/// Xona 3D modelini (gaussian splat) 3DGS serverdagi Spark viewer'ida
/// ko'rsatadi.
///
/// Nega WebView, nega GLB emas: quvur asosiy natija sifatida `.spz` splat
/// chiqaradi. GLB — o'sha splatdan TSDF orqali olingan mesh, ya'ni sifati
/// past. Ilovadagi mkkellogg viewer'i esa SPZ **v1-v2** ni o'qiydi, quvur
/// **v3** yozadi. Serverdagi Spark viewer aynan v3 uchun qurilgan — shuning
/// uchun splat o'sha yerda ochiladi.
///
/// QULFLANGAN: sahifa faqat SHU model uchun ochiladi. Viewer HUD'ida
/// `href="/"` havolasi bor va u serverning model ro'yxati / yuklash
/// konsoliga olib boradi — foydalanuvchi u yerga tushmasligi kerak. Ikki
/// qatlam: navigatsiya so'rovlari boshlang'ich URL'dan boshqasiga
/// o'tkazilmaydi, va sahifa yuklangach o'sha havola JS bilan olib tashlanadi.
library;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../theme/app_colors.dart';

class V2mViewerScreen extends StatefulWidget {
  const V2mViewerScreen({super.key, required this.url, this.title});

  /// To'liq viewer manzili: `.../view.html?m=models/<id>/scene.spz&n=<nom>`.
  final String url;

  /// Xona nomi — sahifaning pastidagi yozuvda ko'rinadi (`&n=`).
  /// Ekran ustida takrorlanmaydi.
  final String? title;

  @override
  State<V2mViewerScreen> createState() => _V2mViewerScreenState();
}

class _V2mViewerScreenState extends State<V2mViewerScreen> {
  late final WebViewController _controller;
  late final Uri _allowed = Uri.parse(widget.url);
  bool _loading = true;
  bool _failed = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          // Faqat shu viewer sahifasi. Boshqa har qanday o'tish — jumladan
          // HUD'dagi "←" (model ro'yxati, `/`) — bloklanadi. Rasm/skript/model
          // fayllari bu yerga tushmaydi (ular navigatsiya emas, resurs).
          //
          // Solishtirish host+path bo'yicha, satr tengligi bilan EMAS:
          // WebView URL'ni qayta kodlashi mumkin (`/` → `%2F` va aksincha) va
          // qat'iy tenglik boshlang'ich yuklashning o'zini ham bloklab qo'yadi.
          onNavigationRequest: (request) {
            final target = Uri.tryParse(request.url);
            final ok =
                target != null &&
                target.host == _allowed.host &&
                target.port == _allowed.port &&
                target.path == _allowed.path;
            return ok
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onPageFinished: (_) {
            _hideExternalLinks();
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            // Faqat ASOSIY hujjat xatosi muhim. Viewer three.js/Spark'ni CDN
            // dan oladi va ulardan biri yiqilsa ham sahifa ishlashi mumkin —
            // resurs xatosi butun ekranni xatoga aylantirmasligi kerak.
            if (error.isForMainFrame == false) return;
            if (mounted) {
              setState(() {
                _loading = false;
                _failed = true;
                _errorText = error.description;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  /// Sahifadagi tashqi havolalarni olib tashlaydi — bloklangan tugmani
  /// ko'rsatib qo'yishdan ko'ra, uni umuman ko'rsatmaslik to'g'ri.
  void _hideExternalLinks() {
    _controller.runJavaScript(
      "document.querySelectorAll('a').forEach(function(a){a.remove();});",
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // StackFit.expand — aks holda Stack o'z o'lchamini pozitsiyalanmagan
      // bolasiga (tepadagi sarlavha qatori) qarab oladi va markazdagi matn
      // o'sha tor bo'lak ichida, ya'ni ekran tepasida qolib ketadi.
      body: Stack(
        fit: StackFit.expand,
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppColors.splashGreen,
                ),
              ),
            ),
          if (_failed)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  _errorText == null
                      ? 'Model ochilmadi — internetni tekshirib qayta urining.'
                      : 'Model ochilmadi: $_errorText',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 14,
                    height: 1.4,
                    color: const Color(0xFF5B6B62),
                  ),
                ),
              ),
            ),
          Align(
            alignment: Alignment.topLeft,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    Material(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        child: const SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(
                            Icons.close_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
