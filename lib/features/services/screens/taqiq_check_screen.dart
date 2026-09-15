/// «Taqiqni tekshirish» — kadastr obyektiga qo'yilgan ta'qiq va cheklovlarni
/// ko'rsatadi.
///
/// Oqim AI Baholashning kadastr qadami bilan bir xil: uy xaritadan tanlanadi
/// (yoki raqam qo'lda yoziladi) → davreestr.uz dan so'raladi. Farqi shundaki,
/// bu yerda manzil/maydon emas, YAGONA savolga javob ko'rsatiladi: obyektga
/// ta'qiq qo'yilganmi.
///
/// Ekran HAR DOIM `forceRefresh: true` bilan so'raydi. Ta'qiq bugun qo'yilib
/// ertaga olinadigan ma'lumot: umumiy keshdan kelgan "toza" javob shu
/// ekranning butun ma'nosini yo'qqa chiqarardi.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../core/network_error_handler.dart';
import '../../../theme/app_colors.dart';
import '../../auth/auth_storage.dart';
import '../api_cadastre_service.dart';
import '../data/ngis_parcel_client.dart';
import '../widgets/cadastre_number_field.dart';
import '../widgets/parcel_map.dart';
import '../widgets/service_app_bar.dart';
import 'parcel_picker_screen.dart';

enum _LoadStatus { idle, loading, loaded, error }

class TaqiqCheckScreen extends StatefulWidget {
  const TaqiqCheckScreen({super.key});

  @override
  State<TaqiqCheckScreen> createState() => _TaqiqCheckScreenState();
}

class _TaqiqCheckScreenState extends State<TaqiqCheckScreen> {
  static const _fullMaskLength = 19;

  final TextEditingController _cadastreController = TextEditingController();
  Timer? _loadTimer;
  _LoadStatus _status = _LoadStatus.idle;
  CadastreLookupResult? _info;
  String? _errorMsg;
  int _lookupRequestId = 0;

  /// Hozir qidirilayotgan raqam. "Yangilash"/"Qayta urinish" tugmalarini
  /// qo'riqlaydi: bir xil raqamga takroriy bosish yangi davreest.uz scrape
  /// boshlamaydi (u foydalanuvchini rate-limit'ga tushirishi mumkin).
  String? _inFlightNumber;

  List<String> _recent = const [];

  /// Xaritadan tanlangan uchastka — kartochkadagi kichik xaritada ajratib
  /// ko'rsatiladi va tanlagich qayta ochilganda o'sha joydan boshlanadi.
  NgisParcel? _parcel;

