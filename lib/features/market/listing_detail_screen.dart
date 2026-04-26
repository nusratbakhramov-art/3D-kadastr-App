import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../theme/app_colors.dart';
import 'models/listing_format.dart';
import 'models/market_listing.dart';
import 'models/payment_method.dart';
import 'widgets/listing_cta_button.dart';
import 'widgets/listing_formats_card.dart';
import 'widgets/listing_gallery.dart';
import 'widgets/listing_info_card.dart';
import 'widgets/listing_meta_pills.dart';
import 'widgets/listing_payment_card.dart';

class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({super.key, required this.listing});

  final MarketListing listing;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  ListingFormat _format = ListingFormat.glb;
  PaymentMethod _payment = PaymentMethod.payme;

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

  void _pay() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          'To\'lov tez orada: ${_payment.label} · ${_format.label}',
        ),
      ),
    );
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
            ListingGallery(
              images: listing.galleryImages,
              heroTag: 'listing.${listing.id}',
              onClose: _close,
              onShare: _share,
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
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListingFormatsCard(
                selected: _format,
                onChanged: (f) => setState(() => _format = f),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListingPaymentCard(
                selected: _payment,
                onChanged: (p) => setState(() => _payment = p),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListingCtaButton(
                label: 'To\'lov qilish va yuklab olish',
                onTap: _pay,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
