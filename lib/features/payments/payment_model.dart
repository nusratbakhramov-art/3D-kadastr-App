import 'package:flutter/material.dart';

enum PaymentMethod { click, payme, uzum }

@immutable
class Payment {
  const Payment({
    required this.id,
    required this.title,
    required this.amount,
    required this.method,
    required this.at,
  });

  final String id;
  final String title;
  final int amount;
  final PaymentMethod method;
  final DateTime at;
}

extension PaymentMethodLabel on PaymentMethod {
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

final List<Payment> mockPayments = [
  Payment(
    id: 'p1',
    title: '3D skan xizmati',
    amount: 250000,
    method: PaymentMethod.click,
    at: DateTime.now().subtract(const Duration(days: 1)),
  ),
  Payment(
    id: 'p2',
    title: 'AI baholash hisoboti',
    amount: 120000,
    method: PaymentMethod.payme,
    at: DateTime.now().subtract(const Duration(days: 4)),
  ),
  Payment(
    id: 'p3',
    title: 'Virtual mulk e‘loni (1 oy)',
    amount: 180000,
    method: PaymentMethod.uzum,
    at: DateTime.now().subtract(const Duration(days: 9)),
  ),
  Payment(
    id: 'p4',
    title: '3D skan xizmati',
    amount: 250000,
    method: PaymentMethod.click,
    at: DateTime.now().subtract(const Duration(days: 33)),
  ),
  Payment(
    id: 'p5',
    title: 'AI baholash hisoboti',
    amount: 120000,
    method: PaymentMethod.payme,
    at: DateTime.now().subtract(const Duration(days: 38)),
  ),
  Payment(
    id: 'p6',
    title: 'Premium kategoriya (1 oy)',
    amount: 350000,
    method: PaymentMethod.payme,
    at: DateTime.now().subtract(const Duration(days: 64)),
  ),
];
