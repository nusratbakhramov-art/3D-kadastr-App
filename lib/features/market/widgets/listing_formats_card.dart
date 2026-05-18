import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import '../models/market_listing.dart';

class ListingFormatsCard extends StatelessWidget {
  const ListingFormatsCard({
    super.key,
    required this.files,
    required this.onTap,
    this.downloadingFileId,
  });

  /// Files available for this listing (only these formats are shown).
  final List<MarketListingFile> files;

  /// Called when a chip is tapped — receives the file to download.
  final ValueChanged<MarketListingFile> onTap;

  /// If non-null, that file's chip shows a spinner.
  final int? downloadingFileId;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF121617) : Colors.white;
    final fg = isDark ? Colors.white : AppColors.textBlack;
    final border = isDark ? null : Border.all(color: const Color(0xFFE3E5E8));

    if (files.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: border,
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Formatlar',
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              height: 1.3,
              color: fg,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in files)
                _FormatChip(
                  label: _formatLabel(f.format),
                  size: _sizeLabel(f.fileSize),
                  loading: downloadingFileId == f.id,
                  onTap: () {
                    if (downloadingFileId != null) return;
                    HapticFeedback.selectionClick();
                    onTap(f);
                  },
                  fg: fg,
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatLabel(String raw) {
    final u = raw.toUpperCase();
    return u == 'GLTF' ? 'glTF' : u;
  }

  static String _sizeLabel(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    if (bytes < 1024 * 1024 * 1024) {
      final mb = bytes / (1024 * 1024);
      return '${mb < 10 ? mb.toStringAsFixed(1) : mb.round()} MB';
    }
    final gb = bytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(1)} GB';
  }
}

class _FormatChip extends StatelessWidget {
  const _FormatChip({
    required this.label,
    required this.size,
    required this.loading,
    required this.onTap,
    required this.fg,
  });

  final String label;
  final String size;
  final bool loading;
  final VoidCallback onTap;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    final borderColor = loading
        ? AppColors.splashGreen
        : const Color(0xFFD1D5D9);
    final textColor = loading
        ? AppColors.splashGreen
        : fg.withValues(alpha: 0.8);
    final bg = loading
        ? AppColors.splashGreen.withValues(alpha: 0.12)
        : Colors.transparent;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading) ...[
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    valueColor: AlwaysStoppedAnimation(AppColors.splashGreen),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      height: 1.2,
                      letterSpacing: 0.2,
                      color: textColor,
                    ),
                  ),
                  if (size.isNotEmpty)
                    Text(
                      size,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w400,
                        fontSize: 10,
                        height: 1.3,
                        color: textColor.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
