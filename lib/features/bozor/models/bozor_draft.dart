/// "Bozor AI" — e'lon joylash sehrgarining (wizard) modeli.
///
/// Sehrgar 1-qadamda uchta tanlov oladi va ULAR butun qolgan oqimni belgilaydi:
/// `Тип объявления → Вид недвижимости → Тип недвижимости`. Oxirgisi nafaqat
/// 2–5-qadamlarning maydonlarini, balki QADAMLAR SONINI ham o'zgartiradi
/// ([stepCount] ga qarang) — shu sababli qadamlar ro'yxati hech qayerda
/// qat'iy 7 deb yozilmasligi kerak.
library;

import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
import 'parcel_boundary.dart';
import 'tour_link.dart';

/// E'lon turi. Dizaynda faqat [rent] oqimi chizilgan; [sale] model uchun bor,
/// uning 4-qadami (narx) hali dizaynda yo'q.
enum DealType { rent, sale }

/// Mulk toifasi — [PropertyType] ro'yxatini filtrlaydi.
enum PropertyKind { residential, nonResidential }

/// Mulk turi — sehrgarning butun shakli shunga bog'liq.
enum PropertyType {
  apartment,
  /// «Квартира в новостройке» — dizaynda `Квартира` dan keyin turadi.
  /// Parametrlari hozircha oddiy kvartiraniki (maxsus maydonlar dizaynda
  /// ochilmagan), lekin AYRIM tur: sotuvda «Прописано» qatori faqat shu
  /// ikkisida so'raladi.
  newBuildingApartment,
  house,
  land,
  commercial,
  garage,
  otherNonResidential,
}

extension DealTypeX on DealType {
  String label(Locale l) => switch (this) {
    DealType.rent => tr(l, 'bozor.deal.rent'),
    DealType.sale => tr(l, 'bozor.deal.sale'),
  };
}

extension PropertyKindX on PropertyKind {
  String label(Locale l) => switch (this) {
    PropertyKind.residential => tr(l, 'bozor.kind.residential'),
    PropertyKind.nonResidential => tr(l, 'bozor.kind.non_residential'),
  };

  /// Shu toifada tanlash mumkin bo'lgan turlar — 1-qadamdagi uchinchi
  /// tanlovning ro'yxati.
  List<PropertyType> get types => switch (this) {
    PropertyKind.residential => const [
      PropertyType.apartment,
      PropertyType.newBuildingApartment,
      PropertyType.house,
      PropertyType.land,
    ],
    PropertyKind.nonResidential => const [
      PropertyType.commercial,
      PropertyType.garage,
      PropertyType.otherNonResidential,
    ],
  };
}

extension PropertyTypeX on PropertyType {
  String label(Locale l) => switch (this) {
    PropertyType.apartment => tr(l, 'bozor.type.apartment'),
    PropertyType.newBuildingApartment => tr(l, 'bozor.type.new_building'),
    PropertyType.house => tr(l, 'bozor.type.house'),
    PropertyType.land => tr(l, 'bozor.type.land'),
    PropertyType.commercial => tr(l, 'bozor.type.commercial'),
    PropertyType.garage => tr(l, 'bozor.type.garage'),
    PropertyType.otherNonResidential => tr(l, 'bozor.type.other_non_res'),
  };

  /// Qaysi toifaga tegishli — toifa o'zgarganda turni tozalash uchun.
  PropertyKind get kind => switch (this) {
    PropertyType.apartment ||
    PropertyType.newBuildingApartment ||
    PropertyType.house ||
    PropertyType.land => PropertyKind.residential,
    PropertyType.commercial ||
    PropertyType.garage ||
    PropertyType.otherNonResidential => PropertyKind.nonResidential,
  };

  /// "Параметры" qadami shu turda bormi.
  ///
  /// "Boshqa noturar joy" da YO'Q — dizaynda o'sha variantda bu ekran
  /// umuman chizilmagan.
  bool get hasParamsStep => this != PropertyType.otherNonResidential;

