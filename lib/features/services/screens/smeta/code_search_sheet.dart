/// Modal sheet — search ABC's СНиР catalog and pick a position code.
///
/// Optional book filter (chips at the top), debounced text search, tap
/// to select → quantity prompt → returns a fully-formed `SmetaItem`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../theme/app_colors.dart';
import '../../data/smeta_api_service.dart';
import '../../models/smeta_draft.dart';

/// Opens the sheet; returns the picked + quantified item, or null on cancel.
Future<SmetaItem?> showCodeSearchSheet(
  BuildContext context, {
  SmetaApiService? service,
}) async {
  return showModalBottomSheet<SmetaItem>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CodeSearchSheet(service: service ?? SmetaApiService()),
  );
}

class _CodeSearchSheet extends StatefulWidget {
  const _CodeSearchSheet({required this.service});
  final SmetaApiService service;

  @override
  State<_CodeSearchSheet> createState() => _CodeSearchSheetState();
}

class _CodeSearchSheetState extends State<_CodeSearchSheet> {
  final TextEditingController _query = TextEditingController();
  List<CatalogBook> _books = const [];
  String? _bookFile;            // selected book filter (null = all)
  List<CatalogCode> _results = const [];
  bool _loading = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadBooks();
    _loadCodes();           // initial "Latest codes" view
    _query.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.removeListener(_onQueryChanged);
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _loadCodes);
  }

  Future<void> _loadBooks() async {
    try {
      final b = await widget.service.books();
      if (!mounted) return;
      setState(() => _books = b);
    } catch (_) {
      // non-fatal — search still works without filter chips
    }
  }

  Future<void> _loadCodes() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.service.codes(
        q: _query.text.trim().isEmpty ? null : _query.text.trim(),
        book: _bookFile,
      );
      if (!mounted) return;
      setState(() {
        _results = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _pick(CatalogCode c) async {
    HapticFeedback.selectionClick();
    final qty = await _askQuantity(c);
    if (qty == null) return;
    if (!mounted) return;
    Navigator.of(context).pop(
      SmetaItem(code: c.code, name: c.name, unit: c.unit, quantity: qty),
    );
  }

  Future<double?> _askQuantity(CatalogCode c) async {
    final ctrl = TextEditingController();
    final qty = await showDialog<double>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(c.code),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.name, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Hajm (${c.unit})',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Bekor'),
            ),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(ctrl.text.replaceAll(',', '.'));
                if (v == null || v <= 0) return;
                Navigator.of(ctx).pop(v);
              },
              child: const Text("Qo'shish"),
            ),
          ],
        );
      },
    );
    ctrl.dispose();
    return qty;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF15191B) : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final mediaInsets = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(bottom: mediaInsets),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF2C3133)
                          : const Color(0xFFE3E5E8),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                "СНиР katalogidan tanlash",
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: textColor,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _query,
                decoration: InputDecoration(
                  hintText: 'Kod yoki nom bo\'yicha qidirish',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_books.isNotEmpty)
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _BookChip(
                      label: 'Hammasi',
                      selected: _bookFile == null,
                      onTap: () {
                        setState(() => _bookFile = null);
                        _loadCodes();
                      },
                    ),
                    for (final b in _books)
                      _BookChip(
                        label: b.label,
                        selected: _bookFile == b.file,
                        onTap: () {
                          setState(() => _bookFile = b.file);
                          _loadCodes();
                        },
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _ErrorView(message: _error!, onRetry: _loadCodes)
                      : _results.isEmpty
                          ? const _EmptyView()
                          : ListView.separated(
                              controller: scroll,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              itemCount: _results.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) => _CodeRow(
                                code: _results[i],
                                onTap: () => _pick(_results[i]),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeRow extends StatelessWidget {
  const _CodeRow({required this.code, required this.onTap});
  final CatalogCode code;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1F2426) : const Color(0xFFF7F8F9);
    final border =
        isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final mutedColor =
        isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    code.code,
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.splashGreen,
                    ),
                  ),
                  Text(
                    code.unit,
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontSize: 12,
                      color: mutedColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                code.name,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                  height: 1.3,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookChip extends StatelessWidget {
  const _BookChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final idleBg =
        isDark ? const Color(0xFF1F2426) : const Color(0xFFF1F2F4);
    final textColor =
        selected ? Colors.white : (isDark ? Colors.white70 : AppColors.textBlack);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? AppColors.splashGreen : idleBg,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final mutedColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF9BA1A6)
        : const Color(0xFF6C7278);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'Natijalar topilmadi',
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w500,
            fontSize: 14,
            color: mutedColor,
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 32, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(
              'Xatolik: $message',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Qayta urinish'),
            ),
          ],
        ),
      ),
    );
  }
}
