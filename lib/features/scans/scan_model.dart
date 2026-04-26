import 'package:flutter/material.dart';

enum ScanStatus { uploaded, processing, valued }

@immutable
class ScanItem {
  const ScanItem({
    required this.id,
    required this.cadastreNo,
    required this.address,
    required this.objectType,
    required this.totalAreaSqm,
    required this.livingAreaSqm,
    required this.accuracyCm,
    required this.cadastreValueUzs,
    required this.status,
    required this.at,
  });

  final String id;
  final String cadastreNo;
  final String address;
  final String objectType;
  final double totalAreaSqm;
  final double livingAreaSqm;
  final double accuracyCm;
  final int cadastreValueUzs;
  final ScanStatus status;
  final DateTime at;
}

final List<ScanItem> mockScans = [
  ScanItem(
    id: 's1',
    cadastreNo: '10:09:01:01:0742:00012',
    address: 'Toshkent, Yunusobod tumani, 14-mavze, 7-uy',
    objectType: 'turar joy',
    totalAreaSqm: 64.5,
    livingAreaSqm: 48.0,
    accuracyCm: 1.8,
    cadastreValueUzs: 612000000,
    status: ScanStatus.valued,
    at: DateTime.now().subtract(const Duration(days: 1)),
  ),
  ScanItem(
    id: 's2',
    cadastreNo: '10:14:03:08:0124:00045',
    address: 'Toshkent, Sergeli tumani, Quruvchilar k., 22a',
    objectType: 'turar joy',
    totalAreaSqm: 48.0,
    livingAreaSqm: 36.0,
    accuracyCm: 2.4,
    cadastreValueUzs: 365000000,
    status: ScanStatus.processing,
    at: DateTime.now().subtract(const Duration(days: 2)),
  ),
  ScanItem(
    id: 's3',
    cadastreNo: '07:01:02:01:0058:00309',
    address: 'Samarqand sh., Registon ko‘chasi, 3-uy',
    objectType: 'noturar joy',
    totalAreaSqm: 92.0,
    livingAreaSqm: 0,
    accuracyCm: 1.5,
    cadastreValueUzs: 980000000,
    status: ScanStatus.uploaded,
    at: DateTime.now().subtract(const Duration(days: 3)),
  ),
  ScanItem(
    id: 's4',
    cadastreNo: '03:01:08:11:1212:00078',
    address: 'Buxoro sh., Bahouddin Naqshband ko‘chasi, 11',
    objectType: 'sanoat obyekti',
    totalAreaSqm: 540.0,
    livingAreaSqm: 0,
    accuracyCm: 2.0,
    cadastreValueUzs: 1840000000,
    status: ScanStatus.valued,
    at: DateTime.now().subtract(const Duration(days: 9)),
  ),
];