  /// Sotuvda «Прописано» (4/8) qatori so'raladimi.
  ///
  /// Faqat kvartira turlarida: dizaynda Дом va Гараж freymlarida bu qator
  /// umuman yo'q. Backend ham shunday tekshiradi
  /// (`listing_options.TYPES_WITH_REGISTERED_COUNT`) — ikkisi ajralib
  /// ketmasin.
  bool get asksRegisteredCount =>
      this == PropertyType.apartment ||
      this == PropertyType.newBuildingApartment;
}

/// Sehrgar qadamlari.
///
/// ⚠️ TARTIB MUHIM: [wizardStepsFor] ro'yxatni shu tartibda quradi va
/// `bozor_resume.dart` dagi `_fallbackStep` "oldingi qadam" ni AYNAN shu
/// enum tartibi bo'yicha izlaydi.
enum WizardStep {
  type,
  address,
  params,
  /// «Сделка» — FAQAT sotuv oqimida (4/8).
  deal,
  price,
  description,
  contacts,
  terms,
}

/// Qadamlar ketma-ketligi — (e'lon turi × mulk turi) juftligiga bog'liq.
///
/// Ilgari u faqat [PropertyType] ga bog'liq edi, chunki dizaynda faqat ijara
/// oqimi bor edi. Sotuv freymlari kelgach ikkinchi o'lchov paydo bo'ldi:
/// «Сделка» qadami FAQAT sotuvda chiziladi. To'rt kombinatsiya:
///
/// | E'lon turi | Mulk turi | Qadamlar |
/// |---|---|---|
/// | sotuv | params bor 6 tur | **8** |
/// | sotuv | Boshqa noturar joy | **7** |
/// | ijara | params bor 6 tur | 7 (o'zgarmagan) |
/// | ijara | Boshqa noturar joy | 6 (o'zgarmagan) |
///
/// [deal] `null` bo'lsa (1-qadam hali to'ldirilmagan) «Сделка» qo'shilmaydi —
/// ijara eng keng tarqalgan holat va progress chizig'i sakramaydi.
/// Raqamlar hech qayerda qo'lda yozilmasin: ekranlar
/// [BozorDraft.stepNumber] dan so'raydi.
List<WizardStep> wizardStepsFor(DealType? deal, PropertyType? type) {
  final t = type ?? PropertyType.apartment;
  return [
    WizardStep.type,
    WizardStep.address,
    if (t.hasParamsStep) WizardStep.params,
    if (deal == DealType.sale) WizardStep.deal,
    WizardStep.price,
    WizardStep.description,
    WizardStep.contacts,
    WizardStep.terms,
  ];
}

/// 2-qadamdagi qatorlar — kanonik (yuqoridan pastga) tartibda.
///
/// Qaysilari chiziladi — [PropertyTypeAddressX.addressRows] hal qiladi.
enum AddressRow {
  region,
  district,
  address,
  landmark,
  apartmentNumber,
  entrance,
  houseNumber,
  totalFloors,
  floor,
}

extension PropertyTypeAddressX on PropertyType {
  /// 2-qadamda ko'rinadigan qatorlar, chizish tartibida.
  ///
  /// Kvartira va uy bir-birining ichida EMAS: `Дом` faqat uyda, `Этаж` va
  /// `Номер квартиры` faqat kvartirada bo'ladi; umumiysi `Этажей в доме`.
  /// Qolgan to'rt turda qo'shimcha qator umuman yo'q.
  List<AddressRow> get addressRows {
    const common = [
      AddressRow.region,
      AddressRow.district,
      AddressRow.address,
      AddressRow.landmark,
    ];
    return switch (this) {
      PropertyType.apartment || PropertyType.newBuildingApartment => const [
        ...common,
        AddressRow.apartmentNumber,
        AddressRow.entrance,
        AddressRow.totalFloors,
        AddressRow.floor,
      ],
      PropertyType.house => const [
        ...common,
        AddressRow.houseNumber,
        AddressRow.totalFloors,
      ],
      PropertyType.land ||
      PropertyType.commercial ||
      PropertyType.garage ||
      PropertyType.otherNonResidential => common,
    };
  }