  @override
  void initState() {
    super.initState();
    _cadastreController.addListener(_onCadastreChanged);
    _loadRecent();
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    _cadastreController.removeListener(_onCadastreChanged);
    _cadastreController.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null) return;
    final list = await CadastreApiService().recent(token: token);
    if (!mounted) return;
    setState(() => _recent = list);
  }

  /// Xaritadan uy tanlash. Qaytgan kadastr raqami maydonga yoziladi va
  /// tekshiruv o'z-o'zidan boshlanadi.
  Future<void> _pickFromMap() async {
    HapticFeedback.lightImpact();
    final parcel = await Navigator.of(context).push<NgisParcel>(
      MaterialPageRoute<NgisParcel>(
        settings: const RouteSettings(name: 'taqiq/parcel-map'),
        builder: (_) => ParcelPickerScreen(
          initialCenter: _parcel?.center,
          initialSelection: _parcel,
        ),
      ),
    );
    if (parcel == null || !mounted) return;
    setState(() => _parcel = parcel);
    _applyNumber(parcel.cadastreNumber);
  }

  /// Raqamni maydonga qo'yadi va tekshiruvni MAJBURAN qaytadan boshlaydi.
  ///
  /// Holatni oldindan `idle` ga qaytarish shart: [_onCadastreChanged]
  /// qidiruvni faqat `idle`/`error` da boshlaydi, aks holda avvalgi uyning
  /// javobi yangi raqam ostida turib qolardi.
  void _applyNumber(String number) {
    _loadTimer?.cancel();
    final unchanged = _cadastreController.text == number;
    setState(() {
      _status = _LoadStatus.idle;
      _info = null;
      _errorMsg = null;
    });
    _cadastreController.value = TextEditingValue(
      text: number,
      selection: TextSelection.collapsed(offset: number.length),
    );
    // Matn O'ZGARMASA listener umuman ishlamaydi — bu xaritadan aynan o'sha
    // uy qayta tanlanganda (yoki o'sha chip bosilganda) sodir bo'ladi va
    // ekran to'la raqam bilan bo'sh turib qolardi. Shu holda tekshiruvni
    // o'zimiz boshlaymiz.
    if (unchanged && kCadastreNumberRe.hasMatch(number)) {
      setState(() => _status = _LoadStatus.loading);
      _loadTimer = Timer(const Duration(milliseconds: 250), _runLookup);
    }
  }

  void _useRecent(String number) => _applyNumber(number);

  void _onCadastreChanged() {
    final text = _cadastreController.text;
    // Qo'lda boshqa raqam yozilsa, xaritadagi yashil ajratma endi shu raqamga
    // tegishli emas — uni olib tashlaymiz, aks holda xarita bir uyni, maydon
    // esa boshqasini ko'rsatib turardi.
    if (_parcel != null && _parcel!.cadastreNumber != text) {
      setState(() => _parcel = null);
    }
    if (kCadastreNumberRe.hasMatch(text)) {
      if (_status == _LoadStatus.idle || _status == _LoadStatus.error) {
        _loadTimer?.cancel();
        _loadTimer = Timer(const Duration(milliseconds: 250), _runLookup);
        setState(() => _status = _LoadStatus.loading);
      }
    } else {
      _loadTimer?.cancel();
      if (_status != _LoadStatus.idle) {
        setState(() {
          _status = _LoadStatus.idle;
          _info = null;
          _errorMsg = null;
        });
      }
    }
  }

  Future<void> _runLookup() async {
    final number = _cadastreController.text;
    if (_inFlightNumber == number) return;
    _loadTimer?.cancel();
    _inFlightNumber = number;
    final reqId = ++_lookupRequestId;
    setState(() {
      _status = _LoadStatus.loading;
      _errorMsg = null;
    });
    try {
      await _performLookup(number, reqId);
    } finally {
      if (_inFlightNumber == number) _inFlightNumber = null;
    }
  }

  Future<void> _performLookup(String number, int reqId) async {
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null) {
      if (!mounted || reqId != _lookupRequestId) return;
      setState(() {
        _status = _LoadStatus.error;
        _errorMsg = _S.signInFirst(Localizations.localeOf(context));
      });
      return;
    }
    try {
      // Kesh ATAYLAB chetlab o'tiladi — ekran izohiga qarang.
      final result = await CadastreApiService().lookup(
        cadastreNumber: number,
        token: token,
        forceRefresh: true,
      );
      if (!mounted || reqId != _lookupRequestId) return;
      // davreest.uz mavjud bo'lmagan raqamga xato emas, hamma maydoni bo'sh
      // javob qaytaradi. Bu tekshiruvda buni ayirish AYNIQSA muhim: obyekt
      // o'qilmagani "ta'qiq yo'q" degani EMAS.
      final found =
          (result.address?.trim().isNotEmpty ?? false) ||
          result.totalArea != null ||
          result.livingArea != null ||
          result.cadastreValue != null ||
          (result.objectTypeHint?.trim().isNotEmpty ?? false);
      if (!found) {
        setState(() {
          _status = _LoadStatus.error;
          _info = null;
          // ATAYLAB "topilmadi" EMAS. Bo'sh javobning ikki sababi bor va ular
          // bir xil ko'rinadi: raqam rostdan reyestrda yo'q, YOKI sayt bizga
          // javob bermadi (so'rov limiti, rad etilgan forma). Ta'qiq
          // tekshiruvida "bu raqam reyestrda yo'q" deb qat'iy aytish —
          // aytolmaydigan gapimiz.
          _errorMsg = _S.noAnswer(Localizations.localeOf(context));
        });
        return;
      }
      if (result.hasRestrictions == null) {
        // Bu yerga tushmasligi kerak (`forceRefresh: true` har doim jonli
        // javob beradi). Tushsa — bilmasligimizni tan olamiz, chunki noto'g'ri
        // "toza" javob shu ekrandagi eng qimmat xato.
        setState(() {
          _status = _LoadStatus.error;
          _info = null;
          _errorMsg = _S.unknownStatus(Localizations.localeOf(context));
        });
        return;
      }
      setState(() {
        _info = result;
        _status = _LoadStatus.loaded;
        _errorMsg = null;
      });
    } on CadastreLookupException catch (e) {
      if (!mounted || reqId != _lookupRequestId) return;
      setState(() {
        _status = _LoadStatus.error;
        _errorMsg = e.message;
      });
    } catch (e) {
      if (!mounted || reqId != _lookupRequestId) return;
      setState(() {
        _status = _LoadStatus.error;
        _errorMsg = _S.networkError(Localizations.localeOf(context), '$e');
      });
      // "Qayta urinish" shu ekrandan _runLookup ni chaqiradi — takror deb
      // tashlab yubormasligi uchun qulfni oldindan bo'shatamiz.
      _inFlightNumber = null;
      await NetworkErrorHandler.maybeShow(context, e, onRetry: _runLookup);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final labelColor = isDark ? Colors.white : AppColors.textBlack;
    final dividerColor =
        isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final info = _info;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxContent = constraints.maxWidth.clamp(0.0, 640.0);
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContent),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: ServiceAppBar(
                        title: _S.title(l),
                        subtitle: _S.subtitle(l),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                        children: [
                          _SectionLabel(_S.mapLabel(l), color: labelColor),
                          const SizedBox(height: 10),
                          _MapCard(
                            parcel: _parcel,
                            isDark: isDark,
                            locale: l,
                            onTap: _pickFromMap,
                          ),
                          const SizedBox(height: 20),
                          _SectionLabel(
                            _S.cadastreNumber(l),
                            color: labelColor,
                          ),
                          const SizedBox(height: 10),
                          CadastreNumberField(
                            controller: _cadastreController,
                            suffix: _status == _LoadStatus.loading
                                ? const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.splashGreen,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          if (_status == _LoadStatus.idle &&
                              _recent.isNotEmpty &&
                              _cadastreController.text.length <
                                  _fullMaskLength) ...[
                            const SizedBox(height: 18),
                            _SectionLabel(
                              _S.recentSearches(l),
                              color: labelColor,
                            ),
                            const SizedBox(height: 10),
                            _RecentChips(
                              numbers: _recent,
                              isDark: isDark,
                              onTap: _useRecent,
                            ),
                          ],
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 240),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: SizeTransition(
                                    sizeFactor: animation,
                                    axisAlignment: -1,
                                    child: child,
                                  ),
                                ),
                            child: _status == _LoadStatus.idle
                                ? const SizedBox.shrink(key: ValueKey('idle'))
                                : Column(
                                    key: const ValueKey('result'),
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 18),
                                      Container(height: 1, color: dividerColor),
                                      const SizedBox(height: 18),
                                      _SectionLabel(
                                        _S.resultLabel(l),
                                        color: labelColor,
                                      ),
                                      const SizedBox(height: 10),
                                      if (_status == _LoadStatus.loading)
                                        _VerdictSkeleton(isDark: isDark)
                                      else if (_status == _LoadStatus.error)
                                        _LookupErrorCard(
                                          message: _errorMsg ??
                                              _S.genericError(l),
                                          onRetry: _runLookup,
                                          isDark: isDark,
                                          locale: l,
                                        )
                                      else if (info != null) ...[
                                        _VerdictCard(
                                          info: info,
                                          isDark: isDark,
                                          locale: l,
                                        ),
                                        if (info.restrictions.isNotEmpty) ...[
                                          const SizedBox(height: 18),
                                          _SectionLabel(
                                            _S.entriesLabel(l),
                                            color: labelColor,
                                          ),
                                          const SizedBox(height: 10),
                                          for (final r in info.restrictions)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 10,
                                              ),
                                              child: _RestrictionCard(
                                                entry: r,
                                                isDark: isDark,
                                                locale: l,
                                              ),
                                            ),
                                        ],
                                        const SizedBox(height: 4),
                                        _RefreshRow(
                                          locale: l,
                                          onTap: _runLookup,
                                        ),
                                      ] else
                                        const SizedBox.shrink(),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Kadastr raqamini xaritadan olish kartochkasi.
