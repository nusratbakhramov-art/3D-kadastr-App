import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
    var p = await _ensureExt(path, '.glb');
    // "Dollhouse": GLB materiallarini single-sided qilamiz → model_viewer
    // kameraga qaragan (yaqin) devorni back-face cull qiladi va xona ichi
    // ko'rinadi (xuddi skandan keyingi native viewer'дek). GLB sifati saqlanadi.
    p = await _glbForceSingleSided(p);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => GlbViewerPage(filePath: p),
    ));
  } else {
    final p = await _ensureExt(path, '.usdz');
    await (scan ?? SavedScanService()).preview(p);
  }
}

/// Rewrites a GLB so every material is single-sided (`doubleSided=false`). With
/// the room mesh's inward-facing normals, model_viewer then back-face-culls the
/// wall facing the camera → "dollhouse" (you see into the room), matching the
/// native post-scan viewer. Only the JSON chunk's material flags change; the
/// binary buffer (mesh + texture) is copied verbatim → no quality loss. Returns
/// a sibling `*.dh.glb` path, or the original on any failure.
Future<String> _glbForceSingleSided(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    if (bytes.length < 20) return path;
    final bd = ByteData.sublistView(bytes);
    if (bd.getUint32(0, Endian.little) != 0x46546C67) return path; // 'glTF'
    final jsonLen = bd.getUint32(12, Endian.little);
    if (bd.getUint32(16, Endian.little) != 0x4E4F534A) return path; // 'JSON'
    final jsonEnd = 20 + jsonLen;
    if (jsonEnd > bytes.length) return path;
    final gltf =
        jsonDecode(utf8.decode(bytes.sublist(20, jsonEnd))) as Map<String, dynamic>;
    final materials = gltf['materials'];
    if (materials is! List || materials.isEmpty) return path;
    var changed = false;
    for (final m in materials) {
      if (m is Map<String, dynamic> && m['doubleSided'] != false) {
        m['doubleSided'] = false;
        changed = true;
      }
    }
    if (!changed) return path;
    // Re-encode JSON chunk; pad to a 4-byte boundary with spaces (glTF spec).
    final newJson = <int>[...utf8.encode(jsonEncode(gltf))];
    while (newJson.length % 4 != 0) {
      newJson.add(0x20);
    }
    final binChunk = bytes.sublist(jsonEnd); // BIN chunk header + data, verbatim
    final total = 20 + newJson.length + binChunk.length;
    final header = ByteData(20);
    header.setUint32(0, 0x46546C67, Endian.little); // magic 'glTF'
    header.setUint32(4, 2, Endian.little); // version
    header.setUint32(8, total, Endian.little); // total byte length
    header.setUint32(12, newJson.length, Endian.little); // JSON chunk length
    header.setUint32(16, 0x4E4F534A, Endian.little); // 'JSON'
    final out = BytesBuilder()
      ..add(header.buffer.asUint8List())
      ..add(newJson)
      ..add(binChunk);
    final outPath = path.endsWith('.glb')
        ? '${path.substring(0, path.length - 4)}.dh.glb'
        : '$path.dh.glb';
    await File(outPath).writeAsBytes(out.toBytes(), flush: true);
    return outPath;
  } catch (_) {
    return path;
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
