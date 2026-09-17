import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
import '../data/pano_capture_channel.dart';
import 'pano_tour_screen.dart';

/// Android acceptance screen uses the existing interactive Flutter panorama viewer.
class PanoPreviewScreen extends StatefulWidget {
  const PanoPreviewScreen({super.key, required this.path});
  final String path;

  @override
  State<PanoPreviewScreen> createState() => _PanoPreviewScreenState();
}

class _PanoPreviewScreenState extends State<PanoPreviewScreen> {
  bool _ready = false;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return Scaffold(
      body: PanoTourScreen(
        panoramas: [TourPano(ref: widget.path, file: widget.path)],
        links: const [],
        onImageReady: (ready) {
          // Viewer init can run while its parent is building.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _ready != ready) setState(() => _ready = ready);
          });
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.pop(context, PanoPreviewAction.retake),
                  child: Text(tr(locale, 'bozor.pano.preview.retake')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _ready
                      ? () => Navigator.pop(context, PanoPreviewAction.accept)
                      : null,
                  child: Text(tr(locale, 'bozor.pano.preview.accept')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