  /// Tavsif maydonining sarlavhasi.
  ///
  /// DIQQAT: dizaynda oltita frame'dan TO'RTTASIDA copy-paste xatosi bor —
  /// uy, tijorat, garaj va boshqa noturar joyda ham «Об участке» yozilgan.
  /// Garaj e'lonida "uchastka haqida" deb so'rash aniq xato, shuning uchun
  /// bu yerda turga mos sarlavha qo'yildi. Dizaynga so'zma-so'z qaytarish
  /// kerak bo'lsa — faqat shu switch o'zgartiriladi.
  String descriptionLabel(Locale l) => switch (this) {
    PropertyType.apartment ||
    PropertyType.newBuildingApartment => tr(l, 'bozor.desc.about.apartment'),
    PropertyType.house => tr(l, 'bozor.desc.about.house'),
    PropertyType.land => tr(l, 'bozor.desc.about.land'),
    PropertyType.commercial => tr(l, 'bozor.desc.about.commercial'),
    PropertyType.garage => tr(l, 'bozor.desc.about.garage'),
    PropertyType.otherNonResidential => tr(l, 'bozor.desc.about.other'),
  };

  /// Narx maydonining sarlavhasi.
  ///
  /// Ijarada u har doim «Ijara haqi», sotuvda esa MULK TURIGA bog'liq
  /// («Стоимость квартиры / дома / участка / гаража / помещения»). Shu sabab
  /// yorliq qat'iy yozilmaydi — ekran shu funksiyadan so'raydi.
  ///
  /// [deal] `null` (1-qadam to'ldirilmagan) bo'lsa ijara yorlig'i: sotuv
  /// bayroq ostida va kamroq uchraydi.
  String priceLabel(Locale l, DealType? deal) {
    if (deal != DealType.sale) return tr(l, 'bozor.price.rent');
    return switch (this) {
      PropertyType.apartment ||
      PropertyType.newBuildingApartment => tr(l, 'bozor.price.sale.apartment'),
      PropertyType.house => tr(l, 'bozor.price.sale.house'),
      PropertyType.land => tr(l, 'bozor.price.sale.land'),
      PropertyType.commercial => tr(l, 'bozor.price.sale.commercial'),
      PropertyType.garage => tr(l, 'bozor.price.sale.garage'),
      PropertyType.otherNonResidential => tr(l, 'bozor.price.sale.other'),
    };
  }

  /// Manzil qatorining sarlavhasi — faqat kvartirada boshqacha.
  String addressRowLabel(Locale l) =>
      this == PropertyType.apartment ||
          this == PropertyType.newBuildingApartment
      ? tr(l, 'bozor.address.field.address_apartment')
      : tr(l, 'bozor.address.field.address');
}

/// 2-qadamning ma'lumotlari.
class AddressDraft {
  /// Backend `market_regions.id` — BUTUN SON (FK). Ilgari stub matn id
  /// ishlatardi (`'tashkent_city'`).
  int? regionId;
  String? regionName;
  int? districtId;
  String? districtName;

  String address = '';
  String landmark = '';
  String apartmentNumber = '';
  String entrance = '';
  String houseNumber = '';
  String totalFloors = '';
  String floor = '';

  /// Xaritadan belgilangan nuqta.
  double? lat;
  double? lng;

  /// Geoportaldan tanlangan uchastkaning kadastr raqami.
  ///
  /// Bo'sh bo'lishi MUMKIN va bu normal: NGIS hamma obyektni qamramaydi
  /// (yangi qurilish, xatlovdan o'tmagan joy), shuning uchun manzilni
  /// xaritada qo'lda belgilash yo'li saqlanib qolgan.
  String cadastreNumber = '';

  /// O'sha uchastkaning chegarasi — e'lon sahifasidagi xaritada chiziladi.
  ParcelBoundary? boundary;

  /// Uchastka bilan bog'liq hammasini birdan tozalaydi.
  ///
  /// Bittasini qoldirib ketish OSON xato bo'lardi: masalan foydalanuvchi
  /// metkani qo'lda ko'chirsa, eski uchastkaning chegarasi yangi nuqta
  /// ustida turib qolardi.
  void clearParcel() {
    cadastreNumber = '';
    boundary = null;
  }

  /// Viloyat o'zgarsa tuman mos kelmay qoladi — tozalanadi.
  void setRegion(int id, String name) {
    if (regionId == id) return;
    regionId = id;
    regionName = name;
    districtId = null;
    districtName = null;
  }
}

