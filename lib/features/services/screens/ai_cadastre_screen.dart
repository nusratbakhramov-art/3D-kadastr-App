import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network_error_handler.dart';
import '../../../theme/app_colors.dart';
import '../../auth/auth_storage.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../api_cadastre_service.dart';
import '../models/ai_baholash_bundle.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/step_progress_bar.dart';
import 'ai_client_form_screen.dart';

enum _LoadStatus { idle, loading, loaded, error }

class AiCadastreScreen extends StatefulWidget {
  const AiCadastreScreen({super.key});

  @override
  State<AiCadastreScreen> createState() => _AiCadastreScreenState();
}

class _AiCadastreScreenState extends State<AiCadastreScreen> {
  static const _fullMaskLength = 19;
  final TextEditingController _cadastreController = TextEditingController();
  Timer? _loadTimer;
  _LoadStatus _status = _LoadStatus.idle;
  CadastreLookupResult? _info;
  String? _errorMsg;
  int _lookupRequestId = 0;

  @override
  void initState() {
    super.initState();
    _cadastreController.addListener(_onCadastreChanged);
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    _cadastreController.removeListener(_onCadastreChanged);
    _cadastreController.dispose();
    super.dispose();
  }

  void _onCadastreChanged() {
    final filled = _cadastreController.text.length == _fullMaskLength;
    if (filled) {
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
    final reqId = ++_lookupRequestId;
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null) {
      if (!mounted || reqId != _lookupRequestId) return;
      setState(() {
        _status = _LoadStatus.error;
        _errorMsg = 'Avval tizimga kiring';
      });
      return;
    }
    try {
      final result = await CadastreApiService().lookup(
        cadastreNumber: number,
        token: token,
      );
      if (!mounted || reqId != _lookupRequestId) return;
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
        _errorMsg = 'Tarmoq xatosi: $e';
      });
      await NetworkErrorHandler.maybeShow(context, e, onRetry: _runLookup);
    }
  }

  void _continue() {
    if (_status != _LoadStatus.loaded || _info == null) return;
    HapticFeedback.lightImpact();
    final bundle = AiBaholashBundle(kadastr: _info!);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AiClientFormScreen(bundle: bundle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final labelColor = isDark ? Colors.white : AppColors.textBlack;
    final dividerColor =
        isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);

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
                      child: const ServiceAppBar(
                        title: 'AI Baholash',
                        subtitle: 'Ko\'chmas mulk qiymatini aniqlash',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: const StepProgressBar(count: 4, activeIndex: 0),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        children: [
                          _SectionLabel('Kadastr raqami', color: labelColor),
                          const SizedBox(height: 10),
                          _CadastreInput(
                            isDark: isDark,
                            controller: _cadastreController,
                          ),
                          const SizedBox(height: 10),
                          _HelperLine(isDark: isDark),
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
                                    key: const ValueKey('details'),
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 18),
                                      Container(
                                          height: 1, color: dividerColor),
                                      const SizedBox(height: 18),
                                      _SectionLabel(
                                        'Uy ma\'lumotlari',
                                        color: labelColor,
                                      ),
                                      const SizedBox(height: 10),
                                      if (_status == _LoadStatus.loading)
                                        _PropertyInfoCardSkeleton(
                                          isDark: isDark,
                                        )
                                      else if (_status == _LoadStatus.error)
                                        _LookupErrorCard(
                                          message: _errorMsg ?? 'Xato',
                                          onRetry: _runLookup,
                                          isDark: isDark,
                                        )
                                      else if (_info != null)
                                        _PropertyInfoCard(
                                          isDark: isDark,
                                          info: _info!,
                                        )
                                      else
                                        const SizedBox.shrink(),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: ListingCtaButton(
                        label: 'Davom etish',
                        enabled: _status == _LoadStatus.loaded,
                        onTap: _continue,
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

class _CadastreInput extends StatelessWidget {
  const _CadastreInput({required this.isDark, required this.controller});

  final bool isDark;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final fillColor = isDark ? const Color(0xFF1F2426) : Colors.white;
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : const Color(0xFFB4B9BF);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final borderColor =
        isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);

    return TextField(
      controller: controller,
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      // `phone` (not `number`) — Android's number keyboard/clipboard layer
      // silently strips non-digit characters from pasted text, so a clipboard
      // value like "11:14:04:01:01:1630" never reaches our formatter. The
      // phone keyboard accepts arbitrary characters on paste; the mask
      // formatter below then strips/re-inserts the colons.
      keyboardType: TextInputType.phone,
      inputFormatters: [_CadastreMaskFormatter()],
      style: TextStyle(
        fontFamily: 'MTSText',
        fontSize: 15,
        letterSpacing: 0.3,
        color: textColor,
      ),
      decoration: InputDecoration(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        hintText: 'XX:XX:XX:XX:XX:XXXX',
        hintStyle: TextStyle(
          fontFamily: 'MTSText',
          fontSize: 15,
          letterSpacing: 0.3,
          color: hintColor,
        ),
        filled: true,
        fillColor: fillColor,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.splashGreen, width: 1.4),
        ),
      ),
    );
  }
}

