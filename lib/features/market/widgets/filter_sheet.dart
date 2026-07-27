import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../data/market_regions_store.dart';
import '../models/market_filters.dart';
import '../models/market_region_node.dart';

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
  late RangeValues _area;
  late RangeValues _floor;
  late Set<String> _districts;
  String _regionQuery = '';
  final Set<String> _expanded = {};
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _area = RangeValues(
      (widget.initial.areaMin ?? kMarketAreaFloor).toDouble(),
      (widget.initial.areaMax ?? kMarketAreaCeil).toDouble(),
    );
    _floor = RangeValues(
      (widget.initial.floorMin ?? kMarketFloorFloor).toDouble(),
      (widget.initial.floorMax ?? kMarketFloorCeil).toDouble(),
    );
    _districts = {...widget.initial.districts};
  }

  void _reset() {
    HapticFeedback.selectionClick();
    setState(() {
      _area = const RangeValues(kMarketAreaFloor + 0.0, kMarketAreaCeil + 0.0);
      _floor =
          const RangeValues(kMarketFloorFloor + 0.0, kMarketFloorCeil + 0.0);
      _districts.clear();
      _regionQuery = '';
      _searchCtrl.clear();
    });
  }

  void _apply() {
    HapticFeedback.lightImpact();
    final areaDefault =
        _area.start <= kMarketAreaFloor && _area.end >= kMarketAreaCeil;
    final floorDefault =
        _floor.start <= kMarketFloorFloor && _floor.end >= kMarketFloorCeil;
    final result = MarketFilters(
      // Narx filtri hozircha yashirilgan — qiymat o'rnatilmaydi.
      areaMin: areaDefault ? null : _area.start.round(),
      areaMax: areaDefault ? null : _area.end.round(),
      floorMin: floorDefault ? null : _floor.start.round(),
      floorMax: floorDefault ? null : _floor.end.round(),
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
                        tr(l, 'market.filter.title'),
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
                        tr(l, 'market.filter.reset'),
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
                    // Narx (price) filtri hozircha yashirilgan — kelajakda
                    // admin paneldan dinamik filtrlar bilan qaytariladi.
                    _SectionLabel(text: tr(l, 'market.filter.area'), color: fg),
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
                    const SizedBox(height: 14),
                    _SectionLabel(text: tr(l, 'market.filter.floor'), color: fg),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${_floor.start.round()} — ${_floor.end.round()} ${tr(l, 'market.filter.floor_unit')}',
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
                        values: _floor,
                        min: kMarketFloorFloor.toDouble(),
                        max: kMarketFloorCeil.toDouble(),
                        divisions: kMarketFloorCeil - kMarketFloorFloor,
                        onChanged: (v) => setState(() => _floor = v),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _SectionLabel(
                              text: tr(l, 'market.filter.region'), color: fg),
                        ),
                        if (_districts.isNotEmpty)
                          Text(
                            '${_districts.length} ${tr(l, 'market.filter.selected_suffix')}',
                            style: TextStyle(
                              fontFamily: 'MTSCompact',
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: AppColors.splashGreen,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _RegionSearchField(
                      controller: _searchCtrl,
                      hint: tr(l, 'market.filter.search_region'),
                      fg: fg,
                      bg: chipBg,
                      onChanged: (v) => setState(() => _regionQuery = v),
                    ),
                    const SizedBox(height: 12),
                    // Viloyat→tuman daraxti (akkordeon). Daraxt hali yuklanmagan
                    // bo'lsa, tekis chiplar (eski ro'yxat) fallback sifatida.
                    ValueListenableBuilder<List<MarketRegionNode>>(
                      valueListenable: marketRegionTreeNotifier,
                      builder: (context, tree, _) {
                        if (tree.isEmpty) {
                          return ValueListenableBuilder<List<String>>(
                            valueListenable: marketRegionsNotifier,
                            builder: (context, regions, _) =>
                                _flatChips(regions, l, fg, chipBg),
                          );
                        }
                        return _regionAccordion(tree, l, fg, muted, chipBg);
                      },
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
                            tr(l, 'market.filter.apply'),
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

  // ── Hudud filtri ─────────────────────────────────────────────────────────
  void _toggleDistrict(String d) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_districts.add(d)) _districts.remove(d);
    });
  }

  void _toggleRegionAll(MarketRegionNode node) {
    HapticFeedback.selectionClick();
    setState(() {
      final all = node.districts.toSet();
      if (all.isNotEmpty && all.every(_districts.contains)) {
        _districts.removeAll(all);
      } else {
        _districts.addAll(all);
      }
    });
  }

  /// Tekis chiplar — daraxt yuklanmaganidagi zaxira ko'rinish.
  Widget _flatChips(List<String> regions, Locale l, Color fg, Color bg) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final d in regions)
          _DistrictChip(
            label: _districtLabel(l, d),
            selected: _districts.contains(d),
            onTap: () => _toggleDistrict(d),
            fg: fg,
            bg: bg,
          ),
      ],
    );
  }

  Widget _regionAccordion(
    List<MarketRegionNode> tree,
    Locale l,
    Color fg,
    Color muted,
    Color bg,
  ) {
    final q = _regionQuery.trim().toLowerCase();
    final divider = fg.withValues(alpha: 0.08);
    final rows = <Widget>[];

    rows.add(_FilterRow(
      label: tr(l, 'market.filter.all_regions'),
      fg: fg,
      weight: FontWeight.w600,
      onTap: () {
        HapticFeedback.selectionClick();
        setState(_districts.clear);
      },
      trailing: _RadioDot(selected: _districts.isEmpty),
    ));

    for (final node in tree) {
      final regionMatch = q.isEmpty || node.name.toLowerCase().contains(q);
      final matched = (q.isEmpty || regionMatch)
          ? node.districts
          : node.districts
              .where((d) => d.toLowerCase().contains(q))
              .toList(growable: false);
      if (!regionMatch && matched.isEmpty) continue;

      final expanded =
          _expanded.contains(node.name) || (q.isNotEmpty && matched.isNotEmpty);
      final selectedCount = node.districts.where(_districts.contains).length;

      rows.add(_FilterRow(
        label: node.name,
        fg: fg,
        weight: FontWeight.w600,
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            if (!_expanded.add(node.name)) _expanded.remove(node.name);
          });
        },
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selectedCount > 0) _CountBadge(count: selectedCount),
            const SizedBox(width: 6),
            Icon(
              expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 22,
              color: muted,
            ),
          ],
        ),
      ));

      if (expanded && node.districts.isNotEmpty) {
        final all = node.districts.toSet();
        final allSelected = all.every(_districts.contains);
        rows.add(_FilterRow(
          label: tr(l, 'market.filter.select_all'),
          fg: AppColors.splashGreen,
          weight: FontWeight.w600,
          leftPad: 32,
          onTap: () => _toggleRegionAll(node),
          trailing: _CheckMark(selected: allSelected),
        ));
        for (final d in matched) {
          rows.add(_FilterRow(
            label: d,
            fg: fg,
            leftPad: 32,
            onTap: () => _toggleDistrict(d),
            trailing: _CheckMark(selected: _districts.contains(d)),
          ));
        }
      }
    }

    if (rows.length == 1 && q.isNotEmpty) {
      rows.add(_FilterRow(
        label: tr(l, 'market.filter.no_results'),
        fg: muted,
        onTap: () {},
      ));
    }

    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) children.add(Divider(height: 1, thickness: 1, color: divider));
      children.add(rows[i]);
    }

    return Container(
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
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
}