/// 4-qadamning ma'lumotlari.
class PriceDraft {
  /// Asosiy narx (ijara haqi). Matn sifatida saqlanadi — maydon matnli.
  String amount = '';

  /// Yopiq qatorda ko'rinadigan birlik tokeni: `UZS/oy`, `USD/oy`…
  /// Dizaynda valyuta va davr BITTA matn — ular ajralmaydi.
  String unit = 'UZS/oy';

  /// "Торг уместен". Dizaynda oltita frame'da ham YOQILGAN holda chizilgan.
  bool negotiable = true;

  /// Sutkalik narx — faqat kvartira va uyda, va faqat IJARADA.
  String dailyAmount = '';
  String dailyUnit = 'UZS';

  /// «Ипотека» (5/8) — faqat sotuvda. Dizaynda toggle YOQILGAN holda
  /// chizilgan, lekin sukut `false`: ipoteka bor-yo'qligi e'lonning moddiy
  /// da'vosi, uni foydalanuvchi ongli yoqishi kerak ("Торг уместен" boshqa
  /// masala — u sozlama, da'vo emas).
  bool mortgage = false;
}

/// 4/8 «Сделка» — FAQAT sotuv oqimida to'ldiriladi.
///
/// ⚠️ Nomi ATAYLAB `TransactionDraft`, `DealDraft` emas: [BozorDraft.deal]
/// allaqachon [DealType] uchun band va `deal` ni ikki ma'noda ishlatish
/// kodni o'qib bo'lmaydigan qilardi.
///
/// Qiymatlar — `listing.option.*` KODLARI (`free_sale`, `under_3`, `6_plus`),
/// yorliq emas: til almashganda tanlov o'zgarib ketmasin.
class TransactionDraft {
  /// «Тип продажи» — ixtiyoriy.
  String? saleType;

  /// «Лет в собственности» — ixtiyoriy.
  String? ownershipYears;

  /// «Собственники» — dizaynda 4/8 dagi YAGONA majburiy maydon.
  String? ownersCount;

  /// «Прописано» — ixtiyoriy va faqat kvartira turlarida
  /// ([PropertyTypeX.asksRegisteredCount]).
  String? registeredCount;

  /// Mulk turi o'zgarganda «Прописано» so'ralmaydigan turga o'tilsa qiymat
  /// osilib qolmasin — backend uni 400 bilan rad etadi.
  void clearRegisteredIfUnsupported(PropertyType? type) {
    if (type == null || !type.asksRegisteredCount) registeredCount = null;
  }
}
/// E'londa allaqachon turgan fayl — tahrirlashda qaytarib yuborish uchun.
class ExistingMedia {
  const ExistingMedia({
    required this.key,
    required this.role,
    required this.sortOrder,
    required this.isCover,
    this.title,
  });

  final String key;
  final String role;
  final int sortOrder;
  final bool isCover;

  /// Xona nomi (panorama) — `PATCH` da qaytarib yuboriladi, yo'qolmasin.
  final String? title;
}

/// 5-qadamning ma'lumotlari.
///
/// Fayllar LOKAL yo'llar sifatida saqlanadi — yuklash endpoint'i hali yo'q.
/// Planirovka va 360 ham ro'yxat: dizaynda nechta fayl ruxsat etilgani
/// ko'rsatilmagan, ro'yxat bo'lsa chegarani keyin validatsiya hal qiladi.
/// Serverda tikilayotgan (yoki yiqilgan) panorama.
///
/// `bozor_pano_jobs` jadvalidagi ishning mobil tarafdagi soyasi. Qoralamaga
/// yoziladi, ya'ni ilova yopilib ochilsa ham kuzatuv davom etadi.
@immutable
class PendingPano {
  const PendingPano({
    required this.jobId,
    required this.startedAt,
    this.error,
  });

  final int jobId;

  /// Kadrlar yuborilgan payt.
  ///
  /// ⚠️ KUZATUV MUDDATI shundan hisoblanadi. Busiz `queued` da qotib qolgan
  /// ish (masalan worker ko'tarilmagan bo'lsa) abadiy «tayyorlanmoqda»
  /// bo'lib turaverardi va e'lon hech qachon yuborilmasdi.
  final DateTime startedAt;

