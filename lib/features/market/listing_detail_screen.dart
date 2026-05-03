import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../auth/auth_storage.dart';
import 'api_marketplace_service.dart';
import 'models/market_listing.dart';
import 'widgets/listing_3d_viewer.dart';
import 'widgets/listing_cta_button.dart';
import 'widgets/listing_info_card.dart';
import 'widgets/listing_meta_pills.dart';

class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({
    super.key,
    required this.listing,
    this.api,
    this.authStorage = const AuthStorage(),
  });

  final MarketListing listing;
  final MarketplaceApiService? api;
  final AuthStorage authStorage;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  late final MarketplaceApiService _api;
  bool _downloading = false;

  /// Resolved direct URL to the model file (cached after first call).
  String? _modelUrl;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? MarketplaceApiService();
    _resolveModelUrl();
  }

  MarketListingFile? get _glbFile {
    final files = widget.listing.files;
    if (files.isEmpty) return null;
    // Prefer GLB; otherwise fall back to the first available file.
    for (final f in files) {
      if (f.format.toUpperCase() == 'GLB') return f;
    }
    return files.first;
  }

  Future<void> _resolveModelUrl() async {
    final id = widget.listing.backendId;
    final file = _glbFile;
    if (id == null || file == null) {
      // Mock listing or no file — fall back to bundled test asset so the
      // viewer still renders something during dev.
      setState(() => _modelUrl = 'assets/3d/test_model.glb');
      return;
    }
    try {
      final session = await widget.authStorage.loadSession();
      if (session.token == null) {
        // Avtorizatsiyasiz — fallback bundled asset ishlatiladi.
        setState(() => _modelUrl = 'assets/3d/test_model.glb');
        return;
      }
      final info = await _api.getDownloadUrl(
        modelId: id,
        fileId: file.id,
        token: session.token!,
      );
      if (!mounted) return;
      setState(() => _modelUrl = info.url);
    } catch (e) {
      // Backend xatosi (eski cached id, network, va h.k.) — bundled asset
      // ko'rinadi, shuning uchun foydalanuvchiga noaniq xato chiqarmaymiz.
      if (!mounted) return;
      setState(() => _modelUrl = 'assets/3d/test_model.glb');
    }
  }

  void _close() => Navigator.of(context).maybePop();

  void _share() {
    final l = widget.listing;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    Share.share(
      '${l.title}\n${l.district} · ${l.areaM2} m²',
      subject: l.title,
      sharePositionOrigin: origin,
    );
  }

  Future<void> _download() async {
    if (_downloading) return;
    final url = _modelUrl;
    if (url == null) {
      AppToast.error(context, 'Model hali tayyor emas');
      return;
    }
    final file = _glbFile;
    setState(() => _downloading = true);
    try {
      final bytes = await _bytesFor(url);
      final dir = await getTemporaryDirectory();
      final safeTitle = widget.listing.title
          .replaceAll(RegExp(r'[^A-Za-z0-9_\- ]'), '')
          .replaceAll(' ', '_');
      final ext = (file?.format ?? 'GLB').toLowerCase();
      final filename =
          '${safeTitle.isEmpty ? 'model' : safeTitle}.$ext';
      final outFile = File('${dir.path}/$filename');
      await outFile.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      final origin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null;
      await Share.shareXFiles(
        [XFile(outFile.path, mimeType: 'model/gltf-binary', name: filename)],
        subject: widget.listing.title,
        sharePositionOrigin: origin,
      );
      if (!mounted) return;
      AppToast.success(context, 'Yuklab olishga tayyor: $filename');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Yuklab olishda xatolik: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<List<int>> _bytesFor(String src) async {
    if (src.startsWith('http://') || src.startsWith('https://')) {
      final res = await http
          .get(Uri.parse(src))
          .timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(src));
      }
      return res.bodyBytes;
    }
    if (src.startsWith('file://')) {
      return await File.fromUri(Uri.parse(src)).readAsBytes();
    }
    if (src.startsWith('assets/')) {
      final data = await DefaultAssetBundle.of(
        context,
      ).load(src);
      return data.buffer.asUint8List();
    }
    throw StateError('Unknown source: $src');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final listing = widget.listing;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Listing3DViewer(
                source: _modelUrl ?? 'assets/3d/test_model.glb',
                alt: listing.title,
                onClose: _close,
                onShare: _share,
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListingMetaPills(
                district: listing.district,
                areaM2: listing.areaM2,
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListingInfoCard(
                priceUzs: listing.priceUzs,
                title: listing.title,
                description: listing.description,
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListingCtaButton(
                label: _downloading ? 'Yuklanmoqda...' : 'Yuklab olish',
                onTap: _downloading
                    ? () {}
                    : () {
                        _download();
                      },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
