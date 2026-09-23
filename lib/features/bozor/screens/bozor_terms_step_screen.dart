/// "Bozor AI" sehrgarining oxirgi qadami — «E'lon shartlari».
///
/// Ekranda BACKENDDAN kelgan «E'lon joylashtirish shartlari» matni
/// (`GET /legal/listing-terms?lang=`, adminka «Shartlar» sahifasida
/// tahrirlanadi) va uning ENG OSTIDA rozilik katakchasi. Katakcha
/// belgilangandagina «Joylashtirish» yonadi; rozilik bilan birga hujjat
/// versiyasi (`terms_version`) serverga ketadi.
///
/// Tariflar (Standart / Top) BU YERDA YO'Q (2026-09-13, mahsulot qarori):
/// «Top» to'lov oqimi hali yo'q, ikkita karta foydalanuvchini chalg'itardi.
/// `TermsDraft.tier` `standard` bo'lib qoladi — backend shuni kutadi.
///
/// Pastdagi qator dizayndagidek: chapda "Oldindan ko'rish", o'ngda
/// "Joylashtirish" — bu yerda "Ortga" YO'Q (dizaynda ham yo'q). Bir qadam
/// orqaga qaytish iOS'dagi chetdan surish imkoniyati bilan qoladi; yuqoridagi
/// tugma esa boshqa qadamlardagidek butun oqimni yopadi.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:http/http.dart' as http;

import '../../../core/api_config.dart';
import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/app_toast.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../../services/widgets/service_app_bar.dart';
import '../../services/widgets/step_progress_bar.dart';
import '../bozor_routes.dart';
import '../data/bozor_api.dart';
import '../data/bozor_draft_store.dart';
import '../data/bozor_submit.dart';
import '../data/pano_submit_gate.dart';
import '../models/bozor_draft.dart';
import '../models/bozor_validation.dart';
import '../widgets/draft_preview_sheet.dart';
import 'bozor_success_screen.dart';

/// Backenddan kelgan «E'lon shartlari» hujjati.
@immutable
class ListingTermsDoc {
  const ListingTermsDoc({
    required this.title,
    required this.html,
    required this.version,
  });

  final String title;
  final String html;
  final String version;
}

/// Hujjatni oladi — test uchun almashtiriladi.
typedef ListingTermsLoader = Future<ListingTermsDoc> Function(String lang);

/// `GET /legal/listing-terms?lang=` — ommaviy, tokensiz.
Future<ListingTermsDoc> fetchListingTerms(String lang) async {
  final res = await http
      .get(Uri.parse('${ApiConfig.baseUrl}/legal/listing-terms?lang=$lang'))
      .timeout(const Duration(seconds: 20));
  if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
  final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  return ListingTermsDoc(
    title: (body['title'] ?? '').toString(),
    html: (body['content'] ?? '').toString(),
    version: (body['version'] ?? '').toString(),
  );
}

class BozorTermsStepScreen extends StatefulWidget {
  const BozorTermsStepScreen({
    super.key,
    required this.draft,
    this.submitter,
    this.termsLoader,
  });

  final BozorDraft draft;

  /// Faqat testlar uchun — tarmoqqa chiqmasdan yuborishni almashtirish.
  final BozorSubmitter? submitter;

  /// Faqat testlar uchun — hujjatni tarmoqsiz berish.
  final ListingTermsLoader? termsLoader;

  @override
  State<BozorTermsStepScreen> createState() => _BozorTermsStepScreenState();
}

class _BozorTermsStepScreenState extends State<BozorTermsStepScreen> {
  TermsDraft get _t => widget.draft.terms;

  late final BozorSubmitter _submitter = widget.submitter ?? BozorSubmitter();
  bool _sending = false;

  /// Yuklash jarayoni — tugma matnida ko'rinadi («Yuborilmoqda… 3/12»).
  /// 12 ta fotoni yuborish daqiqalar oladi; progressiz foydalanuvchi ilova
  /// qotib qoldi deb o'ylab, tugmani qayta bosadi.
  int _done = 0;
  int _total = 0;

