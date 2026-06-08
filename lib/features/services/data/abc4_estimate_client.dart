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

// ─── enums (mirror backend app/schemas/construction_estimate.py) ──────────

String _pick(Locale l, {required String uz, required String ru, required String en}) =>
    switch (l.languageCode) { 'ru' => ru, 'en' => en, _ => uz };

enum WorkKind {
  construction('construction'),
  renovation('renovation');

  const WorkKind(this.wire);
  final String wire;

  String label(Locale l) => switch (this) {
        WorkKind.construction =>
          _pick(l, uz: 'Qurilish (noldan)', ru: 'Строительство', en: 'New construction'),
        WorkKind.renovation =>
          _pick(l, uz: "Ta'mirlash", ru: 'Ремонт', en: 'Renovation'),
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
          _pick(l, uz: 'Xonadon', ru: 'Квартира', en: 'Apartment'),
        BuildingType.privateHouse => _pick(
            l,
            uz: 'Yakka tartibdagi uy',
            ru: 'Частный дом',
            en: 'Private house',
          ),
        BuildingType.multiStorey => _pick(
            l,
            uz: "Ko'p qavatli bino",
            ru: 'Многоэтажное здание',
            en: 'Multi-storey building',
          ),
        BuildingType.commercial => _pick(
            l,
            uz: 'Tijorat obyekti',
            ru: 'Коммерческий объект',
            en: 'Commercial',
          ),
        BuildingType.industrial =>
          _pick(l, uz: 'Sanoat obyekti', ru: 'Промышленный', en: 'Industrial'),
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
        WallMaterial.brick => _pick(l, uz: "G'isht", ru: 'Кирпич', en: 'Brick'),
        WallMaterial.block =>
          _pick(l, uz: 'Blok (gazoblok)', ru: 'Блок', en: 'Block'),
        WallMaterial.panel => _pick(l, uz: 'Panel', ru: 'Панель', en: 'Panel'),
        WallMaterial.monolith =>
          _pick(l, uz: 'Monolit', ru: 'Монолит', en: 'Monolith'),
        WallMaterial.wood =>
          _pick(l, uz: "Yog'och / karkas", ru: 'Дерево / каркас', en: 'Wood / frame'),
      };
}

enum FinishLevel {
  rough('rough'),
  standard('standard'),
  premium('premium');

  const FinishLevel(this.wire);
  final String wire;

  String label(Locale l) => switch (this) {
        FinishLevel.rough =>
          _pick(l, uz: 'Qora suvoq', ru: 'Черновая', en: 'Rough'),
        FinishLevel.standard =>
          _pick(l, uz: "O'rtacha pardoz", ru: 'Стандарт', en: 'Standard'),
        FinishLevel.premium =>
          _pick(l, uz: 'Lyuks pardoz', ru: 'Премиум', en: 'Premium'),
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
