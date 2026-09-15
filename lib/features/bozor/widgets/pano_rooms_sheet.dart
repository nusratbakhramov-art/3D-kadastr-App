/// «360 foto qo'shish» bosilganda — XONALAR varag'i.
///
/// Har 360° skan xonaga bog'lanadi (nom capture'dan oldin so'raladi —
/// `showRoomPickerSheet`). Bu varaq allaqachon skan qilingan xonalarni
/// ro'yxat qilib ko'rsatadi (nomi, holati, eskizi) va pastda «Yangi xona
/// skan qilish» tugmasi turadi. Xona bosilsa — o'sha xonaning ochilishi
/// (sfera/tur, yoki saqlangan skan davomi); tugma — yangi skan.
///
/// Birinchi skanda (xona yo'q) varaq umuman ochilmaydi — to'g'ridan nom
/// so'raladi; buni chaqiruvchi hal qiladi.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../market/widgets/listing_cta_button.dart';

/// Varaq natijasi: mavjud xona indeksi (`>= 0`) yoki [PanoRoomsSheetResult.newRoom].
@immutable
class PanoRoomsSheetResult {
  const PanoRoomsSheetResult.open(this.index) : newRoom = false;
  const PanoRoomsSheetResult.add() : index = -1, newRoom = true;

  final int index;
  final bool newRoom;
}

/// Ro'yxatdagi xona holati — [PanoRoomItem.status].
enum PanoRoomStatus { ready, local, failed, pending }

@immutable
class PanoRoomItem {
  const PanoRoomItem({
    required this.name,
    required this.status,
    this.url,
    this.file,
  });

  final String name;
  final PanoRoomStatus status;

  /// Eskiz — tarmoqdan (yuklangan) yoki fayldan (telefonda tikilgan).
  final String? url;
  final String? file;
}

Future<PanoRoomsSheetResult?> showPanoRoomsSheet(
  BuildContext context, {
  required List<PanoRoomItem> rooms,
  required bool canAdd,
}) => showModalBottomSheet<PanoRoomsSheetResult>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _PanoRoomsSheet(rooms: rooms, canAdd: canAdd),
);

class _PanoRoomsSheet extends StatelessWidget {
  const _PanoRoomsSheet({required this.rooms, required this.canAdd});

  final List<PanoRoomItem> rooms;
  final bool canAdd;

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF15191B) : Colors.white;
    final fg = isDark ? Colors.white : AppColors.textBlack;
    final sub = fg.withValues(alpha: 0.55);
    final bottom = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: fg.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            tr(l, 'bozor.pano.rooms.title'),
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: fg,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tr(l, 'bozor.pano.rooms.hint'),
            style: TextStyle(fontFamily: 'MTSText', fontSize: 13, color: sub),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: rooms.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) => _RoomTile(
                item: rooms[i],
                isDark: isDark,
                onTap: () =>
                    Navigator.of(ctx).pop(PanoRoomsSheetResult.open(i)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ListingCtaButton(
            label: tr(l, 'bozor.pano.rooms.add'),
            enabled: canAdd,
            onTap: () =>
                Navigator.of(context).pop(const PanoRoomsSheetResult.add()),
          ),
        ],
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({
    required this.item,
    required this.isDark,
    required this.onTap,
  });

  final PanoRoomItem item;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final fg = isDark ? Colors.white : AppColors.textBlack;
    final fill = isDark ? const Color(0xFF20262A) : const Color(0xFFF3F5F7);
    final (String status, Color color) = switch (item.status) {
      PanoRoomStatus.ready => (
        tr(l, 'bozor.pano.rooms.status_ready'),
        AppColors.splashGreen,
      ),
      PanoRoomStatus.local => (
        tr(l, 'bozor.pano.rooms.status_local'),
        const Color(0xFFE0A02A),
      ),
      PanoRoomStatus.failed => (
        tr(l, 'bozor.pano.rooms.status_failed'),
        const Color(0xFFE0492A),
      ),
      PanoRoomStatus.pending => (
        tr(l, 'bozor.pano.rooms.status_pending'),
        fg.withValues(alpha: 0.5),
      ),
    };
    final file = item.file;
    final hasFile = file != null && File(file).existsSync();

    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 64,
                  height: 40,
                  child: hasFile
                      ? Image.file(File(file), fit: BoxFit.cover)
                      : (item.url != null && item.url!.isNotEmpty)
                      ? Image.network(
                          item.url!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _ph(fg),
                        )
                      : _ph(fg),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status,
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 12,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: fg.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ph(Color fg) => ColoredBox(
    color: fg.withValues(alpha: 0.08),
    child: Icon(
      Icons.panorama_horizontal_rounded,
      color: fg.withValues(alpha: 0.4),
    ),
  );
}
