import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../../theme/color_tokens.dart';

/// Renders a 3D model with rotate/zoom and an optional AR launch button.
///
/// `source` accepts:
/// - an asset path (`assets/3d/test_model.glb`)
/// - a `file://` URI to a local file
/// - an HTTP/S URL — downloaded once into the cache directory and reused
///
/// iOS launches AR Quick Look when [iosSrc] is provided (typically a USDZ
/// companion); Android launches Scene Viewer with the GLB itself.
///
/// When [onClose] / [onShare] are provided, matching circular buttons are
/// drawn over the top corners of the viewer.
class Listing3DViewer extends StatefulWidget {
  const Listing3DViewer({
    super.key,
    required this.source,
    this.iosSrc,
    this.alt,
    this.height = 380,
    this.autoRotate = true,
    this.cameraControls = true,
    this.ar = true,
    this.onClose,
    this.onShare,
  });

  final String source;
  final String? iosSrc;
  final String? alt;
  final double height;
  final bool autoRotate;
  final bool cameraControls;
  final bool ar;
  final VoidCallback? onClose;
  final VoidCallback? onShare;

  @override
  State<Listing3DViewer> createState() => _Listing3DViewerState();
}

class _Listing3DViewerState extends State<Listing3DViewer> {
  late Future<String> _resolved;

  @override
  void initState() {
    super.initState();
    _resolved = _resolve(widget.source);
  }

  @override
  void didUpdateWidget(covariant Listing3DViewer old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      _resolved = _resolve(widget.source);
    }
  }

  Future<String> _resolve(String src) async {
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return ModelCache.fetch(src);
    }
    return src; // asset path or file:// URI — model_viewer accepts directly
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: ColorTokens.cardBg(context),
                child: FutureBuilder<String>(
                  future: _resolved,
                  builder: (context, snap) {
                    if (snap.hasError) return _ErrorState(error: snap.error!);
                    if (!snap.hasData) return const _LoadingState();
                    return ModelViewer(
                      backgroundColor: ColorTokens.cardBg(context),
                      src: snap.data!,
                      iosSrc: widget.iosSrc,
                      alt: widget.alt ?? '3D model',
                      ar: widget.ar,
                      arModes: const ['scene-viewer', 'webxr', 'quick-look'],
                      autoRotate: widget.autoRotate,
                      cameraControls: widget.cameraControls,
                      disableZoom: false,
                      interactionPrompt: InteractionPrompt.none,
                      shadowIntensity: 1.0,
                      exposure: 1.0,
                    );
                  },
                ),
              ),
            ),
            if (widget.onClose != null)
              Positioned(
                top: 12,
                left: 12,
                child: _CircleButton(
                  iconAsset: 'assets/icons/close.svg',
                  onTap: widget.onClose!,
                ),
              ),
            if (widget.onShare != null)
              Positioned(
                top: 12,
                right: 12,
                child: _CircleButton(
                  iconAsset: 'assets/icons/share.svg',
                  onTap: widget.onShare!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          valueColor: AlwaysStoppedAnimation(ColorTokens.brandPrimary(context)),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '3D modelni yuklab bo‘lmadi:\n$error',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontSize: 13,
            height: 1.4,
            color: ColorTokens.secondaryText(context),
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.iconAsset, required this.onTap});

  final String iconAsset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ColorTokens.cardBg(context).withValues(alpha: 0.9),
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: ColorTokens.shadow(context),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: SvgPicture.asset(
              iconAsset,
              width: 18,
              height: 18,
              colorFilter: ColorFilter.mode(
                ColorTokens.primaryText(context),
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tiny disk cache for 3D models. Files are keyed by SHA1 of the URL and
/// stored under the OS temp directory. Subsequent loads of the same URL
/// return the local file path (used as `file://...` by `model_viewer_plus`).
class ModelCache {
  const ModelCache._();

  static const String _subdir = 'kadastr_3d_cache';
  static final Map<String, Future<String>> _inflight = {};

  static Future<String> fetch(String url) {
    return _inflight.putIfAbsent(url, () async {
      try {
        final dir = await _ensureDir();
        final ext = _extOf(url);
        final hash = base64Url.encode(utf8.encode(url)).replaceAll('=', '');
        // Filename length cap (some FS — 255 bytes) — truncate the hash if
        // unusually long (rare for our presigned URLs).
        final safeHash = hash.length > 200 ? hash.substring(0, 200) : hash;
        final file = File('${dir.path}/$safeHash$ext');

        if (await file.exists() && await file.length() > 0) {
          return file.uri.toString();
        }
        final res = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) {
          throw HttpException(
            'HTTP ${res.statusCode} fetching 3D model',
            uri: Uri.parse(url),
          );
        }
        await file.writeAsBytes(res.bodyBytes, flush: true);
        return file.uri.toString();
      } finally {
        _inflight.remove(url);
      }
    });
  }

  static Future<Directory> _ensureDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/$_subdir');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _extOf(String url) {
    final clean = url.split('?').first;
    final dot = clean.lastIndexOf('.');
    if (dot == -1) return '.bin';
    final candidate = clean.substring(dot).toLowerCase();
    return candidate.length <= 6 ? candidate : '.bin';
  }
}