  /// `null` — hali ishlayapti. Bo'sh bo'lmasa — server qaytargan xato.
  final String? error;

  bool get failed => error != null && error!.isNotEmpty;

  /// [panoramas] ro'yxatidagi vaqtinchalik havola.
  ///
  /// ⚠️ S3 kaliti bilan ADASHMASLIGI shart: kalitlar `listings/media/...`
  /// bilan boshlanadi, bu esa `job:` bilan.
  static String refOf(int jobId) => 'job:$jobId';

  static int? jobIdOf(String ref) =>
      ref.startsWith('job:') ? int.tryParse(ref.substring(4)) : null;

  PendingPano withError(String? e) =>
      PendingPano(jobId: jobId, startedAt: startedAt, error: e);

  Map<String, Object?> toJson() => {
    'job_id': jobId,
    'started_at': startedAt.toUtc().toIso8601String(),
    if (error != null) 'error': error,
  };

  factory PendingPano.fromJson(Map<String, Object?> j) => PendingPano(
    jobId: (j['job_id'] as num?)?.toInt() ?? 0,
    // Eski qoralamada maydon yo'q — o'shanda "hozir" deb olamiz, ya'ni
    // muddat qaytadan boshlanadi. Abadiy kutishdan ko'ra shu yaxshi.
    startedAt:
        DateTime.tryParse('${j['started_at'] ?? ''}')?.toLocal() ??
        DateTime.now(),
    error: j['error']?.toString(),
  );
}

/// Telefonda saqlangan, hali YUKLANMAGAN 360° tushirish.
///
/// Capture tugashi bilanoq qoralamaga yoziladi (tikish va yuklash hali
/// oldinda) — ilova yopilsa, tikish yiqilsa yoki foydalanuvchi xato ekranidan
/// chiqsa 30 nishonni aylanib chiqqan mehnat yo'qolmaydi: qatorda turadi va
/// bosilganda YIQILGAN bosqichdan davom etadi (`PanoCaptureFlow(resumeDir:)`).
///
/// Kadrlar `Application Support/pano/<uuid>/` da (`PanoCapture.swift`) —
/// `tmp/` emas, iOS uni tozalab yuborishi mumkin.
@immutable
class LocalPano {
  const LocalPano({required this.dir, required this.stage, this.error});

  /// Kadrlar (+ tikilgan bo'lsa `pano.jpg`, `preview.jpg`) katalogi.
  final String dir;
  final LocalPanoStage stage;

  /// Oxirgi urinish xatosi (`stage == failed` da).
  final String? error;

  bool get failed => stage == LocalPanoStage.failed;
  String get previewPath => '$dir/preview.jpg';
  String get panoPath => '$dir/pano.jpg';

  /// [DescriptionDraft.panoramas] dagi havola: `local:<katalog nomi>`.
  /// S3 kaliti (`listings/media/…`) va `job:` bilan adashmaydi.
  static String refOf(String dir) => 'local:${dir.split('/').last}';
  static bool isRef(String ref) => ref.startsWith('local:');

  LocalPano copyWith({LocalPanoStage? stage, String? error}) =>
      LocalPano(dir: dir, stage: stage ?? this.stage, error: error);

  Map<String, Object?> toJson() => {
    'dir': dir,
    'stage': stage.name,
    if (error != null) 'error': error,
  };

  factory LocalPano.fromJson(Map<String, Object?> j) => LocalPano(
    dir: (j['dir'] ?? '').toString(),
    stage: LocalPanoStage.values.firstWhere(
      (s) => s.name == j['stage'],
      orElse: () => LocalPanoStage.captured,
    ),
    error: j['error']?.toString(),
  );
}

/// [LocalPano] bosqichi.
///
/// `captured` — kadrlar bor, tikish kerak; `stitched` — `pano.jpg` tayyor,
/// yuklash kerak; `failed` — oxirgi urinish yiqildi (qaysi bosqichda —
/// katalogdagi `pano.jpg` borligidan bilinadi).
enum LocalPanoStage { captured, stitched, failed }

