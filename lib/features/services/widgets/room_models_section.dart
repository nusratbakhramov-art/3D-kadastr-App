/// Ariza uchun olingan xona 3D modellari — ariza tafsiloti ekranida
/// ko'rsatiladigan bo'lim.
///
/// Manba: 3DGS serverdagi `GET /api/models?ariza_id=`. Ya'ni ilova qayta
/// o'rnatilgan, telefon almashtirilgan yoki ariza allaqachon yuborilgan
/// bo'lsa ham modellar joyida — hech qanday lokal holatga tayanmaydi.
///
/// Model yo'q bo'lsa bo'lim UMUMAN chizilmaydi: video olinmagan arizalarda
/// ekranga bo'sh sarlavha qo'shilmasligi kerak.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../widgets/app_toast.dart';
import '../../../theme/app_colors.dart';
import '../data/room_capture_store.dart';
import '../data/v2m_client.dart';
import '../models/ai_baholash_bundle.dart';
import '../screens/ai_video_status_screen.dart';
import '../screens/v2m_viewer_screen.dart';

class RoomModelsSection extends StatefulWidget {
  const RoomModelsSection({super.key, required this.arizaId});

  /// Asosiy backenddagi ariza id — 3DGS serverida shu bo'yicha qidiriladi.
  final int arizaId;

  @override
  State<RoomModelsSection> createState() => _RoomModelsSectionState();
}

class _RoomModelsSectionState extends State<RoomModelsSection> {
  final V2mClient _v2m = V2mClient();

  List<V2mModel> _models = const [];
  bool _loaded = false;
  String? _deleting;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _v2m.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final models = await _v2m.listByAriza(widget.arizaId.toString());
      if (!mounted) return;
      setState(() {
        _models = models;
        _loaded = true;
      });
    } on V2mException {
      // Server yetib bo'lmasa bo'lim shunchaki ko'rinmaydi — ariza
      // tafsilotining qolgan qismi buzilmasligi kerak.
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _open(V2mModel model) async {
    final room = _roomOf(model);
    final name = _nameOf(model);
    final url = _v2m.viewerUrlFor(model, title: name ?? room?.labelUz);
    // Tayyor bo'lmaganini bosgan bo'lsa — kuzatuv ekranini ochamiz.
    if (url == null) {
      if (room == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AiVideoStatusScreen(
            room: room,
            roomName: name,
            arizaId: widget.arizaId,
            modelId: model.id,
            onDeleted: (id) {
              if (mounted) {
                setState(() =>
                    _models = _models.where((m) => m.id != id).toList());
              }
            },
          ),
        ),
      );
      if (mounted) _load();
      return;
    }
    // Splat serverdagi Spark viewer'ida — qulflangan WebView.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => V2mViewerScreen(url: url, title: name ?? room?.labelUz),
      ),
    );
    // Viewer'dan qaytgach ham yangilaymiz: boshqa qurilmada yoki boshqa
    // ekranda o'chirilgan model bu yerda ko'rinib turmasligi kerak.
    if (mounted) _load();
  }

  /// Modelni serverdan o'chiradi. Ishlov berish ketayotgan bo'lsa server
  /// jarayonni to'xtatib navbatdagi ishga o'tadi.
  Future<void> _delete(V2mModel model) async {
    final l = Localizations.localeOf(context);
    final busy = !model.isDone && !model.isFailed;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          tr(l, busy
              ? 'services.ai.capture.cancel_title'
              : 'services.ai.capture.delete_title'),
        ),
        content: Text(
          tr(l, busy
              ? 'services.ai.capture.cancel_body'
              : 'services.ai.capture.delete_body'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr(l, 'common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.chatRedDeep,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr(l, 'common.delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _deleting = model.id);
    try {
      await _v2m.deleteModel(model.id);
      if (!mounted) return;
      setState(() {
        _deleting = null;
        _models = _models.where((m) => m.id != model.id).toList();
      });
      HapticFeedback.mediumImpact();
      AppToast.success(context, tr(l, 'services.ai.capture.deleted'));
    } on V2mException catch (e) {
      if (!mounted) return;
      setState(() => _deleting = null);
      AppToast.error(
        context,
        '${tr(l, 'services.ai.capture.delete_failed')}: ${e.message}',
      );
    }
  }

  RoomKind? _roomOf(V2mModel m) =>
      RoomKind.values.where((r) => r.wire == m.room).firstOrNull;

  /// "Boshqa" xonaga berilgan nom serverda alohida ustunda emas, ish
  /// yorlig'ida (`name`) turadi — [roomNameFromJobName] uni shundan oladi.
  /// Qolgan turlar tarjimasi bilan ko'rsatiladi.
  String? _nameOf(V2mModel m) => _roomOf(m) == RoomKind.other
      ? roomNameFromJobName(m.name)
      : null;

  /// Qatorda va kuzatuv ekranida ko'rinadigan nom.
  String _titleOf(V2mModel m, Locale l) =>
      _nameOf(m) ??
      _roomOf(m)?.label(l) ??
      tr(l, 'services.ai.capture.room_label');

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _models.isEmpty) return const SizedBox.shrink();
    final l = Localizations.localeOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        _Header(title: tr(l, 'services.ai.capture.rooms_title')),
        for (final model in _models)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ModelRow(
              model: model,
              title: _titleOf(model, l),
              locale: l,
              thumbUrl: model.files['thumb'] == null
                  ? null
                  : _v2m.fileUrl(model.files['thumb']!.path),
              onTap: () => _open(model),
              onDelete: () => _delete(model),
              deleting: _deleting == model.id,
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 15,
            decoration: BoxDecoration(
              color: AppColors.splashGreen,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: isDark ? Colors.white : AppColors.textBlack,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.model,
    required this.title,
    required this.locale,
    required this.thumbUrl,
    required this.onTap,
    required this.onDelete,
    required this.deleting,
  });

  final V2mModel model;
  final String title;
  final Locale locale;
  final String? thumbUrl;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool deleting;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    // Holatni `files` bo'yicha hal qilamiz: `status == 'done'` bo'lsa ham
    // eksport chiqmagan bo'lishi mumkin (SfM sifatsiz bo'lganda).
    final ready = model.scene != null;
    final (Color accent, String label) = model.isFailed
        ? (AppColors.chatRedDeep, tr(locale, 'services.ai.capture.status_failed'))
        : ready
            ? (
                AppColors.callGreenDeep,
                tr(locale, 'services.ai.capture.status_done'),
              )
            : (
                const Color(0xFFE0A12A),
                tr(locale, 'services.ai.capture.status_working'),
              );

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              _Thumb(url: thumbUrl, accent: accent, isDark: isDark),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      model.isFailed || ready
                          ? label
                          : '$label · ${model.progress}%',
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 13,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
              if (deleting)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(subColor),
                  ),
                )
              else
                InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: subColor,
                    ),
                  ),
                ),
              Icon(Icons.chevron_right_rounded, size: 18, color: subColor),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// Serverdagi `thumb.jpg`; yo'q bo'lsa yoki yuklanmasa — belgi.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, required this.accent, required this.isDark});

  final String? url;
  final Color accent;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.view_in_ar_rounded, size: 24, color: accent),
    );
    final src = url;
    if (src == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        src,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}
