/// Backend AI baholash javobi.
library;

class AiValuationAdjustment {
  const AiValuationAdjustment({
    required this.name,
    required this.percent,
    required this.delta,
  });

  factory AiValuationAdjustment.fromJson(Map<String, dynamic> json) =>
      AiValuationAdjustment(
        name: json['name'] as String,
        percent: (json['percent'] as num).toDouble(),
        delta: (json['delta'] as num).toDouble(),
      );

  /// Adjustment nomi (UI'da chap tomonda ko'rinadi).
  final String name;

  /// Foiz qiymati. Ijobiy = qimmatlashtirish, salbiy = arzonlashtirish.
  final double percent;

  /// So'mdagi mutloq o'zgarish (UI'da o'ng tomonda ko'rinadi).
  final double delta;
}

class AiApproachResult {
  const AiApproachResult({
    required this.name,
    required this.value,
    required this.weight,
    required this.weighted,
    this.breakdown,
  });

  factory AiApproachResult.fromJson(Map<String, dynamic> json) =>
      AiApproachResult(
        name: json['name'] as String,
        value: json['value'] == null
            ? null
            : (json['value'] as num).toDouble(),
        weight: (json['weight'] as num? ?? 0).toDouble(),
        weighted: (json['weighted'] as num? ?? 0).toDouble(),
        breakdown: json['breakdown'] as Map<String, dynamic>?,
      );

  /// Yondashuv nomi ("Xarajat yondashuvi", "Daromad yondashuvi", "Qiyoslash
  /// yondashuvi").
  final String name;

  /// Yondashuv qiymati (so'm). Hisoblab bo'lmasa null.
  final double? value;

  /// Yakuniy hisobdagi og'irlik (0..1).
  final double weight;

  /// value × weight — yakuniy qiymatga qo'shilgan ulush.
  final double weighted;

  /// Hisob ichidagi oraliq qiymatlar (volume, indekslar va h.k.).
  final Map<String, dynamic>? breakdown;
}

class AiValuationBreakdown {
  const AiValuationBreakdown({
    required this.basePricePerSqm,
    required this.baseValue,
    required this.adjustments,
    required this.method,
    required this.approaches,
  });

  factory AiValuationBreakdown.fromJson(Map<String, dynamic> json) =>
      AiValuationBreakdown(
        basePricePerSqm: (json['base_price_per_sqm'] as num).toDouble(),
        baseValue: (json['base_value'] as num).toDouble(),
        adjustments: ((json['adjustments'] as List?) ?? const [])
            .map((e) => AiValuationAdjustment.fromJson(
                  e as Map<String, dynamic>,
                ))
            .toList(),
        method: json['method'] as String? ?? 'Uch yondashuv',
        approaches: ((json['approaches'] as List?) ?? const [])
            .map((e) => AiApproachResult.fromJson(
                  e as Map<String, dynamic>,
                ))
            .toList(),
      );

  /// Comparables median price/m² (so'm/m²).
  final double basePricePerSqm;

  /// Maydon × asosiy narx (adjustment'siz, so'm).
  final double baseValue;

  final List<AiValuationAdjustment> adjustments;
  final String method;

  /// 3 yondashuv (xarajat / daromad / qiyoslash) batafsil natijasi.
  /// Ba'zi yondashuvlar `value=null` bo'lishi mumkin (ma'lumot yetarli emas).
  final List<AiApproachResult> approaches;
}

class AiValuationResult {
  const AiValuationResult({
    required this.estimatedValue,
    required this.currency,
    required this.rangeLow,
    required this.rangeHigh,
    required this.confidence,
    required this.comparablesCount,
    required this.breakdown,
    required this.fallbackUsed,
    this.fallbackReason,
    this.historyId,
    this.summary,
  });

  factory AiValuationResult.fromJson(Map<String, dynamic> json) =>
      AiValuationResult(
        estimatedValue: (json['estimated_value'] as num).toDouble(),
        currency: json['currency'] as String? ?? 'UZS',
        rangeLow: (json['range_low'] as num).toDouble(),
        rangeHigh: (json['range_high'] as num).toDouble(),
        confidence: (json['confidence'] as num).toDouble(),
        comparablesCount: (json['comparables_count'] as num).toInt(),
        breakdown: AiValuationBreakdown.fromJson(
          json['breakdown'] as Map<String, dynamic>,
        ),
        fallbackUsed: json['fallback_used'] as bool? ?? false,
        fallbackReason: json['fallback_reason'] as String?,
        historyId: json['history_id'] as int?,
        summary: json['summary'] as String?,
      );

  /// Yakuniy taxminiy qiymat (so'm).
  final double estimatedValue;
  final String currency;

  /// Pastki/yuqori chegara (±8% asosiy qiymatdan).
  final double rangeLow;
  final double rangeHigh;

  /// 0..1 oralig'ida ishonchlik. 0.4 dan past = past, 0.7+ = ishonchli.
  final double confidence;

  /// Hisoblashda ishlatilgan analoglar soni.
  final int comparablesCount;

  final AiValuationBreakdown breakdown;

  /// `true` — bu viloyatda yetarli e'lon yo'q edi, kengaytirilgan filter
  /// ishlatildi. UI'da warning ko'rsatish kerak.
  final bool fallbackUsed;
  final String? fallbackReason;

  /// `ai_valuation_history` jadvalidagi yozuv ID'si (saqlangan bo'lsa).
  final int? historyId;

  /// LLM (OpenAI) yaratgan natija izohi (4-6 paragraf, foydalanuvchi tilida).
  /// Backend OpenAI kalit yo'q bo'lsa yoki xato bo'lsa null keladi.
  final String? summary;
}