class DescriptionDraft {
  String text = '';
  final List<String> planFiles = [];
  final List<String> photos = [];
  /// 360° panoramalar — **S3 KALITLARI** (lokal yo'llar EMAS).
  ///
  /// ⚠️ Foto va planirovkadan FARQLI. Panorama serverda tikiladi
  /// (`panorama` Celery navbati) va tikish tugaganda u ALLAQACHON
  /// `listings/media/{user_id}/` da yotadi — ya'ni yuborishda qayta
  /// yuklanmaydi. Shuning uchun bu yerda kalit turadi va u bilan birga
  /// [uploadedMedia] ga `kalit → kalit` yozuvi qo'yiladi: `bozor_submit`
  /// shunda faylni yuklashga urinmaydi va to'g'ridan media ro'yxatiga
  /// qo'shadi.
  final List<String> panoramas = [];

  /// Kalit → ko'rsatish uchun URL. Viewer va tur ekrani shundan o'qiydi
  /// (e'lon hali yaratilmagani uchun serverdan `ListingOut` kelmaydi).
  final Map<String, String> panoramaUrls = {};

  /// HALI TIKILAYOTGAN panoramalar: [panoramas] dagi VAQTINCHALIK havola →
  /// serverdagi ish holati.
  ///
  /// ⚠️ NEGA VAQTINCHALIK HAVOLA. Tikish serverda ~7–9 daqiqa oladi va
  /// foydalanuvchi uni kutib o'tirmaydi — capture ekrani kadrlar
  /// yuborilishi bilan yopiladi. Panorama esa TARTIBDAGI o'z o'rnini
  /// egallashi kerak (foydalanuvchi uni ko'rib turibdi), shuning uchun
  /// [panoramas] ga darhol `job:<id>` ko'rinishidagi havola qo'yiladi va
  /// tayyor bo'lganda AYNAN O'SHA O'RINDA haqiqiy S3 kalitiga
  /// almashtiriladi.
  ///
  /// ⚠️ Bo'sh bo'lmasa e'lonni YUBORIB BO'LMAYDI — aks holda tayyor
  /// bo'lmagan panorama `bozor_submit` da jimgina tashlanib ketardi
  /// (`uploadedMedia` da kaliti yo'q).
  final Map<String, PendingPano> pendingPanoramas = {};

  /// Telefonda saqlangan, hali yuklanmagan tushirishlar: `local:<uuid>`
  /// havola → holat. [LocalPano] izohiga qarang.
  final Map<String, LocalPano> localPanoramas = {};

  /// Havola → XONA NOMI («Zal», «Oshxona»). Har skan xonaga bog'lanadi:
  /// nom capture'dan OLDIN so'raladi, `local:` havola kalitga almashganda
  /// nom ham ko'chadi, yuborishda `media[].title` bo'lib ketadi. Yo'q bo'lsa
  /// UI «Xona N» deb ko'rsatadi.
  final Map<String, String> panoramaNames = {};

  /// [ref] xonasining nomi yoki `null`.
  String? roomName(String ref) {
    final n = panoramaNames[ref]?.trim();
    return (n == null || n.isEmpty) ? null : n;
  }

  /// [panoramas] dagi havola hali TAYYOR EMASmi (serverda tikilayotgan yoki
  /// telefonda yuklanmagan) — sfera/turga qo'shilmaydi.
  bool isPending(String ref) =>
      pendingPanoramas.containsKey(ref) || localPanoramas.containsKey(ref);

  /// Tikish yiqilgan panoramalar — qatorda QIZIL ko'rinadi.
  Iterable<String> get failedPanoramas => pendingPanoramas.entries
      .where((e) => e.value.failed)
      .map((e) => e.key);

  /// Hali ishlayotganlar (xato bermaganlar).
  Iterable<String> get workingPanoramas => pendingPanoramas.entries
      .where((e) => !e.value.failed)
      .map((e) => e.key);

  /// TAHRIRLASHDA: e'londa ALLAQACHON turgan fayllar (S3 kalitlari bilan).
  ///
  /// `PATCH` media ro'yxatini TO'LIQ almashtiradi, ya'ni saqlanadigan
  /// rasmlarni qaytarib yuborish kerak. Yangi e'londa bu ro'yxat bo'sh.
  ///
  /// M1-9 da tahrirlash faqat QO'SHADI: mavjud rasmni o'chirish uchun UI yo'q
  /// (u M4-25 — muqova tanlash va tartib bilan birga keladi). Shu sababli bu
  /// ro'yxat o'zgarmaydi, faqat yangi yuklanganlar ustiga qo'shiladi.
  final List<ExistingMedia> existingMedia = [];

