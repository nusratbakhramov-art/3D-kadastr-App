/// In-app PDF viewer for the report deliverables (Baholash Xulosa, Narxlash
/// Orderi, 3D Kadastr xulosa). Renders a local file with native PDF rendering
/// so the user can actually READ the report in-app — not just share/save it
/// (which dead-ends on Android devices with no PDF app installed). A share
/// action stays in the app bar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:share_plus/share_plus.dart';

import '../../theme/color_tokens.dart';

class PdfViewerScreen extends StatefulWidget {
  const PdfViewerScreen({
    super.key,
    required this.filePath,
    required this.title,
    this.shareName,
  });

  final String filePath;
  final String title;

  /// Filename used when sharing/saving (defaults to the title).
  final String? shareName;

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  int _pages = 0;
  int _current = 0;
  bool _ready = false;
  String? _error;

  Future<void> _share() async {
    final box = context.findRenderObject() as RenderBox?;
    await Share.shareXFiles(
      [
        XFile(
          widget.filePath,
          mimeType: 'application/pdf',
          name: widget.shareName ?? '${widget.title}.pdf',
        ),
      ],
      sharePositionOrigin:
          box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    return Scaffold(
      backgroundColor: ColorTokens.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: ColorTokens.cardBg(context),
        foregroundColor: ColorTokens.primaryText(context),
        elevation: 0.5,
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: ColorTokens.primaryText(context),
          ),
        ),
        actions: [
          IconButton(
            tooltip: _PdfStrings.share(lang),
            onPressed: _share,
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          PDFView(
            filePath: widget.filePath,
            enableSwipe: true,
            swipeHorizontal: false,
            autoSpacing: true,
            pageFling: true,
            fitPolicy: FitPolicy.WIDTH,
            onRender: (pages) {
              if (!mounted) return;
              setState(() {
                _pages = pages ?? 0;
                _ready = true;
              });
            },
            onError: (e) {
              if (!mounted) return;
              setState(() => _error = '$e');
            },
            onPageChanged: (page, total) {
              if (!mounted) return;
              setState(() => _current = page ?? 0);
            },
          ),
          if (!_ready && _error == null)
            const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _PdfStrings.error(lang),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontSize: 14,
                    color: ColorTokens.secondaryText(context),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: (_ready && _pages > 0)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '${_current + 1} / $_pages',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: ColorTokens.secondaryText(context),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class _PdfStrings {
  const _PdfStrings._();

  static String share(String lang) => switch (lang) {
        'ru' => 'Поделиться',
        'en' => 'Share',
        _ => 'Ulashish',
      };

  static String error(String lang) => switch (lang) {
        'ru' => 'Не удалось открыть PDF',
        'en' => 'Could not open the PDF',
        _ => 'PDF ochib bo\'lmadi',
      };
}