///
/// Ichkaridagi xarita ATAYLAB surilmaydi (`interactive: false`): u ro'yxat
/// ichida turibdi va surish ro'yxatning vertikal siljishini o'g'irlardi.
/// Bosilganda to'liq ekranli tanlagich ochiladi.
class _MapCard extends StatelessWidget {
  const _MapCard({
    required this.parcel,
    required this.isDark,
    required this.locale,
    required this.onTap,
  });

  final NgisParcel? parcel;
  final bool isDark;
  final Locale locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final p = parcel;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 190,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ParcelMap(
                  // Kalit tanlov o'zgarganda xaritani o'sha uyga qayta
                  // markazlaydi — `initialCenter` faqat qurilishda o'qiladi.
                  key: ValueKey(p?.cadastreNumber ?? 'empty'),
                  initialCenter: p?.center,
                  initialZoom: p == null ? 12 : 18,
                  selected: p,
                  interactive: false,
                  onTap: (_, _) {},
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: _MapCardBadge(parcel: p, isDark: isDark, locale: locale),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapCardBadge extends StatelessWidget {
  const _MapCardBadge({
    required this.parcel,
    required this.isDark,
    required this.locale,
  });

  final NgisParcel? parcel;
  final bool isDark;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final p = parcel;
    final bg = isDark
        ? Colors.black.withValues(alpha: 0.68)
        : Colors.white.withValues(alpha: 0.95);
    final textColor = isDark ? Colors.white : AppColors.textBlack;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.map_outlined, size: 18,
              color: AppColors.splashGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              p == null ? _S.mapCta(locale) : p.cadastreNumber,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: textColor,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            p == null ? _S.mapOpen(locale) : _S.mapChange(locale),
            style: const TextStyle(
              fontFamily: 'MTSText',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.splashGreen,
            ),
          ),
        ],
      ),
    );
  }
}

