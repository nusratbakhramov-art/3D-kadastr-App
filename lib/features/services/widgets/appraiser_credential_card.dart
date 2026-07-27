import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/remote_image.dart';
import '../api_appraiser_service.dart';

/// One appraiser credential document as a tappable card.
///
/// Two layouts:
///  * default (row) — thumbnail left, title + hint right. Used where cards stack
///    full-width in a single column (the AI Baholash pre-payment step).
///  * [poster] — a large portrait thumbnail on top with the title below, for the
///    two-up grid on the profile About page, so the certificate itself reads as
///    the hero instead of a cropped sliver.
class AppraiserCredentialCard extends StatelessWidget {
  const AppraiserCredentialCard({
    super.key,
    required this.credential,
    required this.viewHint,
    required this.isDark,
    required this.onTap,
    this.poster = false,
  });

  final AppraiserCredential credential;
  final String viewHint;
  final bool isDark;
  final VoidCallback onTap;
  final bool poster;

  Color get _surface => isDark ? const Color(0xFF1F2426) : Colors.white;
  Color get _border => isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
  Color get _title => isDark ? Colors.white : AppColors.textBlack;
  Color get _muted => isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

  /// The document preview: rendered thumbnail, a PDF fallback icon, or the image.
  Widget _thumb() {
    if (credential.previewUrl.isNotEmpty) {
      return RemoteImage(
        url: credential.previewUrl,
        fit: BoxFit.cover,
        memCacheWidth: 400,
      );
    }
    if (credential.isPdf) {
      return ColoredBox(
        color: AppColors.declineRed.withValues(alpha: 0.12),
        child: const Center(
          child: Icon(Icons.picture_as_pdf_rounded,
              size: 30, color: AppColors.declineRed),
        ),
      );
    }
    return RemoteImage(
      url: credential.imageUrl,
      fit: BoxFit.cover,
      memCacheWidth: 400,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hapticTap(onTap),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: _border),
          ),
          child: poster ? _posterBody() : _rowBody(),
        ),
      ),
    );
  }

  // ── Poster: portrait thumbnail on top, title below ──────────────────────
  Widget _posterBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0C1512) : const Color(0xFFF0F2F3),
              border: Border(bottom: BorderSide(color: _border)),
            ),
            child: _thumb(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(11, 10, 11, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                credential.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  height: 1.2,
                  color: _title,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                viewHint,
                style: const TextStyle(
                  fontFamily: 'MTSText',
                  fontSize: 12,
                  color: AppColors.splashGreen,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Row: thumbnail left, title + hint right ─────────────────────────────
  Widget _rowBody() {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(width: 58, height: 78, child: _thumb()),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  credential.title,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: _title,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  viewHint,
                  style: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 12,
                    color: _muted,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.zoom_out_map_rounded, size: 20, color: _muted),
        ],
      ),
    );
  }
}
