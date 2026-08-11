/// In-app PDF viewer for the report deliverables (Baholash Xulosa, Narxlash
/// Orderi, 3D kadastr xulosa). Renders a local file with PDFium (via pdfx) so
/// the user can actually READ the report in-app — not just share/save it. A
/// share action stays in the app bar.
///
/// pdfx (PDFium) is used instead of flutter_pdfview because the latter's native
/// iOS view silently fails to render on iOS 26 (infinite spinner — onRender
/// never fires).
library;

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/haptics.dart';
import '../../core/i18n/app_translations.dart';
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
  late final PdfControllerPinch _controller;
  int _pages = 0;
  int _current = 1;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = PdfControllerPinch(
      document: PdfDocument.openFile(widget.filePath),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
            tooltip: tr(Locale(lang), 'applications.pdf.share'),
            onPressed: hapticTap(_share),
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: PdfViewPinch(
        controller: _controller,
        onDocumentLoaded: (doc) {
          if (!mounted) return;
          setState(() {
            _pages = doc.pagesCount;
            _ready = true;
          });
        },
        onPageChanged: (page) {
          if (!mounted) return;
          setState(() => _current = page);
        },
        builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
          options: const DefaultBuilderOptions(),
          documentLoaderBuilder: (_) =>
              const Center(child: CircularProgressIndicator()),
          pageLoaderBuilder: (_) =>
              const Center(child: CircularProgressIndicator()),
          errorBuilder: (_, error) => _ErrorView(lang: lang),
        ),
      ),
      bottomNavigationBar: (_ready && _pages > 0)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '$_current / $_pages',
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

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.lang});
  final String lang;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          tr(Locale(lang), 'applications.pdf.error'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontSize: 14,
            color: ColorTokens.secondaryText(context),
          ),
        ),
      ),
    );
  }
}