/// Yagona javob: ta'qiq bor yoki yo'q.
class _VerdictCard extends StatelessWidget {
  const _VerdictCard({
    required this.info,
    required this.isDark,
    required this.locale,
  });

  final CadastreLookupResult info;
  final bool isDark;
  final Locale locale;

  static const _red = Color(0xFFE0492A);

  @override
  Widget build(BuildContext context) {
    final restricted = info.hasRestrictions ?? true;
    final accent = restricted ? _red : AppColors.splashGreen;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final count = info.restrictions.length;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  restricted
                      ? Icons.gpp_maybe_rounded
                      : Icons.verified_user_rounded,
                  color: accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            restricted
                                ? _S.restrictedTitle(locale)
                                : _S.cleanTitle(locale),
                            style: TextStyle(
                              fontFamily: 'MTSCompact',
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                              height: 1.2,
                              color: textColor,
                            ),
                          ),
                        ),
                        if (restricted && count > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$count',
                              style: const TextStyle(
                                fontFamily: 'MTSCompact',
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                color: _red,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      restricted
                          ? _S.restrictedBody(locale)
                          : _S.cleanBody(locale),
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 13,
                        height: 1.35,
                        color: subColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 1,
            color: isDark ? const Color(0xFF2C3133) : const Color(0xFFEEF0F2),
          ),
          const SizedBox(height: 12),
          Text(
            _S.cadastreNumber(locale),
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 12.5,
              color: subColor,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            info.cadastreNumber,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 15,
              letterSpacing: 0.2,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bitta ta'qiq yozuvi. Qiymatlar reyestrdagidek ko'rsatiladi (ko'pincha
/// ruscha) — tarjima yuridik ma'noni o'zgartirib yuborishi mumkin.
class _RestrictionCard extends StatelessWidget {
  const _RestrictionCard({
    required this.entry,
    required this.isDark,
    required this.locale,
  });

  final CadastreRestriction entry;
  final bool isDark;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final labelColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    final rows = <(String, String)>[
      if (entry.authority.isNotEmpty)
        (_S.entryAuthority(locale), entry.authority),
      if (entry.number.isNotEmpty) (_S.entryNumber(locale), entry.number),
      if (entry.documentNumber.isNotEmpty)
        (_S.entryDocument(locale), entry.documentNumber),
      if (entry.exchangeCode.isNotEmpty)
        (_S.entryExchange(locale), entry.exchangeCode),
    ];

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  entry.kind.isEmpty ? _S.entryKindUnknown(locale) : entry.kind,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    height: 1.25,
                    color: textColor,
                  ),
                ),
              ),
              if (entry.date.isNotEmpty) ...[
                const SizedBox(width: 10),
                Text(
                  entry.date,
                  style: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 13,
                    color: labelColor,
                  ),
                ),
              ],
            ],
          ),
          for (final row in rows) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${row.$1}:',
                  style: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 13,
                    height: 1.3,
                    color: labelColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    row.$2,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFamily: 'MTSText',
                      fontSize: 13,
                      height: 1.3,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _VerdictSkeleton extends StatefulWidget {
  const _VerdictSkeleton({required this.isDark});

  final bool isDark;

  @override
  State<_VerdictSkeleton> createState() => _VerdictSkeletonState();
}

