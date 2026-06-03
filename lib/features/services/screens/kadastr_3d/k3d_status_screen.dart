/// Step 6 of 3D Kadastr — submit + confirmation.
///
/// On open it POSTs the bundle to `/3d-kadastr-jobs` and shows a confirmation.
/// Unlike AI Baholash there is no pricing pipeline to poll — the request is
/// queued for a specialist, so we just confirm receipt (or surface an error
/// with a retry).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/network_error_handler.dart';
import '../../../../theme/app_colors.dart';
import '../../../auth/auth_storage.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../api_kadastr_3d_job_service.dart';
import '../../models/kadastr_3d_bundle.dart';
import '../../widgets/service_app_bar.dart';
import '../../widgets/step_progress_bar.dart';

class K3dStatusScreen extends StatefulWidget {
  const K3dStatusScreen({super.key, required this.bundle});

  final Kadastr3dBundle bundle;

  @override
  State<K3dStatusScreen> createState() => _K3dStatusScreenState();
}

class _K3dStatusScreenState extends State<K3dStatusScreen> {
  final Kadastr3dJobService _api = Kadastr3dJobService();

  bool _submitting = true;
  String? _error;
  int? _jobId;

  @override
  void initState() {
    super.initState();
    _submit();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Avval tizimga kiring';
      });
      return;
    }
    try {
      final id = await _api.create(
        bundleJson: widget.bundle.toJson(),
        token: token,
      );
      if (!mounted) return;
      setState(() {
        _jobId = id;
        _submitting = false;
      });
      HapticFeedback.mediumImpact();
    } on Kadastr3dApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      final handled =
          await NetworkErrorHandler.maybeShow(context, e, onRetry: _submit);
      if (!mounted) return;
      if (handled) return;
      setState(() {
        _submitting = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;

    return PopScope(
      canPop: !_submitting,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(8, 4, 8, 0),
                    child: ServiceAppBar(
                      title: '3D kadastr',
                      subtitle: 'Ariza yuborilmoqda',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: StepProgressBar(count: 6, activeIndex: 5),
                  ),
                  Expanded(child: _body(isDark)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(bool isDark) {
    if (_submitting) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.splashGreen),
            SizedBox(height: 16),
            Text(
              'Yuborilmoqda...',
              style: TextStyle(fontFamily: 'MTSText', fontSize: 14),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Color(0xFFE0492A)),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'MTSText',
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ListingCtaButton(
                label: 'Qayta urinish',
                enabled: true,
                onTap: _submit,
              ),
            ),
          ],
        ),
      );
    }

    // Success.
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final sub = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle,
              size: 72, color: AppColors.splashGreen),
          const SizedBox(height: 18),
          Text(
            'Arizangiz qabul qilindi',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: textColor,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _jobId == null
                ? 'Mutaxassis 3D model va baholashni tayyorlaydi. '
                    'Tayyor bo\'lganda sizga xabar beramiz.'
                : 'Ariza raqami: #$_jobId\n\n'
                    'Mutaxassis 3D model va baholashni tayyorlaydi. '
                    'Tayyor bo\'lganda sizga xabar beramiz.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 14,
              height: 1.45,
              color: sub,
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ListingCtaButton(
              label: 'Asosiy sahifa',
              enabled: true,
              onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
            ),
          ),
        ],
      ),
    );
  }
}
