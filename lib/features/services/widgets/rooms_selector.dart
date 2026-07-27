/// Xonalarni tanlash komponenti — AI baholashdagi UX (turi chiplari + soni
/// stepperi) qayta ishlatiladigan widget sifatida.
///
/// `showArea: true` bo'lganda har bir xona uchun maydon (m²) maydoni ham
/// ko'rsatiladi (SO'ROVNOMA arxitektura jadvali talab qiladi).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../models/ai_baholash_bundle.dart';

class RoomsSelector extends StatefulWidget {
  const RoomsSelector({
    super.key,
    required this.rooms,
    required this.locale,
    this.onChanged,
    this.title,
    this.subtitle,
    this.showArea = false,
  });

  /// O'zgartiriladigan xonalar ro'yxati (joyida mutatsiya qilinadi).
  final List<AiRoom> rooms;
  final Locale locale;

  /// Har qanday qo'shish/o'chirishdan keyin chaqiriladi.
  final VoidCallback? onChanged;

  /// Ixtiyoriy sarlavha/izoh (null bo'lsa ko'rsatilmaydi).
  final String? title;
  final String? subtitle;

  /// Har bir xona uchun maydon (m²) maydonini ko'rsatish.
  final bool showArea;

  @override
  State<RoomsSelector> createState() => _RoomsSelectorState();
}

class _RoomsSelectorState extends State<RoomsSelector> {
  // Turar (residential / living) vs No-turar (non-residential) grouping.
  static const List<RoomKind> _livingKinds = [
    RoomKind.living,
    RoomKind.bedroom,
    RoomKind.kitchen,
    RoomKind.bathroom,
    RoomKind.hallway,
  ];
  static const List<RoomKind> _nonLivingKinds = [
    RoomKind.balcony,
    RoomKind.storage,
  ];

  final Map<AiRoom, TextEditingController> _counts = {};
  final Map<AiRoom, TextEditingController> _areas = {};
  final TextEditingController _customName = TextEditingController();
  bool _customOpen = false;

  @override
  void initState() {
    super.initState();
    for (final r in widget.rooms) {
      _counts[r] = TextEditingController(text: '${r.count}');
      _areas[r] = TextEditingController(text: r.area?.toString() ?? '');
    }
    _customOpen = widget.rooms.any((r) => r.kind == RoomKind.other);
  }

  @override
  void dispose() {
    for (final c in _counts.values) {
      c.dispose();
    }
    for (final c in _areas.values) {
      c.dispose();
    }
    _customName.dispose();
    super.dispose();
  }

  AiRoom? _standardRoom(RoomKind k) {
    for (final r in widget.rooms) {
      if (r.kind == k && k != RoomKind.other) return r;
    }
    return null;
  }

  void _register(AiRoom room) {
    _counts[room] = TextEditingController(text: '${room.count}');
    _areas[room] = TextEditingController(text: room.area?.toString() ?? '');
  }

  void _toggleStandard(RoomKind k) {
    HapticFeedback.selectionClick();
    final existing = _standardRoom(k);
    setState(() {
      if (existing != null) {
        widget.rooms.remove(existing);
        _counts.remove(existing)?.dispose();
        _areas.remove(existing)?.dispose();
      } else {
        final room = AiRoom(kind: k, count: 1);
        widget.rooms.add(room);
        _register(room);
      }
    });
    widget.onChanged?.call();
  }

  void _addCustom() {
    final name = _customName.text.trim();
    if (name.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      final room = AiRoom(kind: RoomKind.other, name: name, count: 1);
      widget.rooms.add(room);
      _register(room);
      _customName.clear();
    });
    widget.onChanged?.call();
  }

  void _remove(AiRoom room) {
    setState(() {
      widget.rooms.remove(room);
      _counts.remove(room)?.dispose();
      _areas.remove(room)?.dispose();
    });
    widget.onChanged?.call();
  }

  void _setCount(AiRoom room, int value) {
    final v = value.clamp(1, 50);
    room.count = v;
    final ctrl = _counts[room];
    if (ctrl != null && ctrl.text != '$v') {
      ctrl.text = '$v';
      ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

    final selectedKinds = widget.rooms.map((r) => r.kind).toSet();
    final hasCustom = widget.rooms.any((r) => r.kind == RoomKind.other);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.title != null)
          Text(
            widget.title!,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: muted,
            ),
          ),
        if (widget.subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            widget.subtitle!,
            style:
                TextStyle(fontFamily: 'MTSCompact', fontSize: 12, color: muted),
          ),
        ],
        if (widget.title != null || widget.subtitle != null)
          const SizedBox(height: 12),
        _GroupLabel(text: _RoomsSelectorStrings.livingGroup(widget.locale)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final k in _livingKinds)
              _RoomChip(
                label: k.label(widget.locale),
                selected: selectedKinds.contains(k),
                onTap: () => _toggleStandard(k),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _GroupLabel(text: _RoomsSelectorStrings.nonLivingGroup(widget.locale)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final k in _nonLivingKinds)
              _RoomChip(
                label: k.label(widget.locale),
                selected: selectedKinds.contains(k),
                onTap: () => _toggleStandard(k),
              ),
            _RoomChip(
              label: RoomKind.other.label(widget.locale),
              selected: _customOpen || hasCustom,
              onTap: () => setState(() => _customOpen = !_customOpen),
            ),
          ],
        ),
        if (_customOpen) ...[
          const SizedBox(height: 12),
          _CustomNameInput(
            controller: _customName,
            onAdd: _addCustom,
            locale: widget.locale,
          ),
        ],
        if (widget.rooms.isNotEmpty) ...[
          const SizedBox(height: 14),
          for (final room in widget.rooms)
            _RoomCountRow(
              label: room.kind == RoomKind.other
                  ? (room.name?.trim().isNotEmpty ?? false
                      ? room.name!.trim()
                      : _RoomsSelectorStrings.otherRoom(widget.locale))
                  : room.kind.label(widget.locale),
              controller: _counts[room]!,
              count: room.count,
              showArea: widget.showArea,
              areaController: _areas[room],
              onAreaTyped: (txt) =>
                  room.area = double.tryParse(txt.replaceAll(',', '.')),
              onMinus: () => room.count <= 1
                  ? _remove(room)
                  : _setCount(room, room.count - 1),
              onPlus: () => _setCount(room, room.count + 1),
              onTyped: (txt) {
                final n = int.tryParse(txt);
                if (n != null) _setCount(room, n);
              },
            ),
        ],
      ],
    );
  }
}

