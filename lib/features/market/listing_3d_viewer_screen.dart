import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../auth/auth_storage.dart';
import 'api_marketplace_service.dart';
import 'models/market_listing.dart';
import 'widgets/listing_3d_viewer.dart';

/// Full-screen 3D model viewer for a marketplace listing. Fetches a signed
/// download URL for the listing's GLB file (and a USDZ companion for iOS AR
/// Quick Look when available), then renders [Listing3DViewer] full-bleed.
class Listing3DViewerScreen extends StatefulWidget {
  const Listing3DViewerScreen({
    super.key,
    required this.listing,
    this.api,
    this.authStorage = const AuthStorage(),
  });

  final MarketListing listing;
  final MarketplaceApiService? api;
  final AuthStorage authStorage;

  @override
  State<Listing3DViewerScreen> createState() => _Listing3DViewerScreenState();
}

class _Listing3DViewerScreenState extends State<Listing3DViewerScreen> {
  late final MarketplaceApiService _api;
  bool _loading = true;
  String? _source;
  String? _iosSrc;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? MarketplaceApiService();
    _load();
  }

  MarketListingFile? _pickFile(Iterable<String> formats) {
    for (final f in widget.listing.files) {
      if (formats.contains(f.format.toUpperCase())) return f;
    }
    return null;
  }

  Future<void> _load() async {
    final id = widget.listing.backendId;
    if (id == null) {
      setState(() {
        _loading = false;
        _error = 'Model ID topilmadi';
      });
      return;
    }

    final glb = _pickFile(const {'GLB', 'GLTF'});
    final usdz = _pickFile(const {'USDZ'});
    if (glb == null) {
      setState(() {
        _loading = false;
        _error = '3D ko‘rinish uchun GLB format topilmadi';
      });
      return;
    }

    try {
      final session = await widget.authStorage.loadSession();
      if (session.token == null) {
        setState(() {
          _loading = false;
          _error = '3D modelni ko‘rish uchun tizimga kiring';
        });
        return;
      }
      // 3D ko'rish bepul (egalik shart emas) — preview endpoint. Yuklab olish
      // (formatlar) hamon egalik bilan himoyalangan (getDownloadUrl).
      final src = await _api.getPreviewUrl(
        modelId: id,
        fileId: glb.id,
        token: session.token!,
      );
      String? iosUrl;
      if (usdz != null) {
        try {
          final iosInfo = await _api.getPreviewUrl(
            modelId: id,
            fileId: usdz.id,
            token: session.token!,
          );
          iosUrl = iosInfo.url;
        } catch (_) {
          // USDZ is optional — silently fall back to GLB-only viewer.
        }
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _source = src.url;
        _iosSrc = iosUrl;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final fg = isDark ? Colors.white : AppColors.textBlack;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: fg),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          widget.listing.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: fg,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            '$_error',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontSize: 14,
              height: 1.4,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.75)
                  : AppColors.textBlack.withValues(alpha: 0.75),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Listing3DViewer(
        source: _source!,
        iosSrc: _iosSrc,
        alt: widget.listing.title,
        height: MediaQuery.of(context).size.height * 0.8,
      ),
    );
  }
}