  ListingTermsDoc? _doc;
  bool _docLoading = true;
  bool _docFailed = false;
  bool _docStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_docStarted) return;
    _docStarted = true;
    _loadDoc();
  }

  @override
  void dispose() {
    // Testdan berilgan bo'lsa uni yopish testning ishi.
    if (widget.submitter == null) _submitter.dispose();
    super.dispose();
  }

  Future<void> _loadDoc() async {
    final lang = Localizations.localeOf(context).languageCode;
    setState(() {
      _docLoading = true;
      _docFailed = false;
    });
    try {
      final doc = await (widget.termsLoader ?? fetchListingTerms)(lang);
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _docLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _docLoading = false;
        _docFailed = true;
      });
    }
  }

  void _setAccepted(bool v) {
    setState(() {
      _t.accepted = v;
      _t.acceptedVersion = v ? _doc?.version : null;
    });
  }

  /// Fayllarni yuklaydi, keyin e'lonni yaratadi.
  ///
  /// Xatolikda qoralama JOYIDA qoladi va tugma yana yonadi — foydalanuvchi
  /// hamma narsani qaytadan kiritmasligi kerak.
  /// Yuborishdan OLDINGI oxirgi darvoza.
  ///
  /// Qadamlarning har biri o'z "Далее" sini bloklaydi, lekin qoralamani
  /// davom ettirish sehrgarni SAQLANGAN qadamdan ochadi: `current_step` ==
  /// `terms` bo'lsa foydalanuvchi to'g'ridan bu ekranga tushadi va 1–6
  /// qadamlarning tekshiruvi umuman ishlamaydi. Shunda server tushunarsiz
  /// 400 berardi (`'bathroom_type' toʻldirilishi shart`) — maydon 3-qadamda,
  /// u esa ochilmagan ham.
  ///
  /// `true` — yuborish mumkin.
  bool _checkComplete(Locale l) {
    final blockers = draftBlockers(widget.draft);
    if (blockers.isEmpty) return true;
    final first = blockers.first;
    final step = tr(l, first.stepTitleKey);
    // Maydon nomlari bo'lsa aytamiz — "Parametrlar qadami to'ldirilmagan"
    // dan ko'ra "Parametrlar: Sanuzel turi" ancha foydali.
    final fields = first.fieldLabelKeys.take(3).map((k) => tr(l, k)).join(', ');
    final more = first.fieldLabelKeys.length > 3
        ? ' +${first.fieldLabelKeys.length - 3}'
        : '';
    final n = widget.draft.stepNumber(first.step);
    AppToast.error(
      context,
      fields.isEmpty
          ? '$n. $step — ${tr(l, 'bozor.common.fill_required')}'
          : '$n. $step: $fields$more',
    );
    return false;
  }

  Future<void> _submit() async {
    if (_sending) return;
    final locale = Localizations.localeOf(context);
    if (!_checkComplete(locale)) return;
    // ⚠️ Panorama to'sig'i ALOHIDA: `_checkComplete` majburiy MAYDONLARNI
    // tekshiradi, bu esa fonda tikilayotgan ishni. Ikkalasini birlashtirsak
    // xabar aniqligini yo'qotardi.
    final blocker = panoSubmitBlocker(widget.draft.description);
    if (blocker != null) {
      AppToast.error(context, tr(locale, blocker));
      return;
    }
    setState(() {
      _sending = true;
      _done = 0;
      _total = 0;
    });
    final l = Localizations.localeOf(context);
    try {
      final created = await _submitter.submit(
        widget.draft,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _done = done;
            _total = total;
          });
        },
      );
      if (!mounted) return;
      // `id` kutilmagan shaklda kelsa `null` qoladi — success ekrani bunda
      // "ko'rish" tugmasini ko'rsatmaydi (mavjud bo'lmagan e'lonni ochmaydi).
      final rawId = created['id'];
      final listingId = rawId is int ? rawId : int.tryParse('$rawId');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          settings: bozorRoute('success'),
          builder: (_) => BozorSuccessScreen(listingId: listingId),
        ),
        // Sehrgarning hamma qadamini olib tashlaymiz: muvaffaqiyat ekranidan
        // formaga qaytib bo'lmaydi.
        (route) {
          final name = route.settings.name;
          return name == null || !name.startsWith(bozorRoutePrefix);
        },
      );
    } on BozorApiException catch (e) {
      // Uzilishdan oldin yuklangan fayl kalitlari qoralamaga yozilgan —
      // ularni SERVERGA ham saqlaymiz, aks holda ilova qayta ishga
      // tushirilsa qayta urinish hamma faylni boshidan yuklardi.
      saveBozorDraftInBackground(widget.draft, WizardStep.terms);
      if (mounted) AppToast.error(context, e.message);
    } catch (e) {
      saveBozorDraftInBackground(widget.draft, WizardStep.terms);
      if (mounted) AppToast.error(context, tr(l, 'bozor.terms.submit_failed'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// «Yuborilmoqda…» yoki fayl bo'lsa «Yuborilmoqda… 3/12».
  ///
  /// Umumiy son 1 dan katta bo'lgandagina raqam ko'rsatiladi: rasmsiz e'londa
  /// «1/1» faqat shovqin bo'lardi.
  String _sendingLabel(Locale l) {
    final base = tr(l, 'bozor.terms.submitting');
    return _total > 1 ? '$base $_done/$_total' : base;
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final draft = widget.draft;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final maxContent = c.maxWidth.clamp(0.0, 640.0);
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContent),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: ServiceAppBar(
                        title: tr(l, 'bozor.terms.title'),
                        subtitle:
                            '${draft.stepNumber(WizardStep.terms)}'
                            '/${draft.stepCount}',
                        onBack: bozorStepBack(
                          context,
                          isFirstStep: draft.stepIndex(WizardStep.terms) == 0,
                        ),
                        onClose: bozorStepClose(
                          context,
                          isFirstStep: draft.stepIndex(WizardStep.terms) == 0,
                        ),
                        closeTooltip: tr(l, 'bozor.exit.title'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: StepProgressBar(
                        count: draft.stepCount,
                        activeIndex: draft.stepIndex(WizardStep.terms),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        children: [
                          _termsBody(l, isDark),
                          const SizedBox(height: 16),
                          // Katakcha HUJJATNING OSTIDA — o'qib bo'lgach.
                          _ConsentCheckbox(
                            value: _t.accepted,
                            enabled: _doc != null,
                            text:
                                '${tr(l, 'bozor.terms.consent_lead')} '
                                '${tr(l, 'bozor.terms.consent_link')}',
                            onChanged: _setAccepted,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: _PreviewButton(
                              label: tr(l, 'bozor.terms.preview'),
                              onTap: () =>
                                  showDraftPreviewSheet(context, draft),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _t.accepted
                                  ? null
                                  : () => AppToast.error(
                                      context,
                                      tr(l, 'bozor.terms.accept_first'),
                                    ),
                              child: ListingCtaButton(
                                label: _sending
                                    ? _sendingLabel(l)
                                    : tr(l, 'bozor.terms.submit'),
                                enabled: _t.accepted && !_sending,
                                onTap: _submit,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

extension on _BozorTermsStepScreenState {
  Widget _termsBody(Locale l, bool isDark) {
    final fg = isDark ? Colors.white : AppColors.textBlack;
    final fill = isDark ? const Color(0xFF15191B) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    Widget inner;
    if (_docLoading) {
      inner = const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(color: AppColors.splashGreen),
        ),
      );
    } else if (_docFailed || _doc == null) {
      inner = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr(l, 'bozor.terms.doc_failed'),
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'MTSText', fontSize: 14, color: fg),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _loadDoc,
            child: Text(tr(l, 'bozor.pano.flow.retry')),
          ),
        ],
      );
    } else {
      final d = _doc!;
      inner = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            d.title,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: fg,
            ),
          ),
          const SizedBox(height: 12),
          HtmlWidget(
            d.html,
            textStyle: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 14,
              height: 1.45,
              color: fg.withValues(alpha: 0.9),
            ),
          ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: inner,
    );
  }
}

/// Rozilik katakchasi — hujjat ostida. Hujjat yuklanmaguncha o'chiq.
class _ConsentCheckbox extends StatelessWidget {
  const _ConsentCheckbox({
    required this.value,
    required this.enabled,
    required this.text,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final String text;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : AppColors.textBlack;
    final fill = isDark ? const Color(0xFF20262A) : const Color(0xFFF3F5F7);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? () => onChanged(!value) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
            child: Row(
              children: [
                Checkbox(
                  value: value,
                  onChanged: enabled ? (v) => onChanged(v ?? false) : null,
                  activeColor: AppColors.splashGreen,
                  checkColor: Colors.black,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontFamily: 'MTSText',
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ikkilamchi tugma — [ListingCtaButton] bilan bir o'lchamda.
class _PreviewButton extends StatelessWidget {
  const _PreviewButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final fg = isDark ? Colors.white : AppColors.textBlack;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