class _CustomNameInput extends StatelessWidget {
  const _CustomNameInput({
    required this.controller,
    required this.onAdd,
    required this.locale,
  });
  final TextEditingController controller;
  final VoidCallback onAdd;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldBg = isDark ? const Color(0xFF1F2426) : const Color(0xFFF7F8F9);
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;

    return Container(
      decoration: BoxDecoration(
        color: fieldBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.only(left: 14, right: 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onAdd(),
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontSize: 15,
                color: textColor,
              ),
              decoration: InputDecoration(
                hintText: _RoomsSelectorStrings.customNameHint(locale),
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          IconButton(
            onPressed: onAdd,
            icon: const Icon(Icons.add_circle, size: 30),
            color: AppColors.splashGreen,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'MTSCompact',
        fontWeight: FontWeight.w700,
        fontSize: 12.5,
        letterSpacing: 0.2,
        color: color,
      ),
    );
  }
}

class _RoomChip extends StatelessWidget {
  const _RoomChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final idleBg = isDark ? const Color(0xFF1F2426) : const Color(0xFFF1F2F4);
    final idleText = isDark ? Colors.white : AppColors.textBlack;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);

    return Material(
      color: selected ? AppColors.splashGreen.withValues(alpha: 0.16) : idleBg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.splashGreen : border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check, size: 15, color: AppColors.splashGreen),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  color: selected ? AppColors.splashGreen : idleText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomCountRow extends StatelessWidget {
  const _RoomCountRow({
    required this.label,
    required this.controller,
    required this.count,
    required this.onMinus,
    required this.onPlus,
    required this.onTyped,
    this.showArea = false,
    this.areaController,
    this.onAreaTyped,
  });

  final String label;
  final TextEditingController controller;
  final int count;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final ValueChanged<String> onTyped;
  final bool showArea;
  final TextEditingController? areaController;
  final ValueChanged<String>? onAreaTyped;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : const Color(0xFFB4B9BF);

    final atOne = count <= 1;
    final minusColor = atOne ? const Color(0xFFE5484D) : AppColors.splashGreen;
    final minusIcon = atOne ? Icons.close_rounded : Icons.remove_rounded;

    Widget stepBtn(IconData icon, VoidCallback onTap, Color color) => InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(icon, size: 20, color: color),
          ),
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: textColor,
              ),
            ),
          ),
          if (showArea && areaController != null) ...[
            // Maydon (m²) — bu yashik tahrirlanadigan ekanini ko'rsatish uchun
            // ramka + ichki fon beriladi (avval oddiy kulrang "m²" yorlig'iga
            // o'xshab, bosib bo'lmaydigandek ko'rinardi).
            Container(
              width: 76,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF15191B) : const Color(0xFFF4F5F7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: border),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextField(
                controller: areaController,
                textAlign: TextAlign.center,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                onChanged: onAreaTyped,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: textColor,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  border: InputBorder.none,
                  suffixText: 'm²',
                  suffixStyle: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 12,
                    color: hintColor,
                  ),
                  hintText: '0',
                  hintStyle: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 13,
                    color: hintColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          stepBtn(minusIcon, onMinus, minusColor),
          SizedBox(
            width: 34,
            child: TextField(
              controller: controller,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              onChanged: onTyped,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: textColor,
              ),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
                border: InputBorder.none,
              ),
            ),
          ),
          stepBtn(Icons.add_rounded, onPlus, AppColors.splashGreen),
        ],
      ),
    );
  }
}

class _RoomsSelectorStrings {
  const _RoomsSelectorStrings._();

  static String otherRoom(Locale l) =>
      tr(l, 'services.widget.rooms.other_room');

  static String livingGroup(Locale l) => tr(l, 'rooms.group.living');

  static String nonLivingGroup(Locale l) => tr(l, 'rooms.group.non_living');

  static String customNameHint(Locale l) =>
      tr(l, 'services.widget.rooms.custom_name_hint');
}
