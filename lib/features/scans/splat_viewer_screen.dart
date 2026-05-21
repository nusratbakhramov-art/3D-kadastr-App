/// 3D Gaussian Splat ko'ruvchi ekran.
///
/// `.splat` (antimatter15 binary format) faylni WebView ichidagi
/// `assets/3d/splat_viewer.html` orqali ko'rsatadi. Viewer @mkkellogg/
/// gaussian-splats-3d kutubxonasini CDN'dan yuklaydi va WebGL2 orqali
/// real-time ko'rsatadi.
///
/// Foydalanish — chaqiruvchi `.splat` faylni oldindan local diskka yuklab
/// (AuthHttpClient bilan auth qilib) `splatFilePath` ni beradi:
/// ```dart
/// Navigator.push(context, MaterialPageRoute(
///   builder: (_) => SplatViewerScreen(
///     splatFilePath: '/var/.../scene.splat',
///     title: 'Skan #123',
///   ),
/// ));
/// ```
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

class SplatViewerScreen extends StatefulWidget {
  const SplatViewerScreen({
    super.key,
    required this.splatFilePath,
    this.title,
  });

  /// Local diskdagi `.splat` fayl yo'li (chaqiruvchi auth bilan yuklab kelgan).
  final String splatFilePath;

  /// AppBar'da ko'rsatiladigan sarlavha.
  final String? title;

  @override
  State<SplatViewerScreen> createState() => _SplatViewerScreenState();
}

class _SplatViewerScreenState extends State<SplatViewerScreen> {
  late final Future<String> _viewerUrl;
  WebViewController? _webView;

  @override
  void initState() {
    super.initState();
    _viewerUrl = _prepareViewerHtml();
  }

  /// viewer.html'ni Flutter asset'dan diskka ko'chiradi (har ochishda toza)
  /// va `?splat=file:///.../scene.splat` query bilan URL qaytaradi.
  ///
  /// file:// dan tashqi CDN'ga fetch qilish — iOS WKWebView'da ruxsatli
  /// (CORS bo'lsa ham, JS module importmap CDN'dan yuklanadi).
  Future<String> _prepareViewerHtml() async {
    final tempDir = await getTemporaryDirectory();
    final viewerDir = Directory('${tempDir.path}/splat_viewer');
    if (!await viewerDir.exists()) {
      await viewerDir.create(recursive: true);
    }

    final viewerHtml =
        await rootBundle.loadString('assets/3d/splat_viewer.html');
    final viewerFile = File('${viewerDir.path}/viewer.html');
    await viewerFile.writeAsString(viewerHtml, flush: true);

    final splatFileUri = Uri.file(widget.splatFilePath).toString();
    final viewerUri = Uri.file(viewerFile.path).replace(
      queryParameters: {'splat': splatFileUri},
    );
    return viewerUri.toString();
  }

  Future<void> _shareSplat() async {
    await Share.shareXFiles(
      [XFile(widget.splatFilePath)],
      text: widget.title ?? '3D skan',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a1a),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.4),
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          widget.title ?? '3D ko\'rinish',
          style: const TextStyle(color: Colors.white, fontSize: 17),
        ),
        actions: [
          IconButton(
            tooltip: 'Ulashish',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: _shareSplat,
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: _viewerUrl,
        builder: (context, snap) {
          if (snap.hasError) {
            return _ErrorView(error: snap.error!);
          }
          if (!snap.hasData) {
            return const _LoadingView();
          }
          _webView ??= WebViewController()
            ..setJavaScriptMode(JavaScriptMode.unrestricted)
            ..setBackgroundColor(const Color(0xFF1a1a1a))
            ..loadRequest(Uri.parse(snap.data!));
          return WebViewWidget(controller: _webView!);
        },
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 48, height: 48,
        child: CircularProgressIndicator(
          strokeWidth: 2.8,
          valueColor: AlwaysStoppedAnimation(Colors.white),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.white54, size: 56),
            const SizedBox(height: 16),
            const Text(
              '3D modelni ochib bo\'lmadi',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
