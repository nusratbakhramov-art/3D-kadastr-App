import 'package:flutter/widgets.dart';

/// Umumiy (takrorlanadigan) UI matnlari — uch tilda (uz/ru/en).
class L {
  const L._();
  static String _s(Locale l, String ru, String en, String uz) =>
      switch (l.languageCode) { 'ru' => ru, 'en' => en, _ => uz };

  static String retry(Locale l) => _s(l, 'Повторить', 'Retry', 'Qayta urinish');
  static String errorOccurred(Locale l) => _s(l, 'Произошла ошибка', 'An error occurred', 'Xatolik yuz berdi');
  static String cancel(Locale l) => _s(l, 'Отмена', 'Cancel', 'Bekor qilish');
  static String add(Locale l) => _s(l, 'Добавить', 'Add', "Qo'shish");
  static String search(Locale l) => _s(l, 'Поиск', 'Search', 'Qidirish');
  static String searchAddress(Locale l) => _s(l, 'Поиск адреса...', 'Search address...', 'Manzilni qidiring...');
  static String roomName(Locale l) => _s(l, 'Название комнаты', 'Room name', 'Xona nomi');
  static String authRequired(Locale l) => _s(l, 'Требуется авторизация', 'Authorization required', 'Avtorizatsiya kerak');
}
