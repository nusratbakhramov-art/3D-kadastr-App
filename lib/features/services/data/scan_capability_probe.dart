import 'package:flutter/services.dart';

import '../models/scan_capability.dart';

class ScanCapabilityProbe {
  static const _channel = MethodChannel('kadastr/scan_capability');

  static Future<ScanCapability> probe() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('probe');
    if (raw == null) {
      throw const ScanProbeException('null result from native channel');
    }
    return ScanCapability.fromMap(raw);
  }
}

class ScanProbeException implements Exception {
  const ScanProbeException(this.message);
  final String message;
  @override
  String toString() => 'ScanProbeException: $message';
}
