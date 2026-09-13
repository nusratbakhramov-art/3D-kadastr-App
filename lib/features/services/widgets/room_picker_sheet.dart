/// Qo'llanmadan keyingi varaq — qaysi xona videoga olinayotganini tanlash.
///
/// Har bir xona alohida video, alohida job va alohida 3D model bo'ladi:
/// v2m quvurida xonalarni birlashtirish yo'q va metrik masshtab ham yo'q,
/// shu sababli "bitta video = bitta xona" qoidasi.
///
/// Ro'yxat hozircha statik — [RoomKind] ning barcha qiymatlari (tarjimalari
/// `services.model.room.*` da tayyor). Keyinchalik ariza bundle'idagi
/// kiritilgan xonalardan to'ldirilishi mumkin.
///
/// "Boshqa" ALOHIDA: tanlansa ro'yxat ostida nom maydoni ochiladi. Sakkizta
/// qat'iy tur har qanday xonadonni qoplamaydi (ish xonasi, ayvon, garaj...),
/// va nomsiz qolsa ro'yxatdagi bir nechta "Boshqa" bir-biridan farq qilmay
/// qolardi — qaysi video qaysi xona ekani bilinmasdi.
library;

import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../models/ai_baholash_bundle.dart';
import 'choice_tile.dart';

/// Varaqni ochadi. Tanlangan xona qaytadi, bekor qilinsa `null`.
///
/// [title]/[hint] — matnni almashtirish (Bozor 360° sehrgari ham shu
/// varaqni ishlatadi: u yerda «video/3D model» izohi to'g'ri kelmaydi).
Future<RoomChoice?> showRoomPickerSheet(
  BuildContext context, {
  RoomKind? selected,
  String? title,
  String? hint,
}) {
  return showModalBottomSheet<RoomChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _RoomPickerSheet(selected: selected, title: title, hint: hint),
  );
}

class _RoomPickerSheet extends StatefulWidget {
  const _RoomPickerSheet({this.selected, this.title, this.hint});

  final RoomKind? selected;
  final String? title;
  final String? hint;

  @override
  State<_RoomPickerSheet> createState() => _RoomPickerSheetState();
}

class _RoomPickerSheetState extends State<_RoomPickerSheet> {
  final TextEditingController _name = TextEditingController();

  late RoomKind? _selected = widget.selected;

  /// Nom maydoni ochilganmi — faqat "Boshqa" tanlanganda.
  late bool _naming = widget.selected == RoomKind.other;

  @override
  void initState() {
    super.initState();
    // Tugma bo'sh maydonda o'chiq turishi kerak — har bosishda
    // qayta chizamiz.
    _name.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _name.removeListener(_onNameChanged);
    _name.dispose();
    super.dispose();
  }

  void _onNameChanged() => setState(() {});

  /// Oddiy xona bir teginishda tanlanadi — bu avvalgi xatti-harakat.
  /// "Boshqa" esa varaqni yopmaydi: avval nomi so'raladi.
  void _pick(RoomKind room) {
    if (room != RoomKind.other) {
      Navigator.of(context).pop(RoomChoice(room));
      return;
    }
    setState(() {
      _selected = room;
      _naming = true;
    });
  }

  void _confirmName() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(RoomChoice(RoomKind.other, name: name));
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF15191B) : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    return SafeArea(
      child: Padding(
        // Klaviatura ochilganda nom maydoni uning ostida qolib ketmasin.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: sheetBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : const Color(0xFFD9DEE1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  widget.title ?? _S.title(l),
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.hint ?? _S.hint(l),
                  style: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 13,
                    height: 1.35,
                    color: subColor,
                  ),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final room in RoomKind.values) ...[
                          ChoiceTile(
                            label: room.label(l),
                            selected: _selected == room,
                            onTap: () => _pick(room),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_naming) ...[
                  Text(
                    _S.nameLabel(l),
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: subColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _NameField(
                    controller: _name,
                    isDark: isDark,
                    placeholder: _S.namePlaceholder(l),
                    onSubmitted: _confirmName,
                  ),
                  const SizedBox(height: 12),
                  ListingCtaButton(
                    label: _S.confirm(l),
                    // Nomsiz "Boshqa" ning ma'nosi yo'q — varaq yopilmaydi.
                    enabled: _name.text.trim().isNotEmpty,
                    onTap: _confirmName,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Xona nomi maydoni — ilovaning boshqa formalari bilan bir xil ko'rinish.
class _NameField extends StatelessWidget {
  const _NameField({
    required this.controller,
    required this.isDark,
    required this.placeholder,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool isDark;
  final String placeholder;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final text = isDark ? Colors.white : AppColors.textBlack;
    final hint = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : const Color(0xFFB4B9BF);

    return TextField(
      controller: controller,
      autofocus: true,
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => onSubmitted(),
      // Nom ro'yxat qatoriga va serverdagi ish yorlig'iga tushadi — uzun
      // matn ikkalasida ham kesilib qolardi.
      maxLength: 40,
      style: TextStyle(fontFamily: 'MTSText', fontSize: 15, color: text),
      decoration: InputDecoration(
        isDense: true,
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintText: placeholder,
        hintStyle: TextStyle(
          fontFamily: 'MTSText',
          fontSize: 15,
          color: hint,
        ),
        filled: true,
        fillColor: fill,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: AppColors.splashGreen,
            width: 1.4,
          ),
        ),
      ),
    );
  }
}

class _S {
  const _S._();

  static String title(Locale l) => tr(l, 'services.ai.capture.room_title');
  static String hint(Locale l) => tr(l, 'services.ai.capture.room_hint');
  static String nameLabel(Locale l) =>
      tr(l, 'services.ai.capture.room_name_label');
  static String namePlaceholder(Locale l) =>
      tr(l, 'services.ai.capture.room_name_hint');
  static String confirm(Locale l) => tr(l, 'services.ai.capture.continue');
}
