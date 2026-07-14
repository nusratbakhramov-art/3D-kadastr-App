import 'package:flutter/widgets.dart';

import 'payment_deep_links.dart';

/// Push xabarnoma / deep-link bosilganda asosiy tab'ni almashtirish uchun
/// global signal. [MainShell] buni tinglaydi va `-1` dan farqli qiymat kelganda
/// o'sha tab'ga o'tadi (so'ng `-1` ga qaytaradi).
///
/// Cold start (app o'chgan holatdan push bosib ochilsa): [MainShell] hali
/// qurilmagan bo'lishi mumkin — shu sabab qiymat saqlanib turadi, shell
/// initState'da o'qiydi.
final ValueNotifier<int> shellTabRequest = ValueNotifier<int>(-1);

/// Arizalar (Applications) tab indeksi. Xizmatlar tab'i olib tashlangач
/// (Home, Market, Arizalar, Profil) — Arizalar 3-dan 2-ga suriladi.
const int kApplicationsTabIndex = 2;

/// Ochiq ekranlarni yopib, asosiy shell'da "Arizalar" tab'ini ochadi.
void navigateToApplicationsTab() {
  rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
  shellTabRequest.value = kApplicationsTabIndex;
}
