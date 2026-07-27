/// Yuborilgan arizani backend forma sxemasi bo'yicha to'liq ko'rsatadi —
/// barcha to'ldirilgan maydonlar, bo'limga ajratilgan (label → qiymat).
///
/// `GET /forms/{key}` sxemasini oladi va [payload] (ariza xom javobi) ichidagi
/// qiymatlarni `field.mapsTo` bo'yicha o'qib, variant qiymatlarini o'qiladigan
/// label'ga aylantiradi. Shu sbabli ariza detali ham dinamik — yangi maydon
/// qo'shilsa, reliz shart emas.
library;

import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/color_tokens.dart';
import '../api_forms_service.dart';
import '../models/dynamic_form_schema.dart';
import '../models/dynamic_form_payload.dart';

class SchemaAnswersView extends StatefulWidget {
  const SchemaAnswersView({
    super.key,
    required this.formKey,
    required this.payload,
    this.fallback,
  });

  final String formKey;
  final Map<String, dynamic> payload;

  /// Sxema yuklanmasa ko'rsatiladigan zaxira ko'rinish (eski tekis ro'yxat).
  final Widget? fallback;

  @override
  State<SchemaAnswersView> createState() => _SchemaAnswersViewState();
}

class _SchemaAnswersViewState extends State<SchemaAnswersView> {
  late Future<FormSchema> _future;

  @override
  void initState() {
    super.initState();
    _future = FormsApiService().getForm(widget.formKey);
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    return FutureBuilder<FormSchema>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snap.hasData) {
          return widget.fallback ?? const SizedBox.shrink();
        }
        final schema = snap.data!;
        final sections = <Widget>[];
        for (final section in schema.sections) {
          final rows = <(String, String)>[];
          for (final f in section.fields) {
            final value = _format(f, getByPath(widget.payload, f.mapsTo), l);
            if (value != null) rows.add((trMap(f.label, l), value));
          }
          if (rows.isEmpty) continue;
          sections.add(_SectionCard(title: trMap(section.title, l), rows: rows));
        }
        if (sections.isEmpty) {
          return widget.fallback ?? const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < sections.length; i++) ...[
              sections[i],
              if (i != sections.length - 1) const SizedBox(height: 14),
            ],
          ],
        );
      },
    );
  }

  /// Maydon qiymatini o'qiladigan matnga aylantiradi. Bo'sh/ko'rsatishga arzimas
  /// bo'lsa null (qator chiqmaydi).
  String? _format(FormFieldDef f, dynamic value, Locale l) {
    switch (f.type) {
      case FormFieldType.toggle:
        // Faqat yoqilgan (true) togglelarni ko'rsatamiz — shovqinni kamaytirish.
        return value == true ? _yes(l) : null;
      case FormFieldType.singleChoice:
        if (value == null) return null;
        return _optionLabel(f, value.toString(), l) ?? value.toString();
      case FormFieldType.multiChoice:
        if (value is! List || value.isEmpty) return null;
        return value
            .map((v) => _optionLabel(f, v.toString(), l) ?? v.toString())
            .join(', ');
      case FormFieldType.rooms:
        if (value is! List || value.isEmpty) return null;
        return value.whereType<Map>().map((r) {
          final name = (r['name'] ?? '').toString();
          final count = r['count'];
          final area = r['area_sqm'];
          final parts = <String>[
            if (name.isNotEmpty) name,
            if (count != null) '×$count',
            if (area != null) '$area m²',
          ];
          return parts.join(' ');
        }).where((s) => s.trim().isNotEmpty).join(', ');
      case FormFieldType.number:
      case FormFieldType.integer:
        if (value == null) return null;
        final s = value.toString();
        return f.unit != null ? '$s ${f.unit}' : s;
      case FormFieldType.note:
        return null;
      case FormFieldType.text:
      case FormFieldType.textarea:
      case FormFieldType.date:
      case FormFieldType.unknown:
        if (value == null) return null;
        final s = value.toString().trim();
        return s.isEmpty ? null : s;
    }
  }

  String? _optionLabel(FormFieldDef f, String value, Locale l) {
    for (final o in f.options) {
      if (o.value == value) return trMap(o.label, l);
    }
    return null;
  }

  String _yes(Locale l) => tr(l, 'services.widget.schema.yes');
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.rows});
  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: ColorTokens.primaryText(context),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
          decoration: BoxDecoration(
            color: ColorTokens.cardBg(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ColorTokens.outline(context), width: 0.6),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                _Row(label: rows[i].$1, value: rows[i].$2),
                if (i != rows.length - 1)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: ColorTokens.divider(context),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w400,
                fontSize: 14,
                height: 1.3,
                color: ColorTokens.secondaryText(context),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w500,
                fontSize: 14,
                height: 1.3,
                color: ColorTokens.primaryText(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
