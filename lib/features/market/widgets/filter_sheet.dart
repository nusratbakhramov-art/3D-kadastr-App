import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import '../models/market_filters.dart';

Future<MarketFilters?> showMarketFilterSheet(
  BuildContext context, {
  required MarketFilters initial,
}) {
  return showModalBottomSheet<MarketFilters>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (_) => _FilterSheet(initial: initial),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial});
  final MarketFilters initial;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late RangeValues _price;
  late RangeValues _area;
  late Set<String> _districts;

  @override
  void initState() {
    super.initState();
    _price = RangeValues(
      (widget.initial.priceMin ?? kMarketPriceFloor).toDouble(),
      (widget.initial.priceMax ?? kMarketPriceCeil).toDouble(),
    );
    _area = RangeValues(
      (widget.initial.areaMin ?? kMarketAreaFloor).toDouble(),
      (widget.initial.areaMax ?? kMarketAreaCeil).toDouble(),
    );
    _districts = {...widget.initial.districts};
  }

  void _reset() {
    HapticFeedback.selectionClick();
    setState(() {
      _price = const RangeValues(
        kMarketPriceFloor + 0.0,
        kMarketPriceCeil + 0.0,
      );
      _area = const RangeValues(kMarketAreaFloor + 0.0, kMarketAreaCeil + 0.0);
      _districts.clear();
    });
  }

  void _apply() {
    HapticFeedback.lightImpact();
    final priceDefault =
        _price.start <= kMarketPriceFloor && _price.end >= kMarketPriceCeil;
    final areaDefault =
        _area.start <= kMarketAreaFloor && _area.end >= kMarketAreaCeil;
    final result = MarketFilters(
      priceMin: priceDefault ? null : _price.start.round(),
      priceMax: priceDefault ? null : _price.end.round(),
      areaMin: areaDefault ? null : _area.start.round(),
      areaMax: areaDefault ? null : _area.end.round(),
      districts: Set.unmodifiable(_districts),
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0E1A12) : Colors.white;
    final fg = isDark ? Colors.white : AppColors.textBlack;
    final muted = fg.withValues(alpha: 0.6);
    final chipBg = isDark ? const Color(0xFF121617) : const Color(0xFFF4F4F4);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _FilterStrings.title(l),
                        style: TextStyle(
                          fontFamily: 'MTSCompact',
                          fontWeight: FontWeight.w700,
                          fontSize: 22,
                          height: 1.3,
                          color: fg,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _reset,
                      child: Text(
                        _FilterStrings.reset(l),
                        style: TextStyle(
                          fontFamily: 'MTSCompact',
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                          color: muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  children: [
                    _SectionLabel(text: _FilterStrings.price(l), color: fg),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${_fmtInt(_price.start.round())} — ${_fmtInt(_price.end.round())} UZS',
                        style: TextStyle(
                          fontFamily: 'MTSCompact',
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                          color: muted,
                        ),
                      ),
                    ),
                    SliderTheme(
                      data: _sliderTheme(fg),
                      child: RangeSlider(
                        values: _price,
                        min: kMarketPriceFloor.toDouble(),
                        max: kMarketPriceCeil.toDouble(),
                        divisions: 40,
                        onChanged: (v) => setState(() => _price = v),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _SectionLabel(text: _FilterStrings.area(l), color: fg),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${_area.start.round()} — ${_area.end.round()} m²',
                        style: TextStyle(
                          fontFamily: 'MTSCompact',
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                          color: muted,
                        ),
                      ),
                    ),
                    SliderTheme(
                      data: _sliderTheme(fg),
                      child: RangeSlider(
                        values: _area,
                        min: kMarketAreaFloor.toDouble(),
                        max: kMarketAreaCeil.toDouble(),
                        divisions: 34,
                        onChanged: (v) => setState(() => _area = v),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _SectionLabel(text: _FilterStrings.districts(l), color: fg),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final d in kMarketDistricts)
                          _DistrictChip(
                            label: _FilterStrings.district(l, d),
                            selected: _districts.contains(d),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                if (_districts.contains(d)) {
                                  _districts.remove(d);
                                } else {
                                  _districts.add(d);
                                }
                              });
                            },
                            fg: fg,
                            bg: chipBg,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Material(
                    color: AppColors.splashGreen,
                    borderRadius: BorderRadius.circular(999),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _apply,
                      child: SizedBox(
                        height: 52,
                        child: Center(
                          child: Text(
                            _FilterStrings.apply(l),
                            style: const TextStyle(
                              fontFamily: 'MTSCompact',
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: AppColors.buttonTextBlack,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  SliderThemeData _sliderTheme(Color fg) => SliderThemeData(
    activeTrackColor: AppColors.splashGreen,
    inactiveTrackColor: fg.withValues(alpha: 0.12),
    thumbColor: AppColors.splashGreen,
    overlayColor: AppColors.splashGreen.withValues(alpha: 0.12),
    rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 10),
    trackHeight: 4,
    showValueIndicator: ShowValueIndicator.never,
  );

  String _fmtInt(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      buf.write(s[i]);
      final remaining = s.length - i - 1;
      if (remaining > 0 && remaining % 3 == 0) buf.write(' ');
    }
    return buf.toString();
  }
}

class _FilterStrings {
  const _FilterStrings._();

  static String title(Locale l) => switch (l.languageCode) {
    'ru' => 'Фильтры',
    'en' => 'Filters',
    _ => 'Filtrlar',
  };
  static String reset(Locale l) => switch (l.languageCode) {
    'ru' => 'Очистить',
    'en' => 'Clear',
    _ => 'Tozalash',
  };
  static String price(Locale l) => switch (l.languageCode) {
    'ru' => 'Цена (UZS)',
    'en' => 'Price (UZS)',
    _ => 'Narx (UZS)',
  };
  static String area(Locale l) => switch (l.languageCode) {
    'ru' => 'Площадь (м²)',
    'en' => 'Area (m²)',
    _ => 'Maydon (m²)',
  };
  static String districts(Locale l) => switch (l.languageCode) {
    'ru' => 'Районы',
    'en' => 'Districts',
    _ => 'Tumanlar',
  };
  static String apply(Locale l) => switch (l.languageCode) {
    'ru' => 'Применить',
    'en' => 'Apply',
    _ => 'Qo‘llash',
  };

  /// Localized display label for a canonical district value. The value stored
  /// in the filter set stays the original (used as the query/match key).
  static String district(Locale l, String canonical) =>
      switch (l.languageCode) {
        'ru' => switch (canonical) {
          'Yashnabod tumani' => 'Яшнабадский район',
          'Mirzo Ulug\'bek tumani' => 'Мирзо-Улугбекский район',
          'Yunusobod tumani' => 'Юнусабадский район',
          'Chilonzor tumani' => 'Чиланзарский район',
          'Sergeli tumani' => 'Сергелийский район',
          _ => canonical,
        },
        'en' => switch (canonical) {
          'Yashnabod tumani' => 'Yashnabad district',
          'Mirzo Ulug\'bek tumani' => 'Mirzo Ulugbek district',
          'Yunusobod tumani' => 'Yunusabad district',
          'Chilonzor tumani' => 'Chilanzar district',
          'Sergeli tumani' => 'Sergeli district',
          _ => canonical,
        },
        _ => canonical,
      };
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'MTSCompact',
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: color,
        ),
      ),
    );
  }
}

class _DistrictChip extends StatelessWidget {
  const _DistrictChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.fg,
    required this.bg,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.splashGreen : bg,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w500,
              fontSize: 13,
              height: 1.2,
              color: selected ? AppColors.buttonTextBlack : fg,
            ),
          ),
        ),
      ),
    );
  }
}
