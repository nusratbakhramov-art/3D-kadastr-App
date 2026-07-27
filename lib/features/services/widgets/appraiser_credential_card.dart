import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/remote_image.dart';
import '../api_appraiser_service.dart';

/// One appraiser credential document as a tappable card (thumbnail + title +
/// hint). Shared so the AI-Baholash credentials list and the profile About page
/// render identical cards — the AI screen stacks them one per row, the About
/// page lays them out two-up.
class AppraiserCredentialCard extends StatelessWidget {
  const AppraiserCredentialCard({
    super.key,
    required this.credential,
    required this.viewHint,
    required this.isDark,
    required this.onTap,
  });

  final AppraiserCredential credential;
  final String viewHint;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final titleColor = isDark ? Colors.white : AppColors.textBlack;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: hapticTap(onTap),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 58,
                  height: 78,
                  // Images (and PDFs whose first page the server rendered) show
                  // a real thumbnail; a PDF with no rendered preview falls back
                  // to its icon rather than a broken image.
                  child: credential.previewUrl.isNotEmpty
                      ? RemoteImage(
                          url: credential.previewUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 240,
                        )
                      : credential.isPdf
                      ? ColoredBox(
                          color: AppColors.declineRed.withValues(alpha: 0.12),
                          child: const Center(
                            child: Icon(
                              Icons.picture_as_pdf_rounded,
                              size: 26,
                              color: AppColors.declineRed,
                            ),
                          ),
                        )
                      : RemoteImage(
                          url: credential.imageUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 240,
                        ),
                ),
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
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      viewHint,
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 12,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.zoom_out_map_rounded, size: 20, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}