/// Localized display label for a canonical district value. The value stored
/// in the filter set stays the original (used as the query/match key); only
/// the shown prose is routed through the backend-driven bundle.
String _districtLabel(Locale l, String canonical) {
  final key = switch (canonical) {
    'Yashnabod tumani' => 'market.filter.district_yashnabod',
    'Mirzo Ulug\'bek tumani' => 'market.filter.district_mirzo_ulugbek',
    'Yunusobod tumani' => 'market.filter.district_yunusobod',
    'Chilonzor tumani' => 'market.filter.district_chilonzor',
    'Sergeli tumani' => 'market.filter.district_sergeli',
    _ => null,
  };
  return key == null ? canonical : tr(l, key);
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

/// Akkordeon ichidagi bitta qator (hudud / tuman / "barchasi").
class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.label,
    required this.fg,
    required this.onTap,
    this.trailing,
    this.leftPad = 16,
    this.weight = FontWeight.w500,
  });

  final String label;
  final Color fg;
  final VoidCallback onTap;
  final Widget? trailing;
  final double leftPad;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: EdgeInsets.fromLTRB(leftPad, 12, 14, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: weight,
                  fontSize: 15,
                  height: 1.25,
                  color: fg,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// "Barcha hududlar" uchun radio nuqta.
class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.splashGreen : const Color(0xFFB4B9BF),
          width: 2,
        ),
        color: selected ? AppColors.splashGreen : Colors.transparent,
      ),
      child: selected
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : null,
    );
  }
}

/// Tuman tanlash belgisi (checkbox o'rnida yengil check).
class _CheckMark extends StatelessWidget {
  const _CheckMark({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected ? AppColors.splashGreen : const Color(0xFFB4B9BF),
          width: 2,
        ),
        color: selected ? AppColors.splashGreen : Colors.transparent,
      ),
      child: selected
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : null,
    );
  }
}

/// Viloyat qatorida tanlangan tumanlar soni.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.splashGreen,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontFamily: 'MTSCompact',
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: AppColors.buttonTextBlack,
        ),
      ),
    );
  }
}

class _RegionSearchField extends StatelessWidget {
  const _RegionSearchField({
    required this.controller,
    required this.hint,
    required this.fg,
    required this.bg,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final Color fg;
  final Color bg;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      style: TextStyle(fontFamily: 'MTSText', fontSize: 14.5, color: fg),
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: Icon(Icons.search_rounded, size: 20, color: fg.withValues(alpha: 0.5)),
        hintText: hint,
        hintStyle: TextStyle(
          fontFamily: 'MTSText',
          fontSize: 14.5,
          color: fg.withValues(alpha: 0.45),
        ),
        filled: true,
        fillColor: bg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: fg.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.splashGreen, width: 1.4),
        ),
      ),
    );
  }
}