  /// MUVAFFAQIYATLI yuklangan fayllar: qurilma yo'li → S3 kaliti.
  ///
  /// Yuborish yarim yo'lda uzilsa (Wi-Fi o'chdi, server 500) qoralama JOYIDA
  /// qoladi va foydalanuvchi qayta uriniradi. Shu xarita busiz har urinishda
  /// HAMMA fayl qaytadan ketardi: 12 fotoli e'lon uchun bu o'n daqiqa va
  /// storage'da bir necha to'plam yetim fayl. Endi faqat qolgani yuklanadi.
  ///
  /// Qoralama payload'ida saqlanadi, ya'ni ilova qayta ishga tushsa ham
  /// yo'qolmaydi.
  final Map<String, String> uploadedMedia = {};

  /// 360° tur havolalari — panoramalarni bir-biriga bog'laydi.
  ///
  /// Uchlari LOKAL YO'L (hali yuklanmagan panorama) yoki S3 KALITI
  /// (tahrirlashda e'londa allaqachon turgani) bo'lishi mumkin;
  /// `resolveTourLinks` yuborishdan oldin ikkalasini kalitga keltiradi.
  final List<TourLink> tourLinks = [];

  String youtubeUrl = '';
}

/// 6-qadamning ma'lumotlari.
class ContactsDraft {
  String name = '';

  /// Telefon raqamlari — FAQAT milliy qism (9 raqam), `+998` siz.
  /// Birinchisi majburiy, qolganini foydalanuvchi qo'shadi.
  final List<String> phones = [''];

  String email = '';
}

/// E'lonni joylashtirish tarifi.
enum PlacementTier { standard, top }

/// 7-qadamning ma'lumotlari.
class TermsDraft {
  PlacementTier tier = PlacementTier.standard;

  /// Shartlarga rozilik.
  ///
  /// Dizaynda BELGILANGAN holda chizilgan, lekin biz `false` dan boshlaymiz:
  /// oldindan belgilangan katakcha rozilik hisoblanmaydi — u foydalanuvchining
  /// ijobiy harakati bo'lishi kerak. ("Торг уместен" boshqa masala: u rozilik
  /// emas, sozlama, shuning uchun u dizayndagidek yoqilgan turadi.)
  bool accepted = false;
}

/// Sehrgar to'ldirib boradigan qoralama.
///
/// Keyingi qadamlar o'z bo'limlarini shu klassga qo'shadi.
class BozorDraft {
  BozorDraft({this.deal, this.kind, this.type});

  DealType? deal;
  PropertyKind? kind;
  PropertyType? type;

  /// Serverdagi qoralama qatorining id'si (`bozor_listing_drafts.id`).
  ///
  /// Birinchi qadam saqlanganda paydo bo'ladi va sehrgar bo'ylab qoralama
  /// bilan birga yuradi. `null` — hali saqlanmagan (yoki foydalanuvchi
  /// tizimga kirmagan, yoki tarmoq yo'q): bunday holatda yuborish eski
  /// yo'l bilan, `POST /listings/` orqali ketadi.
  int? draftId;

  /// Tahrirlanayotgan e'lonning id'si.
  ///
  /// `null` — YANGI e'lon (qoralama → `submit`, yoki to'g'ridan-to'g'ri
  /// `POST`). To'lgan bo'lsa yuborish `PATCH /listings/{id}` ga ketadi va
  /// yangi e'lon YARATILMAYDI. Ikkisi bir vaqtda bo'lmaydi: tahrirlash
  /// mavjud e'londan boshlanadi, qoralamadan emas.
  int? editingListingId;

  bool get isEditing => editingListingId != null;

  final AddressDraft address = AddressDraft();

  /// 3-qadam qiymatlari — sxema bo'yicha kalit→qiymat
  /// (`param_schema.dart` ga qarang). Turi o'zgarsa tozalanadi.
  final Map<String, Object?> params = {};

  /// 1-qadam to'liq to'ldirilganmi — "Далее" shunga qarab yonadi.
  bool get isTypeStepComplete => deal != null && kind != null && type != null;

