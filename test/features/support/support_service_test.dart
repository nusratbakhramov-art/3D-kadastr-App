import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadastr/features/support/support_service.dart';

void main() {
  group('SupportInfo.fromJson', () {
    test('parses all fields', () {
      final info = SupportInfo.fromJson({
        'phone': '+998901234567',
        'email': 'help@example.uz',
        'telegram': '@support',
        'working_hours': '9-18',
      });
      expect(info.phone, '+998901234567');
      expect(info.email, 'help@example.uz');
      expect(info.telegram, '@support');
      expect(info.workingHours, '9-18');
    });

    test('falls back to fallbackPhone when phone is missing or blank', () {
      expect(SupportInfo.fromJson({'phone': ''}).phone,
          SupportService.fallbackPhone);
      expect(SupportInfo.fromJson(<String, dynamic>{}).phone,
          SupportService.fallbackPhone);
    });
  });

  group('SupportService.fetchInfo', () {
    // Runs first so the process-wide cache is still empty → exercises the
    // network-failure fallback path deterministically.
    test('returns fallback phone on non-200 (cache empty)', () async {
      final client = MockClient(
        (_) async => http.Response('boom', 500),
      );
      final info =
          await SupportService(client: client).fetchInfo(forceRefresh: true);
      expect(info.phone, SupportService.fallbackPhone);
    });

    test('returns server phone on 200', () async {
      final client = MockClient(
        (req) async {
          expect(req.url.path, endsWith('/support/info'));
          return http.Response(
            jsonEncode({'phone': '1269', 'email': null}),
            200,
            headers: {'content-type': 'application/json'},
          );
        },
      );
      final info =
          await SupportService(client: client).fetchInfo(forceRefresh: true);
      expect(info.phone, '1269');
    });
  });
}