class _CadastreMaskFormatter extends TextInputFormatter {
  static const _segments = [2, 2, 2, 2, 2, 4];
  static const _maxDigits = 14;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '').substring(
          0,
          newValue.text
              .replaceAll(RegExp(r'\D'), '')
              .length
              .clamp(0, _maxDigits),
        );

    final buffer = StringBuffer();
    var consumed = 0;
    for (var i = 0; i < _segments.length; i++) {
      if (consumed >= digits.length) break;
      final take = _segments[i];
      final end = (consumed + take).clamp(0, digits.length);
      if (i > 0) buffer.write(':');
      buffer.write(digits.substring(consumed, end));
      consumed = end;
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _HelperLine extends StatelessWidget {
  const _HelperLine({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final restColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontFamily: 'MTSText',
          fontSize: 13,
          height: 1.3,
          color: restColor,
        ),
        children: const [
          TextSpan(
            text: 'davreest.uz',
            style: TextStyle(
              color: AppColors.splashGreen,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: ' dan avtomatlik olinadi'),
        ],
      ),
    );
  }
}

class _PropertyInfoCardSkeleton extends StatefulWidget {
  const _PropertyInfoCardSkeleton({required this.isDark});

  final bool isDark;

  @override
  State<_PropertyInfoCardSkeleton> createState() =>
      _PropertyInfoCardSkeletonState();
}

class _PropertyInfoCardSkeletonState extends State<_PropertyInfoCardSkeleton>
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
    final divider =
        isDark ? const Color(0xFF2C3133) : const Color(0xFFEEF0F2);
    final baseA = isDark ? const Color(0xFF1A2024) : const Color(0xFFE7EAEE);
    final baseB = isDark ? const Color(0xFF262C31) : const Color(0xFFF2F4F7);

    const labelWidths = [56.0, 36.0, 64.0, 48.0, 110.0];
    const valueWidths = [140.0, 150.0, 90.0, 50.0, 80.0];

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final shade = Color.lerp(baseA, baseB, _pulse.value)!;

        return Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < labelWidths.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _bar(shade, width: labelWidths[i], height: 11),
                      _bar(shade, width: valueWidths[i], height: 12),
                    ],
                  ),
                ),
                if (i != labelWidths.length - 1)
                  Container(height: 1, color: divider),
              ],
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

class _PropertyInfoCard extends StatelessWidget {
  const _PropertyInfoCard({required this.isDark, required this.info});

  final bool isDark;
  final CadastreLookupResult info;

  List<(String, String)> get _rows {
    String fmtNum(double? v, String unit) =>
        v == null ? '—' : '${_formatDecimal(v)} $unit';
    String fmtUzs(double? v) {
      if (v == null) return '—';
      if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(2)} mlrd';
      if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)} mln';
      return _formatDecimal(v);
    }

    return [
      ('Manzil', info.address ?? '—'),
      if (info.objectTypeHint != null) ('Turi', info.objectTypeHint!),
      ('Maydon', fmtNum(info.totalArea, 'm²')),
      if (info.livingArea != null)
        ('Yashash maydoni', fmtNum(info.livingArea, 'm²')),
      ('Kadastr qiymati', fmtUzs(info.cadastreValue)),
    ];
  }

  static String _formatDecimal(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final divider =
        isDark ? const Color(0xFF2C3133) : const Color(0xFFEEF0F2);
    final labelColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final valueColor = isDark ? Colors.white : AppColors.textBlack;

    final rows = _rows;
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${rows[i].$1}:',
                    style: TextStyle(
                      fontFamily: 'MTSText',
                      fontSize: 14,
                      height: 1.25,
                      color: labelColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Qiymat — qolgan joyni egallaydi va uzun matn (masalan to'liq
                  // manzil) bir necha qatorga o'raladi, satrdan toshib ketmaydi.
                  Expanded(
                    child: Text(
                      rows[i].$2,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        height: 1.25,
                        color: valueColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (i != rows.length - 1) Container(height: 1, color: divider),
          ],
        ],
      ),
    );
  }
}

class _LookupErrorCard extends StatelessWidget {
  const _LookupErrorCard({
    required this.message,
    required this.onRetry,
    required this.isDark,
  });

  final String message;
  final VoidCallback onRetry;
  final bool isDark;

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
                  'Ma\'lumot olib bo\'lmadi',
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
              label: const Text('Qayta urinish'),
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