  /// Tanlangan (e'lon turi × mulk turi) juftligidagi qadamlar ro'yxati —
  /// [wizardStepsFor] ga qarang.
  List<WizardStep> get wizardSteps => wizardStepsFor(deal, type);

  int get stepCount => wizardSteps.length;

  /// Qadamning 1 dan boshlanadigan tartib raqami (`4/7` dagi 4).
  int stepNumber(WizardStep step) => wizardSteps.indexOf(step) + 1;

  /// `StepProgressBar.activeIndex` uchun 0 dan boshlanadigan indeks.
  int stepIndex(WizardStep step) => wizardSteps.indexOf(step);

  /// Shu qadamdan keyingisi. Oxirgi qadamda `null`.
  WizardStep? stepAfter(WizardStep step) {
    final i = wizardSteps.indexOf(step);
    return i < 0 || i + 1 >= wizardSteps.length ? null : wizardSteps[i + 1];
  }

  /// 4/8 «Сделка» qiymatlari — FAQAT sotuvda to'ldiriladi. Ijara e'lonida
  /// bo'sh qoladi va payload'ga umuman ketmaydi.
  final TransactionDraft transaction = TransactionDraft();

  /// Narx qadamining qiymatlari (ijara 4/7, sotuv 5/8).
  final PriceDraft price = PriceDraft();

  /// E'lon sarlavhasi. Dizaynda sehrgar uni SO'RAMAYDI, lekin lenta kartasi
  /// va "E'lonlarim" ro'yxati uchun kerak — 5-qadamga maydon qo'shildi.
  String title = '';

  /// 5-qadam qiymatlari.
  final DescriptionDraft description = DescriptionDraft();

  /// 6-qadam qiymatlari.
  final ContactsDraft contacts = ContactsDraft();

  /// 7-qadam qiymatlari.
  final TermsDraft terms = TermsDraft();

  /// E'lon turi o'zgarganda narx BIRLIGINI shu oqimga moslaydi.
  ///
  /// NEGA KERAK. Ijarada birlik davr bilan keladi (`UZS/oy`), sotuvda esa
  /// davr umuman yo'q (`UZS`). Foydalanuvchi ijarani tanlab narxgacha borib,
  /// keyin 1-qadamga qaytib sotuvni tanlasa, `unit` da `'UZS/oy'` qolib
  /// ketardi va e'lon "sotiladi, oyiga …" bo'lib chiqardi.
  ///
  /// Valyuta SAQLANADI — foydalanuvchi uni ataylab tanlagan bo'lishi mumkin;
  /// faqat davr qismi olib tashlanadi yoki qo'shiladi.
  ///
  /// Sotuvdan ijaraga qaytilganda «Сделка» va «Ипотека» ham tozalanadi: ular
  /// ijara e'lonida yuborilsa backend 400 beradi.
  void setDeal(DealType? next) {
    if (deal == next) return;
    deal = next;
    final currency = price.unit.split('/').first.trim();
    switch (next) {
      case DealType.sale:
        price.unit = currency;
        // Sutkalik narx sotuvda yo'q.
        price.dailyAmount = '';
      case DealType.rent:
        price.unit = '$currency/oy';
        price.mortgage = false;
        transaction
          ..saleType = null
          ..ownershipYears = null
          ..ownersCount = null
          ..registeredCount = null;
      case null:
        break;
    }
  }

  /// Toifa o'zgarganda unga tegishli bo'lmay qolgan turni tozalaydi.
  void setKind(PropertyKind? next) {
    kind = next;
    if (type != null && type!.kind != next) setType(null);
  }

  /// Mulk turi o'zgarsa 3-qadam qiymatlari boshqa sxemaga tegishli bo'lib
  /// qoladi — tozalanadi. Aks holda kvartiraning "Balkon" qiymati uyning
  /// formasida osilib qolardi.
  void setType(PropertyType? next) {
    if (type == next) return;
    type = next;
    params.clear();
    // «Прописано» faqat kvartira turlarida so'raladi — uyga o'tilsa qiymat
    // osilib qolmasin, aks holda backend uni 400 bilan rad etadi.
    transaction.clearRegisteredIfUnsupported(next);
  }
}
