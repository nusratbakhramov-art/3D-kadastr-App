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
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/haptics.dart';
import '../../core/i18n/app_translations.dart';
import '../settings/settings_state.dart';

class SplatViewerScreen extends StatefulWidget {
  const SplatViewerScreen({super.key, required this.splatFilePath, this.title});

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
  HttpServer? _server;

  @override
  void initState() {
    super.initState();
    _viewerUrl = _startLocalServer();
  }

  @override
  void dispose() {
    _server?.close(force: true);
    super.dispose();
  }

  /// Loopback HTTP server ishga tushiradi va `http://127.0.0.1:PORT/viewer.html`
  /// `?splat=<filename>` URL'ini qaytaradi.
  ///
  /// **Nega kerak:** WKWebView'da `file://` dokument boshqa `file://` resursni
  /// `fetch()` qila olmaydi (har file URL alohida origin sifatida hisoblanadi —
  /// hatto same directory bo'lsa ham). `loadFile()` + `allowingReadAccessToURL:`
  /// faqat WebKit'ning resource loader'iga ruxsat beradi, JS fetch API'ga emas.
  /// Loopback HTTP server bilan har ikkala fayl bir xil http origin'da
  /// serve qilinadi — CORS muammosi yo'q.
  Future<String> _startLocalServer() async {
    final viewerHtml = await rootBundle.loadString(
      'assets/3d/splat_viewer.html',
    );
    final splatFile = File(widget.splatFilePath);
    final splatName = splatFile.uri.pathSegments.last;
    final splatLength = await splatFile.length();

    // Library fayllarni asset'dan oldindan o'qib xotirada saqlaymiz —
    // har request uchun bundle'dan o'qish sekin bo'lar edi.
    final libFiles = <String, Uint8List>{
      '/lib/three.module.js': (await rootBundle.load(
        'assets/3d/lib/three.module.js',
      )).buffer.asUint8List(),
      '/lib/gaussian-splats-3d.module.js': (await rootBundle.load(
        'assets/3d/lib/gaussian-splats-3d.module.js',
      )).buffer.asUint8List(),
    };

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;

    server.listen((req) async {
      try {
        final path = req.uri.path;
        if (path == '/' || path == '/viewer.html') {
          req.response.headers.set(
            HttpHeaders.contentTypeHeader,
            'text/html; charset=utf-8',
          );
          req.response.headers.set('cache-control', 'no-store');
          req.response.write(viewerHtml);
          await req.response.close();
        } else if (libFiles.containsKey(path)) {
          final bytes = libFiles[path]!;
          req.response.headers.set(
            HttpHeaders.contentTypeHeader,
            'application/javascript; charset=utf-8',
          );
          req.response.headers.set('cache-control', 'no-store');
          req.response.headers.contentLength = bytes.length;
          req.response.add(bytes);
          await req.response.close();
        } else if (path == '/$splatName') {
          // Range support (mkkellogg progressive load uchun foydali)
          final rangeHeader = req.headers.value(HttpHeaders.rangeHeader);
          req.response.headers.set('accept-ranges', 'bytes');
          req.response.headers.set(
            HttpHeaders.contentTypeHeader,
            'application/octet-stream',
          );
          if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
            final spec = rangeHeader.substring(6).split('-');
            final start = int.tryParse(spec[0]) ?? 0;
            final end = (spec.length > 1 && spec[1].isNotEmpty)
                ? int.tryParse(spec[1]) ?? splatLength - 1
                : splatLength - 1;
            final length = end - start + 1;
            req.response.statusCode = HttpStatus.partialContent;
            req.response.headers.contentLength = length;
            req.response.headers.set(
              'content-range',
              'bytes $start-$end/$splatLength',
            );
            await splatFile.openRead(start, end + 1).pipe(req.response);
          } else {
            req.response.headers.contentLength = splatLength;
            await splatFile.openRead().pipe(req.response);
          }
        } else {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
        }
      } catch (_) {
        try {
          req.response.statusCode = HttpStatus.internalServerError;
          await req.response.close();
        } catch (_) {}
      }
    });

    return 'http://127.0.0.1:${server.port}/viewer.html?splat=$splatName';
  }

  Future<void> _shareSplat() async {
    final locale = localeNotifier.value;
    await Share.shareXFiles([
      XFile(widget.splatFilePath),
    ], text: widget.title ?? _Strings.shareTitle(locale));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (context, locale, _) => Scaffold(
        backgroundColor: const Color(0xFF1a1a1a),
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.black.withValues(alpha: 0.4),
          elevation: 0,
          foregroundColor: Colors.white,
          title: Text(
            widget.title ?? _Strings.viewerTitle(locale),
            style: const TextStyle(color: Colors.white, fontSize: 17),
          ),
          actions: [
            IconButton(
              tooltip: _Strings.share(locale),
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: hapticTap(_shareSplat),
            ),
          ],
        ),
        body: FutureBuilder<String>(
          future: _viewerUrl,
          builder: (context, snap) {
            if (snap.hasError) {
              return _ErrorView(error: snap.error!, locale: locale);
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
        width: 48,
        height: 48,
        child: CircularProgressIndicator(
          strokeWidth: 2.8,
          valueColor: AlwaysStoppedAnimation(Colors.white),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.locale});

  final Object error;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.white54,
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              _Strings.openError(locale),
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

class _Strings {
  static String shareTitle(Locale l) => _p(l, 'scan.splat.share_title');
  static String viewerTitle(Locale l) => _p(l, 'scan.splat.viewer_title');
  static String share(Locale l) => _p(l, 'common.share');
  static String openError(Locale l) => _p(l, 'scan.splat.open_error');
  static String _p(Locale l, String key) => tr(l, key);
}
