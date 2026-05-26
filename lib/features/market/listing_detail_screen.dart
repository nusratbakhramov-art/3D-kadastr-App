import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../auth/auth_storage.dart';
import 'api_marketplace_service.dart';
import 'listing_3d_viewer_screen.dart';
import 'models/market_listing.dart';
import 'widgets/listing_formats_card.dart';
import 'widgets/listing_gallery_pager.dart';
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
  int? _downloadingFileId;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? MarketplaceApiService();
  }

  void _close() => Navigator.of(context).maybePop();

  bool get _has3DViewable {
    for (final f in widget.listing.files) {
      final fmt = f.format.toUpperCase();
      if (fmt == 'GLB' || fmt == 'GLTF') return true;
    }
    return false;
  }

  void _open3DViewer() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Listing3DViewerScreen(
          listing: widget.listing,
          api: _api,
          authStorage: widget.authStorage,
        ),
      ),
    );
  }

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

  Future<void> _downloadFormat(MarketListingFile file) async {
    if (_downloadingFileId != null) return;
    final id = widget.listing.backendId;
    if (id == null) {
      AppToast.error(context, 'Model ID topilmadi');
      return;
    }
    setState(() => _downloadingFileId = file.id);
    try {
      final session = await widget.authStorage.loadSession();
      if (session.token == null) {
        if (!mounted) return;
        AppToast.error(context, 'Yuklab olish uchun tizimga kiring');
        return;
      }
      final info = await _api.getDownloadUrl(
        modelId: id,
        fileId: file.id,
        token: session.token!,
      );
      final bytes = await _bytesFor(info.url);
      final dir = await getTemporaryDirectory();
      final safeTitle = widget.listing.title
          .replaceAll(RegExp(r'[^A-Za-z0-9_\- ]'), '')
          .replaceAll(' ', '_');
      final ext = file.format.toLowerCase();
      final filename = '${safeTitle.isEmpty ? 'model' : safeTitle}.$ext';
      final outFile = File('${dir.path}/$filename');
      await outFile.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      final origin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null;
      await Share.shareXFiles(
        [XFile(outFile.path, name: filename)],
        subject: widget.listing.title,
        sharePositionOrigin: origin,
      );
      if (!mounted) return;
      AppToast.success(context, '$filename tayyor');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Yuklab olishda xatolik: $e');
    } finally {
      if (mounted) setState(() => _downloadingFileId = null);
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
              child: ListingGalleryPager(
                images: listing.galleryImages,
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
            if (_has3DViewable) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _View3DButton(onTap: _open3DViewer),
              ),
            ],
            if (listing.files.isNotEmpty) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ListingFormatsCard(
                  files: listing.files,
                  downloadingFileId: _downloadingFileId,
                  onTap: _downloadFormat,
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _View3DButton extends StatelessWidget {
  const _View3DButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = AppColors.splashGreen;
    final fg = AppColors.buttonTextBlack;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.view_in_ar_rounded, size: 22, color: fg),
              const SizedBox(width: 10),
              Text(
                '3D modelni ko‘rish',
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  height: 1.2,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