class _VerdictSkeletonState extends State<_VerdictSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final baseA = isDark ? const Color(0xFF1A2024) : const Color(0xFFE7EAEE);
    final baseB = isDark ? const Color(0xFF232A2E) : const Color(0xFFF2F4F6);

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final shade = Color.lerp(baseA, baseB, _pulse.value)!;
        return Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: shade,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _bar(shade, width: 150, height: 14),
                        const SizedBox(height: 8),
                        _bar(shade, width: double.infinity, height: 11),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _bar(shade, width: 90, height: 10),
              const SizedBox(height: 8),
              _bar(shade, width: 170, height: 13),
            ],
          ),
        );
      },
    );
  }

  Widget _bar(Color color, {required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

class _LookupErrorCard extends StatelessWidget {
  const _LookupErrorCard({
    required this.message,
    required this.onRetry,
    required this.isDark,
    required this.locale,
  });

  final String message;
  final VoidCallback onRetry;
  final bool isDark;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0492A)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.error_outline,
                color: Color(0xFFE0492A),
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _S.lookupFailed(locale),
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 13,
              height: 1.35,
              color: hintColor,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(_S.retry(locale)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.splashGreen,
                side: const BorderSide(color: AppColors.splashGreen),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ta'qiq holati o'zgaruvchan — javobni qayta so'rash yo'li doim ko'rinib
/// tursin.
class _RefreshRow extends StatelessWidget {
  const _RefreshRow({required this.locale, required this.onTap});

  final Locale locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.refresh, size: 18),
        label: Text(_S.recheck(locale)),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.splashGreen,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'MTSCompact',
        fontWeight: FontWeight.w700,
        fontSize: 16,
        height: 1.25,
        color: color,
      ),
    );
  }
}

/// Foydalanuvchining oxirgi qidirgan raqamlari — bosilsa maydonga qo'yiladi.
class _RecentChips extends StatelessWidget {
  const _RecentChips({
    required this.numbers,
    required this.isDark,
    required this.onTap,
  });

  final List<String> numbers;
  final bool isDark;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final n in numbers)
          GestureDetector(
            onTap: () => onTap(n),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF1F2426) : const Color(0xFFF1F3F5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF2C3133)
                      : const Color(0xFFE3E5E8),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 14,
                    color: isDark ? Colors.white70 : const Color(0xFF8A9097),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    n,
                    style: TextStyle(
                      fontFamily: 'MTSText',
                      fontSize: 13,
                      color: isDark ? Colors.white : AppColors.textBlack,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _S {
  const _S._();

  // Kadastr maydoni / xarita — AI Baholashning kadastr qadami bilan bir xil
  // matn, shuning uchun kalitlar ham o'sha.
  static String cadastreNumber(Locale l) =>
      tr(l, 'services.ai.cadastre.cadastre_number');
  static String mapLabel(Locale l) => tr(l, 'services.ai.cadastre.map_label');
  static String mapCta(Locale l) => tr(l, 'services.ai.cadastre.map_cta');
  static String mapOpen(Locale l) => tr(l, 'services.ai.cadastre.map_open');
  static String mapChange(Locale l) => tr(l, 'services.ai.cadastre.map_change');
  static String recentSearches(Locale l) =>
      tr(l, 'services.ai.cadastre.recent_searches');
  static String retry(Locale l) => tr(l, 'services.ai.cadastre.retry');
  static String lookupFailed(Locale l) =>
      tr(l, 'services.ai.cadastre.lookup_failed');
  static String genericError(Locale l) =>
      tr(l, 'services.ai.cadastre.generic_error');
  static String networkError(Locale l, String err) =>
      '${tr(l, 'services.ai.cadastre.network_error')}: $err';
  static String signInFirst(Locale l) =>
      tr(l, 'services.ai.common.sign_in_first');

  // Ta'qiqqa xos matnlar.
  static String title(Locale l) => tr(l, 'home.card.taqiq_check');
  static String subtitle(Locale l) => tr(l, 'services.taqiq.subtitle');
  static String resultLabel(Locale l) => tr(l, 'services.taqiq.result_label');
  static String cleanTitle(Locale l) => tr(l, 'services.taqiq.clean_title');
  static String cleanBody(Locale l) => tr(l, 'services.taqiq.clean_body');
  static String restrictedTitle(Locale l) =>
      tr(l, 'services.taqiq.restricted_title');
  static String restrictedBody(Locale l) =>
      tr(l, 'services.taqiq.restricted_body');
  static String entriesLabel(Locale l) => tr(l, 'services.taqiq.entries_label');
  static String entryKindUnknown(Locale l) =>
      tr(l, 'services.taqiq.entry_kind_unknown');
  static String entryAuthority(Locale l) =>
      tr(l, 'services.taqiq.entry_authority');
  static String entryNumber(Locale l) => tr(l, 'services.taqiq.entry_number');
  static String entryDocument(Locale l) =>
      tr(l, 'services.taqiq.entry_document');
  static String entryExchange(Locale l) =>
      tr(l, 'services.taqiq.entry_exchange');
  static String recheck(Locale l) => tr(l, 'services.taqiq.recheck');
  static String noAnswer(Locale l) => tr(l, 'services.taqiq.no_answer');
  static String unknownStatus(Locale l) =>
      tr(l, 'services.taqiq.unknown_status');
}
