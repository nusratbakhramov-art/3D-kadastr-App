import 'package:flutter/widgets.dart';

import 'i18n/app_translations.dart';

/// Umumiy (takrorlanadigan) UI matnlari — uch tilda (uz/ru/en).
class L {
  const L._();
  static String _s(
    Locale l,
    String key, {
    required String uz,
    required String ru,
    required String en,
  }) => tr(l, key, uz: uz, ru: ru, en: en);

  static String retry(Locale l) =>
      _s(l, 'common.retry', uz: 'Qayta urinish', ru: 'Повторить', en: 'Retry');
  static String errorOccurred(Locale l) => _s(
    l,
    'common.error_occurred',
    uz: 'Xatolik yuz berdi',
    ru: 'Произошла ошибка',
    en: 'An error occurred',
  );
  static String cancel(Locale l) =>
      _s(l, 'common.cancel', uz: 'Bekor qilish', ru: 'Отмена', en: 'Cancel');
  static String add(Locale l) =>
      _s(l, 'common.add', uz: "Qo'shish", ru: 'Добавить', en: 'Add');
  static String search(Locale l) =>
      _s(l, 'common.search', uz: 'Qidirish', ru: 'Поиск', en: 'Search');
  static String searchAddress(Locale l) => _s(
    l,
    'common.search_address',
    uz: 'Manzilni qidiring...',
    ru: 'Поиск адреса...',
    en: 'Search address...',
  );
  static String roomName(Locale l) => _s(
    l,
    'common.room_name',
    uz: 'Xona nomi',
    ru: 'Название комнаты',
    en: 'Room name',
  );
  static String authRequired(Locale l) => _s(
    l,
    'common.auth_required',
    uz: 'Avtorizatsiya kerak',
    ru: 'Требуется авторизация',
    en: 'Authorization required',
  );
}
