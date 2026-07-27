/// Kalkulyator — ABC-UZ construction estimate client.
///
/// Posts a building profile to `POST /abc4/estimate`. The backend builds a
/// smeta, asks the ABC software (over the bridge) to price it, and — if ABC is
/// unreachable — returns a deterministic per-m² approximation instead. The
/// `engine` field on the result says which one came back.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/api_config.dart';
import '../../../core/i18n/app_translations.dart';

// ─── enums (mirror backend app/schemas/construction_estimate.py) ──────────

enum WorkKind {
  construction('construction'),
  renovation('renovation');

  const WorkKind(this.wire);
  final String wire;

  String label(Locale l) => switch (this) {
        WorkKind.construction =>
          tr(l, 'services.data.abc4.work_kind.construction'),
        WorkKind.renovation => tr(l, 'services.data.abc4.work_kind.renovation'),
      };
}

enum BuildingType {
  apartment('apartment'),
  privateHouse('private_house'),
  multiStorey('multi_storey'),
  commercial('commercial'),
  industrial('industrial');

  const BuildingType(this.wire);
  final String wire;

  String label(Locale l) => switch (this) {
        BuildingType.apartment =>
          tr(l, 'services.data.abc4.building.apartment'),
        BuildingType.privateHouse =>
          tr(l, 'services.data.abc4.building.private_house'),
        BuildingType.multiStorey =>
          tr(l, 'services.data.abc4.building.multi_storey'),
        BuildingType.commercial =>
          tr(l, 'services.data.abc4.building.commercial'),
        BuildingType.industrial =>
          tr(l, 'services.data.abc4.building.industrial'),
      };
}

enum WallMaterial {
  brick('brick'),
  block('block'),
  panel('panel'),
  monolith('monolith'),
  wood('wood');

  const WallMaterial(this.wire);
  final String wire;

  String label(Locale l) => switch (this) {
        WallMaterial.brick => tr(l, 'services.data.abc4.wall.brick'),
        WallMaterial.block => tr(l, 'services.data.abc4.wall.block'),
        WallMaterial.panel => tr(l, 'services.data.abc4.wall.panel'),
        WallMaterial.monolith => tr(l, 'services.data.abc4.wall.monolith'),
        WallMaterial.wood => tr(l, 'services.data.abc4.wall.wood'),
      };
}

enum FinishLevel {
  rough('rough'),
  standard('standard'),
  premium('premium');

  const FinishLevel(this.wire);
  final String wire;

  String label(Locale l) => switch (this) {
        FinishLevel.rough => tr(l, 'services.data.abc4.finish.rough'),
        FinishLevel.standard => tr(l, 'services.data.abc4.finish.standard'),
        FinishLevel.premium => tr(l, 'services.data.abc4.finish.premium'),
      };
}

// ─── request / response models ────────────────────────────────────────────

class ConstructionProfile {
  const ConstructionProfile({
    required this.workKind,
    required this.buildingType,
    required this.wallMaterial,
    required this.finishLevel,
    required this.floors,
    required this.areaSqm,
    this.district,
    this.address,
    this.cadastreNumber,
  });

  final WorkKind workKind;
  final BuildingType buildingType;
  final WallMaterial wallMaterial;
  final FinishLevel finishLevel;
  final int floors;
  final double areaSqm;
  final String? district;
  final String? address;
  final String? cadastreNumber;

  Map<String, dynamic> toJson() => {
        'work_kind': workKind.wire,
        'building_type': buildingType.wire,
        'wall_material': wallMaterial.wire,
        'finish_level': finishLevel.wire,
        'floors': floors,
        'area_sqm': areaSqm,
        if (district != null) 'district': district,
        if (address != null) 'address': address,
        if (cadastreNumber != null) 'cadastre_number': cadastreNumber,
      };
}

class EstimateLine {
  const EstimateLine({
    required this.section,
    required this.code,
    required this.unit,
    required this.quantity,
    required this.costUzs,
  });

  final String section;
  final String code;
  final String unit;
  final double quantity;
  final int costUzs;

  factory EstimateLine.fromJson(Map<String, dynamic> j) => EstimateLine(
        section: (j['section'] ?? '') as String,
        code: (j['code'] ?? '') as String,
        unit: (j['unit'] ?? '') as String,
        quantity: (j['quantity'] as num?)?.toDouble() ?? 0,
        costUzs: (j['cost_uzs'] as num?)?.round() ?? 0,
      );
}

class ConstructionEstimateResult {
  const ConstructionEstimateResult({
    required this.totalUzs,
    required this.currency,
    required this.engine,
    required this.lines,
    required this.note,
    required this.areaSqm,
    required this.profileSummary,
  });

  final int totalUzs;
  final String currency;
  final String engine; // "abc4" | "approx"
  final List<EstimateLine> lines;
  final String note;
  final double areaSqm;
  final String profileSummary;

  bool get isAbc => engine == 'abc4';

  factory ConstructionEstimateResult.fromJson(Map<String, dynamic> j) =>
      ConstructionEstimateResult(
        totalUzs: (j['total_uzs'] as num?)?.round() ?? 0,
        currency: (j['currency'] ?? 'UZS') as String,
        engine: (j['engine'] ?? 'approx') as String,
        lines: ((j['lines'] as List<dynamic>?) ?? const [])
            .map((e) => EstimateLine.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        note: (j['note'] ?? '') as String,
        areaSqm: (j['area_sqm'] as num?)?.toDouble() ?? 0,
        profileSummary: (j['profile_summary'] ?? '') as String,
      );
}

class Abc4EstimateException implements Exception {
  Abc4EstimateException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => 'Abc4EstimateException: $message';
}

// ─── service ──────────────────────────────────────────────────────────────

class Abc4EstimateService {
  Abc4EstimateService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  /// The endpoint is public (no auth) and always returns 200 with a usable
  /// number. The timeout is generous because, when a real ABC bridge is
  /// connected, the driver run can take a minute or two.
  Future<ConstructionEstimateResult> estimate(ConstructionProfile profile) async {
    final uri = Uri.parse('$_baseUrl/abc4/estimate');
    final res = await _client
        .post(
          uri,
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(profile.toJson()),
        )
        .timeout(const Duration(seconds: 130));
    if (res.statusCode != 200) {
      throw Abc4EstimateException('HTTP ${res.statusCode}', statusCode: res.statusCode);
    }
    return ConstructionEstimateResult.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }
}
