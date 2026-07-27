import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../auth/auth_storage.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../../settings/settings_state.dart';
import '../api_kadastr_3d_job_service.dart';
import '../models/kadastr_3d_bundle.dart';
import '../widgets/choice_tile.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/step_progress_bar.dart';
import 'kadastr_3d/k3d_intake_screen.dart';

class ScanObjectTypeScreen extends StatefulWidget {
  const ScanObjectTypeScreen({super.key, required this.bundle});

  final Kadastr3dBundle bundle;

  @override
  State<ScanObjectTypeScreen> createState() => _ScanObjectTypeScreenState();
}

class _ScanObjectTypeScreenState extends State<ScanObjectTypeScreen> {
  final Kadastr3dJobService _api = Kadastr3dJobService();

  // Object types now come from the backend (localized) instead of a hardcoded
  // enum, so adding/renaming a type is a server-only change.
  List<ObjectTypeOption> _options = const [];
  ObjectTypeOption? _selected;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final session = await const AuthStorage().loadSession();
      final token = session.token;
      if (token == null || token.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _loadError = _ScanObjectTypeStrings.errLogin(localeNotifier.value);
        });
        return;
      }
      final options = await _api.fetchObjectTypes(
        token: token,
        locale: localeNotifier.value.languageCode,
      );
      if (!mounted) return;
      // Preselect any previously chosen type (e.g. when stepping back in).
      final prev = widget.bundle.objectType;
      setState(() {
        _options = options;
        _selected = prev == null
            ? null
            : options.cast<ObjectTypeOption?>().firstWhere(
                  (o) => o?.value == prev.value,
                  orElse: () => null,
                );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _ScanObjectTypeStrings.errLoad(localeNotifier.value);
      });
    }
  }

  void _continue() {
    if (_selected == null) return;
    widget.bundle.objectType = _selected;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => K3dIntakeScreen(bundle: widget.bundle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (context, locale, _) => _build(context, locale),
    );
  }

  Widget _build(BuildContext context, Locale locale) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final labelColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

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
                        title: _ScanObjectTypeStrings.appBarTitle(locale),
                        subtitle:
                            _ScanObjectTypeStrings.appBarSubtitle(locale),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: const StepProgressBar(count: 6, activeIndex: 3),
                    ),
                    Expanded(
                      child: _buildBody(locale, labelColor, subColor),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: ListingCtaButton(
                        label: _ScanObjectTypeStrings.ctaContinue(locale),
                        enabled: _selected != null,
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

  Widget _buildBody(Locale locale, Color labelColor, Color subColor) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.splashGreen),
      );
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: subColor, size: 40),
              const SizedBox(height: 12),
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'MTSText',
                  fontSize: 14,
                  color: labelColor,
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: hapticTap(_loadOptions),
                child: Text(
                  _ScanObjectTypeStrings.retry(locale),
                  style: const TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    color: AppColors.splashGreen,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      children: [
        Text(
          _ScanObjectTypeStrings.heading(locale),
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 16,
            height: 1.25,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _ScanObjectTypeStrings.subheading(locale),
          style: TextStyle(
            fontFamily: 'MTSText',
            fontSize: 13,
            height: 1.3,
            color: subColor,
          ),
        ),
        const SizedBox(height: 14),
        for (final o in _options) ...[
          ChoiceTile(
            label: o.label,
            selected: _selected?.value == o.value,
            onTap: () => setState(() => _selected = o),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ScanObjectTypeStrings {
  static String appBarTitle(Locale locale) =>
      tr(locale, 'services.scan.object_type.app_bar_title');

  static String appBarSubtitle(Locale locale) =>
      tr(locale, 'services.scan.object_type.app_bar_subtitle');

  static String heading(Locale locale) =>
      tr(locale, 'services.scan.object_type.heading');

  static String subheading(Locale locale) =>
      tr(locale, 'services.scan.object_type.subheading');

  static String ctaContinue(Locale locale) =>
      tr(locale, 'services.scan.object_type.cta_continue');

  static String retry(Locale locale) =>
      tr(locale, 'services.scan.object_type.retry');

  static String errLoad(Locale locale) =>
      tr(locale, 'services.scan.object_type.err_load');

  static String errLogin(Locale locale) =>
      tr(locale, 'services.scan.object_type.err_login');
}
