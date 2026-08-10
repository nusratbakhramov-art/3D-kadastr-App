import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../features/market/api_marketplace_service.dart';
import '../features/market/listing_detail_screen.dart';
import '../features/payments/payment_result_screen.dart';

/// MaterialApp navigatorKey — deep-link'dan (context'siz) navigatsiya uchun.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// iOS Universal Links: to'lovdan keyin Payme `c=https://api.3dkadastr.uz/
/// pay-return/{id}` ga qaytaradi → iOS appni shu link bilan ochadi → bu yerda
/// ushlanib [PaymentResultScreen] ochiladi (status polling).
class PaymentDeepLinks {
  PaymentDeepLinks._();

  static final AppLinks _appLinks = AppLinks();
  static StreamSubscription<Uri>? _sub;

  /// Payme checkout ochilganda boshlangan to'lov id'si. App fonдан qaytganda
  /// (native Payme "Yopish"/"‹ app" yoki web `c=`) status tekshiriladi.
  static int? pendingPaymentId;

  /// Hozir ko'rsatilayotgan natija ekrani id'si (ikki marta push bo'lmasligi —
  /// universal link va lifecycle ikkalasi ham ishlasa).
  static int? _activeResultId;

  /// App ishga tushganda bir marta chaqiriladi.
  static void init() {
    _sub ??= _appLinks.uriLinkStream.listen(_handle, onError: (_) {});
    // Cold start: app aynan universal link bilan ochilgan bo'lsa.
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handle(uri);
    });
  }

  /// App fonдан qaytganda (lifecycle resumed) — kutilayotgan to'lov bo'lsa
  /// natija ekranini ochadi (status polling). Native Payme appdan qaytishni
  /// qoplaydi (u `c=` universal link'ni ochmaydi).
  static void onResumed() {
    final id = pendingPaymentId;
    if (id != null) openResult(id);
  }

  static void _handle(Uri uri) {
    final seg = uri.pathSegments;
    // Marketplace e'loni: https://api.3dkadastr.uz/market/{id} yoki
    // kadastr3d://market/{id} — ulashilgan havolani bosgan foydalanuvchi
    // to'g'ridan-to'g'ri shu e'lon sahifasiga tushadi.
    final m = seg.indexOf('market');
    if (m >= 0 && m + 1 < seg.length) {
      final modelId = int.tryParse(seg[m + 1]);
      if (modelId != null) {
        openMarketListing(modelId);
        return;
      }
    } else if (uri.host == 'market' && seg.isNotEmpty) {
      final modelId = int.tryParse(seg.first);
      if (modelId != null) {
        openMarketListing(modelId);
        return;
      }
    }

    int? id;
    // Universal Link: https://api.3dkadastr.uz/pay-return/{id}
    //   → pathSegments = [pay-return, {id}]
    final i = seg.indexOf('pay-return');
    if (i >= 0 && i + 1 < seg.length) {
      id = int.tryParse(seg[i + 1]);
    } else if (uri.host == 'pay-return' && seg.isNotEmpty) {
      // Custom scheme: kadastr3d://pay-return/{id}
      //   → host = pay-return, pathSegments = [{id}]
      id = int.tryParse(seg.first);
    }
    if (id != null) openResult(id);
  }

  /// Ulashilgan havoladan marketplace e'lonini ochadi.
  ///
  /// E'lon ma'lumoti havolada bo'lmagani uchun avval backenddan olinadi;
  /// olinmasa (o'chirilgan e'lon, tarmoq yo'q) — jimgina e'tiborsiz
  /// qoldiriladi, ilova baribir odatdagidek ochilaveradi.
  static Future<void> openMarketListing(int modelId) async {
    if (_activeListingId == modelId) return; // allaqachon ochilyapti
    _activeListingId = modelId;
    try {
      final listing = await MarketplaceApiService().getModel(modelId);
      final nav = rootNavigatorKey.currentState;
      if (nav == null) return;
      await nav.push(
        MaterialPageRoute<void>(
          builder: (_) => ListingDetailScreen(listing: listing),
        ),
      );
    } catch (_) {
      // e'lon topilmadi / tarmoq xatosi — havola shunchaki ilovani ochadi
    } finally {
      _activeListingId = null;
    }
  }

  static int? _activeListingId;

  /// Natija ekranini ochadi (dedupe). pendingPaymentId tozalanadi.
  static void openResult(int id) {
    pendingPaymentId = null;
    if (_activeResultId == id) return; // allaqachon ko'rsatilyapti
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;
    _activeResultId = id;
    nav
        .push(MaterialPageRoute<void>(
          builder: (_) => PaymentResultScreen(paymentId: id),
        ))
        .then((_) => _activeResultId = null);
  }
}
