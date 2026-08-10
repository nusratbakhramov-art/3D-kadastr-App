/// A bottom drawer prompting the user to log in before a gated action.
///
/// Usage:
///   if (!await ensureLoggedIn(context)) return;   // user not logged in / skipped
///   // ... proceed with the authenticated action
///
/// `ensureLoggedIn` checks the stored session; if missing it shows this
/// drawer, runs the auth flow if the user taps "Kirish", and returns whether
/// the user is authenticated afterwards.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/sheet_button.dart';
import '../auth_flow_screen.dart';
import '../auth_storage.dart';

/// Returns true if the user has a valid session (already, or after logging in
/// via the drawer). Returns false if not logged in and the user dismissed /
/// skipped — in which case the caller should NOT proceed.
Future<bool> ensureLoggedIn(
  BuildContext context, {
  AuthStorage storage = const AuthStorage(),
  String? title,
  String? message,
}) async {
  final session = await storage.loadSession();
  if (session.token != null && session.token!.isNotEmpty) return true;
  if (!context.mounted) return false;

  final wantsLogin = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _LoginRequiredSheet(title: title, message: message),
  );
  if (wantsLogin != true || !context.mounted) return false;

  // Run the auth flow; both callbacks just pop it.
  await Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      fullscreenDialog: true,
      pageBuilder: (ctx, _, _) => AuthFlowScreen(
        storage: storage,
        onAuthenticated: () => Navigator.of(ctx).pop(),
        onSkip: () => Navigator.of(ctx).pop(),
      ),
      transitionsBuilder: (_, animation, _, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  );

  // Re-check after the flow.
  final after = await storage.loadSession();
  return after.token != null && after.token!.isNotEmpty;
}

class _LoginRequiredSheet extends StatelessWidget {
  const _LoginRequiredSheet({required this.title, required this.message});
  final String? title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF15191B) : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

    // The colored Container is the OUTER wrapper so its background fills the
    // bottom safe-area (home-indicator strip); SafeArea(top:false) only insets
    // the content. Wrapping the other way round left that strip transparent —
    // the dark scrim showed through as a "black bar" under the sheet.
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.splashGreen.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_outline,
                  size: 28, color: AppColors.splashGreen),
            ),
            const SizedBox(height: 16),
            Text(
              title ?? tr(l, 'auth.login_required.title'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: textColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message ?? tr(l, 'auth.login_required.message'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontSize: 14,
                height: 1.4,
                color: muted,
              ),
            ),
            const SizedBox(height: 24),
            // Primary + secondary as a matched pair: same height/radius, the
            // brand green filled and a quiet tonal "cancel" beneath it.
            SheetButton(
              label: tr(l, 'auth.login_required.sign_in'),
              filled: true,
              isDark: isDark,
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).pop(true);
              },
            ),
            const SizedBox(height: 10),
            SheetButton(
              label: tr(l, 'auth.login_required.cancel'),
              filled: false,
              isDark: isDark,
              onTap: () => Navigator.of(context).pop(false),
            ),
            ],
          ),
        ),
      ),
    );
  }
}
