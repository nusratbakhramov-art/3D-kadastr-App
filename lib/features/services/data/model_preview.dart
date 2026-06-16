import 'dart:io';

import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';
import '../../market/widgets/listing_3d_viewer.dart';
import '../../scans/saved_scan_service.dart';

/// Sniff the first 4 bytes: a binary glTF (GLB) file begins with ASCII "glTF"
/// (0x67 0x6C 0x54 0x46). A USDZ is a zip ("PK..").
Future<bool> isGlbFile(String path) async {
  try {
    final raf = await File(path).open();
    try {
      final head = await raf.read(4);
      return head.length >= 4 &&
          head[0] == 0x67 &&
          head[1] == 0x6C &&
          head[2] == 0x54 &&
          head[3] == 0x46;
    } finally {
      await raf.close();
    }
  } catch (_) {
    return false;
  }
}

/// Open a downloaded/local scan model in the CORRECT viewer regardless of how
/// the file was named on disk.
///
/// The backend now serves the primary model as **GLB** (`scan_usdz_key` → .glb).
/// SceneKit — the native `previewModel` path used by QuickLook — CANNOT load
/// GLB, so a GLB handed to it renders a blank screen. This routes by CONTENT:
/// GLB → `model_viewer_plus` (rotate/zoom); legacy USDZ → native SceneKit/
/// QuickLook. The file is first copied to a content-correct extension so each
/// viewer gets what it expects even if the download saved it as `.usdz`.
Future<void> openScanModel(
  BuildContext context,
  String path, {
  SavedScanService? scan,
}) async {
  final glb = await isGlbFile(path);
  if (glb) {
    final p = await _ensureExt(path, '.glb');
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => GlbViewerPage(filePath: p),
    ));
  } else {
    final p = await _ensureExt(path, '.usdz');
    await (scan ?? SavedScanService()).preview(p);
  }
}

/// Ensure [path] ends with [ext]; if not, copy it to a sibling file with that
/// extension (model_viewer_plus / QuickLook key off the extension). Returns the
/// original path if the copy fails.
Future<String> _ensureExt(String path, String ext) async {
  if (path.toLowerCase().endsWith(ext)) return path;
  final dot = path.lastIndexOf('.');
  final base = dot == -1 ? path : path.substring(0, dot);
  final out = '$base$ext';
  final f = File(out);
  if (!await f.exists()) {
    try {
      await File(path).copy(out);
    } catch (_) {
      return path;
    }
  }
  return out;
}

/// Full-screen GLB viewer (rotate/zoom) via `model_viewer_plus`. The local file
/// is passed as a `file://` URI so no re-download happens. AR is off — iOS AR
/// Quick Look needs a USDZ companion, which a GLB-only scan doesn't have.
class GlbViewerPage extends StatelessWidget {
  const GlbViewerPage({super.key, required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorTokens.scaffoldBg(context),
      body: SafeArea(
        child: Listing3DViewer(
          source: Uri.file(filePath).toString(),
          height: MediaQuery.of(context).size.height,
          ar: false,
          onClose: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }
}
