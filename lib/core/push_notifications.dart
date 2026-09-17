import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import '../features/auth/auth_storage.dart';
import '../features/notifications/notifications_api.dart';
import '../firebase_options.dart';
import 'api_config.dart';
import 'app_navigation.dart';
import 'app_update/app_update_store.dart';
import 'app_update/store_launcher.dart';

/// Background isolate handler — app fonда yoki o'chgan holatda FCM xabari
/// kelganda chaqiriladi. Bizning xabarlarda `notification` payload bor, shuning
/// uchun OS bildirishnomани o'zi ko'rsatadi — bu yerda qo'shimcha ish kerak
/// emas (hook majburiy, top-level + vm:entry-point bo'lishi shart).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Ilova ikonkasidagi badge'ni o'qilmagan bildirishnomalar soni bilan
/// sinxronlaydi. `count == 0` bo'lsa badge TOZALANADI. Backend har push'да
/// `badge=1` yuboradi — foydalanuvchi o'qiganда bu funksiya 0 ga tushirib
/// badge'ni o'chiradi. Qo'llab-quvvatlanmasa / ruxsat bo'lmasa jim qaytadi.
Future<void> syncAppBadge(int count) async {
  try {
    if (await AppBadgePlus.isSupported()) {
      await AppBadgePlus.updateBadge(count < 0 ? 0 : count);
    }
  } catch (_) {}
}

/// FCM push xabarnomalar — initsializatsiya, ruxsat, token ro'yxati va bosish
/// (tap) navigatsiyasi. Firebase sozlanmagan / o'rnatilmagan bo'lsa jim
/// o'chiriladi — app ishlashiga TEGMAYDI.
class PushNotifications {
  PushNotifications._();

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static const AuthStorage _authStorage = AuthStorage();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel',
    'Muhim bildirishnomalar',
    description: "Baholash, to'lov va ariza holati xabarnomalari",
    importance: Importance.high,
  );

  static bool _started = false;

  /// App ishga tushganda bir marta chaqiriladi (main bootstrap).
  static Future<void> init() async {
    if (_started) return;
    _started = true;
    try {
      // iOS: GoogleService-Info.plist bundle'ga qo'shilmagani uchun aniq
      // options bilan init qilamiz. Android: google-services plugin
      // auto-config qiladi (options'siz).
      if (Platform.isIOS) {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.ios);
      } else {
        await Firebase.initializeApp();
      }
    } catch (e) {
      // GoogleService-Info.plist / google-services.json yo'q yoki noto'g'ri —
      // push'siz davom etamiz.
      debugPrint("PushNotifications: Firebase init o'tmadi: $e");
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Local notifications — Android'da foreground heads-up ko'rsatish uchun.
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _local.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: darwinInit),
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        _handleTapData(payload == null ? const {} : _decode(payload));
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    final messaging = FirebaseMessaging.instance;

    // Ruxsat (iOS + Android 13+). Natijani log qilamiz.
    try {
      final settings =
          await messaging.requestPermission(alert: true, badge: true, sound: true);
      debugPrint('PushNotifications: ruxsat = ${settings.authorizationStatus}');
    } catch (e) {
      debugPrint('PushNotifications: requestPermission xato: $e');
    }

    // iOS: app ochiq turganda ham banner ko'rsatilsin.
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Oqimlarni tinglash.
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _handleTapData(m.data));
    messaging.onTokenRefresh.listen(_sendTokenToBackend);

    // Cold start: app aynan push bosilib ochilgan bo'lsa.
    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _handleTapData(initial.data),
      );
    }

    // iOS: FCM token APNs token tayyor bo'lгач beriladi — bir oz kutib olamiz
    // (aks holda app ochilishida getToken null qaytarib, token ro'yxatga
    // tushmay qoladi).
    if (Platform.isIOS) {
      for (var i = 0; i < 12; i++) {
        try {
          final apns = await messaging.getAPNSToken();
          if (apns != null) {
            debugPrint('PushNotifications: APNs token tayyor');
            break;
          }
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }

    // Joriy tokenni backendga yuborish (app ochilganда — login bo'lган bo'lsa).
    await syncToken();
  }

  /// App ochilganда va login'дан keyin tokenni backendga yuboradi.
  static Future<void> syncToken() async {
    if (!_started) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      debugPrint(
        'PushNotifications: FCM token = '
        '${token == null ? "NULL" : "${token.substring(0, 12)}…"}',
      );
      if (token != null) await _sendTokenToBackend(token);
    } catch (e) {
      debugPrint('PushNotifications: getToken xato: $e');
    }
  }

  static Future<void> _sendTokenToBackend(String token) async {
    final session = await _authStorage.loadSession();
    final auth = session.token;
    if (auth == null) {
      debugPrint("PushNotifications: login yo'q — token login'да yuboriladi");
      return; // login qilmagan — login'da qayta yuboriladi
    }
    try {
      final resp = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/devices/register'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $auth',
            },
            body: jsonEncode({
              'token': token,
              'platform': Platform.isIOS ? 'ios' : 'android',
            }),
          )
          .timeout(const Duration(seconds: 12));
      debugPrint('PushNotifications: /devices/register → ${resp.statusCode}');
    } catch (e) {
      debugPrint('PushNotifications: register xato: $e');
    }
  }

  /// Logout — tokenni backenddan o'chiradi (storage tozalanishidan OLDIN
  /// chaqiriladi, auth token kerak).
  static Future<void> unregister(String authToken) async {
    if (!_started) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/devices/unregister'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
            body: jsonEncode({'token': token}),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  static void _onForegroundMessage(RemoteMessage m) {
    // Yangi xabarnoma keldi — ro'yxat + badge'ni yangilaymiz.
    refreshNotifications();
    // iOS banner'ni presentation options ko'rsatadi — Android'da qo'lda.
    if (!Platform.isAndroid) return;
    final n = m.notification;
    if (n == null) return;
    _local.show(
      id: n.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: jsonEncode(m.data),
    );
  }

  static void _handleTapData(Map<String, dynamic> data) {
    // Ilova yangilanishi haqidagi push — do'konni ochamiz. `store_url` push
    // payload'ida keladi (backend `publish_release` qo'shadi); bo'lmasa
    // platforma zaxira havolasi ishlaydi.
    if (data['type'] == 'app_update') {
      final url = data['store_url'];
      openStore(url is String ? url : null);
      // Yangilanish holatini ham darhol yangilaymiz: push kelgan ekan, reliz
      // e'lon qilingan — majburiy bo'lsa ilova ochilishida bloklovchi ekran
      // chiqsin (throttle chetlab o'tiladi).
      unawaited(AppUpdateStore.instance.refresh(force: true));
      return;
    }
    // Qolgan barcha xabarnomalar "Arizalar" bo'limiga olib boradi.
    navigateToApplicationsTab();
  }

  static Map<String, dynamic> _decode(String s) {
    try {
      final m = jsonDecode(s);
      return m is Map ? m.cast<String, dynamic>() : const {};
    } catch (_) {
      return const {};
    }
  }
}
