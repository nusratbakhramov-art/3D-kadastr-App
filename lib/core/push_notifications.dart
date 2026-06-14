import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import '../features/auth/auth_storage.dart';
import '../features/notifications/notifications_api.dart';
import 'api_config.dart';
import 'app_navigation.dart';

/// Background isolate handler — app fonда yoki o'chgan holatda FCM xabari
/// kelganda chaqiriladi. Bizning xabarlarda `notification` payload bor, shuning
/// uchun OS bildirishnomани o'zi ko'rsatadi — bu yerda qo'shimcha ish kerak
/// emas (hook majburiy, top-level + vm:entry-point bo'lishi shart).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

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
      await Firebase.initializeApp();
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

    // Ruxsat (iOS + Android 13+).
    try {
      await messaging.requestPermission(alert: true, badge: true, sound: true);
    } catch (_) {}

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

    // Joriy tokenni backendga yuborish (login qilingan bo'lsa).
    await syncToken();
  }

  /// Login bo'lgandan keyin yoki bootstrap'da tokenni backendga yuboradi.
  static Future<void> syncToken() async {
    if (!_started) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _sendTokenToBackend(token);
    } catch (_) {}
  }

  static Future<void> _sendTokenToBackend(String token) async {
    final session = await _authStorage.loadSession();
    final auth = session.token;
    if (auth == null) return; // login qilmagan — login'da qayta yuboriladi
    try {
      await http
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
    } catch (_) {}
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
    // Hozircha barcha xabarnomalar "Arizalar" bo'limiga olib boradi.
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
