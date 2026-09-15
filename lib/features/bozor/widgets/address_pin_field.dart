/// Manzil qatori — yoziladigan matn maydoni + o'ng tarafda xarita tugmachasi.
///
/// Dizayndagi `Адрес` qatori aynan shunday: oddiy input, ichida 32pt li
/// tugmacha, unda qizil "map pin". Tugmacha bosilsa xarita ekrani ochiladi.
///
/// Xaritadan tanlangach chaqiruvchi manzil matnini AVTOMATIK to'ldiradi
/// ([busy] shu paytda aylanma ko'rsatadi). Natija maydon ostida alohida
/// qatorda qoladi — manzil matni tahrirlansa ham u saqlanib turadi.
///
/// ## Ikki yo'l
///
/// Asosiysi ([onPickOnMap]) — geoportal uchastkalari xaritasi: u kadastr
/// raqamini ham, uy chegarasini ham beradi.
///
/// Ikkinchisi ([onPickManually]) — oddiy erkin metka. U ATAYLAB qoldirilgan:
/// geoportal hamma obyektni qamramaydi (yangi qurilish, xatlovdan o'tmagan
/// joy), va uchastka topilmagani uchun e'lon berish yo'li berkilib qolmasligi
/// kerak.
library;

import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../theme/app_colors.dart';

class AddressPinField extends StatelessWidget {
  const AddressPinField({
    super.key,
    required this.label,
    required this.controller,
    required this.placeholder,
    required this.onPickOnMap,
    this.busy = false,
    this.point,
    this.onClearPoint,
    this.required = false,
    this.pointLabel,
    this.clearLabel,
    this.cadastreNumber,
    this.cadastreLabel,
    this.onPickManually,
    this.manualLabel,
  });

  final String label;
  final TextEditingController controller;
  final String placeholder;

  /// Asosiy yo'l — geoportal uchastkalari xaritasi.
  final VoidCallback onPickOnMap;

  /// Xaritadan qaytgan natija manzilga aylantirilmoqda — tugmacha o'rnida
  /// aylanma chiqadi va bosilmaydi.
  final bool busy;

  /// Xaritada belgilangan nuqta — `null` bo'lsa ostidagi qator chizilmaydi.
  final ({double lat, double lng})? point;
  final VoidCallback? onClearPoint;
  final bool required;

  /// "Xaritada belgilandi" matni (tarjima chaqiruvchidan keladi).
  final String? pointLabel;
  final String? clearLabel;

  /// Geoportaldan tanlangan uchastkaning raqami. Bo'lsa, ostidagi qatorda
  /// koordinata O'RNIGA shu ko'rsatiladi: foydalanuvchi uchun
  /// "10:09:01:01:02:5942" "41.31108, 69.24056" dan ancha ma'noli.
  final String? cadastreNumber;
  final String? cadastreLabel;

  /// Ikkinchi yo'l — erkin metka. `null` bo'lsa qator umuman chizilmaydi.
  final VoidCallback? onPickManually;
  final String? manualLabel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark ? Colors.white : AppColors.textBlack;
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : const Color(0xFFB4B9BF);
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final pinBg = isDark ? const Color(0xFF2A2F32) : const Color(0xFFEEF1F0);

    final radius = BorderRadius.circular(14);
    final p = point;
    final cadastre = cadastreNumber?.trim();
    final hasCadastre = cadastre != null && cadastre.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  height: 1.25,
                  color: labelColor,
                ),
              ),
            ),
            if (required)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text(
                  '*',
                  style: TextStyle(color: Color(0xFFE0492A), fontSize: 14),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onTapOutside: (_) => FocusScope.of(context).unfocus(),
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(
            fontFamily: 'MTSText',
            fontSize: 14.5,
            color: textColor,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
            hintText: placeholder,
            hintStyle: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 14.5,
              color: hintColor,
            ),
            // Tugmacha input ichida turadi — dizayndagidek.
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Material(
                color: pinBg,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: busy ? null : hapticTap(onPickOnMap),
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: busy
                        ? const Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.splashGreen,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.place_rounded,
                            size: 19,
                            color: AppColors.declineRed,
                          ),
                  ),
                ),
              ),
            ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 38,
              minHeight: 32,
            ),
            filled: true,
            fillColor: fill,
            enabledBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(color: border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: const BorderSide(
                color: AppColors.splashGreen,
                width: 1.4,
              ),
            ),
          ),
        ),
        if (p != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  size: 15, color: AppColors.splashGreen),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  // Uchastka tanlangan bo'lsa kadastr raqami ko'rsatiladi:
                  // u foydalanuvchi TANIYDIGAN ma'lumot, koordinata esa
                  // yo'q. Nuqta baribir saqlangan — shunchaki ko'rsatilmaydi.
                  hasCadastre
                      ? '${cadastreLabel ?? ''} $cadastre'
                      : '${pointLabel ?? ''} · '
                          '${p.lat.toStringAsFixed(5)}, '
                          '${p.lng.toStringAsFixed(5)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 12,
                    color: subColor,
                  ),
                ),
              ),
              if (onClearPoint != null)
                GestureDetector(
                  onTap: hapticSelect(onClearPoint),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      clearLabel ?? '',
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: subColor,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (onPickManually != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: busy ? null : hapticSelect(onPickManually),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_location_alt_outlined,
                        size: 15, color: subColor),
                    const SizedBox(width: 6),
                    Text(
                      manualLabel ?? '',
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: subColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
