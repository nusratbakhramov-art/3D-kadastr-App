import 'package:flutter/material.dart';

/// Payment provider (mirrors backend `PaymentProvider`).
enum PaymentMethod { click, payme, uzum }

/// What the payment was for (mirrors backend `PaymentType`).
enum PaymentType {
  aiValuation,
  marketplacePurchase,
  virtualPropertyView,
  subscription,
  other,
}

/// Payment lifecycle state (mirrors backend `PaymentStatus`).
enum PaymentStatus { pending, processing, completed, failed, cancelled, refunded }

@immutable
class Payment {
  const Payment({
    required this.id,
    required this.type,
    required this.rawType,
    required this.amount,
    required this.method,
    required this.status,
    required this.at,
    this.externalId,
  });

  /// Backend payment id (used as the human "receipt no.").
  final String id;
  final PaymentType type;

  /// Raw backend code (`payment_type`); used as a fallback label when [type]
  /// is [PaymentType.other] so unknown future types still render readably.
  final String rawType;

  /// Amount in so'm.
  final int amount;
  final PaymentMethod method;
  final PaymentStatus status;
  final DateTime at;

  /// Provider-side transaction id (Payme `paycom_id`), when available.
  final String? externalId;

  /// Localised service title for this payment.
  String title(Locale l) =>
      type == PaymentType.other ? _prettifyCode(rawType) : type.label(l);
}

String _prettifyCode(String code) {
  if (code.trim().isEmpty) return '—';
  return code.replaceAll('_', ' ');
}

extension PaymentMethodLabel on PaymentMethod {
  static PaymentMethod fromCode(String p) => switch (p.toLowerCase()) {
    'payme' => PaymentMethod.payme,
    'uzum' => PaymentMethod.uzum,
    _ => PaymentMethod.click,
  };

  String get displayName => switch (this) {
    PaymentMethod.click => 'Click',
    PaymentMethod.payme => 'Payme',
    PaymentMethod.uzum => 'Uzum',
  };

  Color get accent => switch (this) {
    PaymentMethod.click => const Color(0xFF1A73E8),
    PaymentMethod.payme => const Color(0xFF00C2A8),
    PaymentMethod.uzum => const Color(0xFF7B61FF),
  };
}

extension PaymentTypeX on PaymentType {
  static PaymentType fromCode(String code) => switch (code.toLowerCase()) {
    'ai_valuation' => PaymentType.aiValuation,
    'marketplace_purchase' || 'marketplace' => PaymentType.marketplacePurchase,
    'virtual_property_view' ||
    'virtual_property' => PaymentType.virtualPropertyView,
    'subscription' => PaymentType.subscription,
    _ => PaymentType.other,
  };

  IconData get icon => switch (this) {
    PaymentType.aiValuation => Icons.auto_awesome_rounded,
    PaymentType.marketplacePurchase => Icons.storefront_rounded,
    PaymentType.virtualPropertyView => Icons.apartment_rounded,
    PaymentType.subscription => Icons.workspace_premium_rounded,
    PaymentType.other => Icons.receipt_long_rounded,
  };

  String label(Locale l) => switch (this) {
    PaymentType.aiValuation => switch (l.languageCode) {
      'ru' => 'AI-оценка',
      'en' => 'AI valuation',
      _ => 'AI baholash',
    },
    PaymentType.marketplacePurchase => switch (l.languageCode) {
      'ru' => 'Покупка в маркетплейсе',
      'en' => 'Marketplace purchase',
      _ => 'Marketplace xaridi',
    },
    PaymentType.virtualPropertyView => switch (l.languageCode) {
      'ru' => 'Виртуальный объект',
      'en' => 'Virtual property',
      _ => 'Virtual obyekt',
    },
    PaymentType.subscription => switch (l.languageCode) {
      'ru' => 'Подписка',
      'en' => 'Subscription',
      _ => 'Obuna',
    },
    // Unknown codes fall back to the prettified raw code via Payment.title().
    PaymentType.other => '',
  };
}

extension PaymentStatusX on PaymentStatus {
  static PaymentStatus fromCode(String code) => switch (code.toLowerCase()) {
    'completed' => PaymentStatus.completed,
    'processing' => PaymentStatus.processing,
    'failed' => PaymentStatus.failed,
    'cancelled' || 'canceled' => PaymentStatus.cancelled,
    'refunded' => PaymentStatus.refunded,
    _ => PaymentStatus.pending,
  };

  bool get isCompleted => this == PaymentStatus.completed;

  /// Completed is the expected, default state — kept badge-free in lists so the
  /// status colour budget is spent only on the rows that need attention.
  bool get isNoteworthy => this != PaymentStatus.completed;

  Color get color => switch (this) {
    PaymentStatus.completed => const Color(0xFF1FA85A),
    PaymentStatus.pending || PaymentStatus.processing => const Color(0xFFE0922A),
    PaymentStatus.failed => const Color(0xFFE0492A),
    PaymentStatus.cancelled => const Color(0xFF8A9097),
    PaymentStatus.refunded => const Color(0xFF1A73E8),
  };

  IconData get icon => switch (this) {
    PaymentStatus.completed => Icons.check_circle_rounded,
    PaymentStatus.pending ||
    PaymentStatus.processing => Icons.schedule_rounded,
    PaymentStatus.failed => Icons.error_rounded,
    PaymentStatus.cancelled => Icons.cancel_rounded,
    PaymentStatus.refunded => Icons.replay_rounded,
  };

  String label(Locale l) => switch (this) {
    PaymentStatus.completed => switch (l.languageCode) {
      'ru' => 'Оплачено',
      'en' => 'Paid',
      _ => 'To‘langan',
    },
    PaymentStatus.pending => switch (l.languageCode) {
      'ru' => 'В ожидании',
      'en' => 'Pending',
      _ => 'Kutilmoqda',
    },
    PaymentStatus.processing => switch (l.languageCode) {
      'ru' => 'В обработке',
      'en' => 'Processing',
      _ => 'Jarayonda',
    },
    PaymentStatus.failed => switch (l.languageCode) {
      'ru' => 'Ошибка',
      'en' => 'Failed',
      _ => 'Amalga oshmadi',
    },
    PaymentStatus.cancelled => switch (l.languageCode) {
      'ru' => 'Отменён',
      'en' => 'Cancelled',
      _ => 'Bekor qilindi',
    },
    PaymentStatus.refunded => switch (l.languageCode) {
      'ru' => 'Возврат',
      'en' => 'Refunded',
      _ => 'Qaytarildi',
    },
  };
}

/// Localised currency unit (so'm / сум / soum).
String soumLabel(Locale l) => switch (l.languageCode) {
  'ru' => 'сум',
  'en' => 'soum',
  _ => 'so‘m',
};

/// Groups a whole-number so'm amount with thin-space thousands separators.
/// 1000 -> "1 000", 250000 -> "250 000".
String groupDigits(int value) {
  final negative = value < 0;
  final s = value.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '${negative ? '-' : ''}$buf';
}

/// Grouped amount + localised currency unit, e.g. "250 000 so‘m".
String formatMoney(int value, Locale l) => '${groupDigits(value)} ${soumLabel(l)}';
