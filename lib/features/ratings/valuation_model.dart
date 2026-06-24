import 'package:flutter/material.dart';

@immutable
class Valuation {
  const Valuation({
    required this.id,
    required this.address,
    required this.objectType,
    required this.areaSqm,
    required this.at,
    required this.abcValue,
    required this.marketValue,
    required this.incomeValue,
    required this.finalValue,
    required this.confidence,
  });

  final String id;
  final String address;
  final String objectType;
  final double areaSqm;
  final DateTime at;

  /// All values are stored in so'm (UZS).
  final int abcValue;
  final int marketValue;
  final int? incomeValue;
  final int finalValue;

  /// 0..1 confidence score from the AI engine.
  final double confidence;
}

final List<Valuation> mockValuations = [
  Valuation(
    id: 'v1',
    address: 'Toshkent, Yunusobod tumani, 14-mavze, 7-uy',
    objectType: 'turar joy',
    areaSqm: 64.5,
    at: DateTime.now().subtract(const Duration(days: 1, hours: 4)),
    abcValue: 720000000,
    marketValue: 815000000,
    incomeValue: 760000000,
    finalValue: 798000000,
    confidence: 0.86,
  ),
  Valuation(
    id: 'v2',
    address: 'Toshkent, Sergeli tumani, Quruvchilar k., 22a',
    objectType: 'turar joy',
    areaSqm: 48.0,
    at: DateTime.now().subtract(const Duration(days: 4)),
    abcValue: 410000000,
    marketValue: 465000000,
    incomeValue: null,
    finalValue: 452000000,
    confidence: 0.74,
  ),
  Valuation(
    id: 'v3',
    address: 'Samarqand sh., Registon ko‘chasi, 3-uy',
    objectType: 'noturar joy',
    areaSqm: 92.0,
    at: DateTime.now().subtract(const Duration(days: 12)),
    abcValue: 980000000,
    marketValue: 1120000000,
    incomeValue: 1050000000,
    finalValue: 1085000000,
    confidence: 0.91,
  ),
  Valuation(
    id: 'v4',
    address: 'Buxoro sh., Bahouddin Naqshband ko‘chasi, 11',
    objectType: 'sanoat obyekti',
    areaSqm: 540.0,
    at: DateTime.now().subtract(const Duration(days: 28)),
    abcValue: 2200000000,
    marketValue: 2480000000,
    incomeValue: 2950000000,
    finalValue: 2680000000,
    confidence: 0.68,
  ),
];

String formatSum(int value) {
  final negative = value < 0;
  final s = value.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    // Group thousands counted from the RIGHT, so 1000 -> "1 000" and
    // 50000 -> "50 000" (the previous left-to-right logic broke any amount
    // whose digit-count wasn't a multiple of 3, e.g. "100 0").
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '${negative ? '-' : ''}${buf.toString()} so‘m';
}

String formatShortDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
