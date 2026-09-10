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

/// E'lon turi. Dizaynda faqat [rent] oqimi chizilgan; [sale] model uchun bor,
/// uning 4-qadami (narx) hali dizaynda yo'q.
enum DealType { rent, sale }

/// Mulk toifasi — [PropertyType] ro'yxatini filtrlaydi.
enum PropertyKind { residential, nonResidential }

/// Mulk turi — sehrgarning butun shakli shunga bog'liq.
enum PropertyType {
  apartment,
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
    PropertyType.house => tr(l, 'bozor.type.house'),
    PropertyType.land => tr(l, 'bozor.type.land'),
    PropertyType.commercial => tr(l, 'bozor.type.commercial'),
    PropertyType.garage => tr(l, 'bozor.type.garage'),
    PropertyType.otherNonResidential => tr(l, 'bozor.type.other_non_res'),
  };

  /// Qaysi toifaga tegishli — toifa o'zgarganda turni tozalash uchun.
  PropertyKind get kind => switch (this) {
    PropertyType.apartment ||
    PropertyType.house ||
    PropertyType.land => PropertyKind.residential,
    PropertyType.commercial ||
    PropertyType.garage ||
    PropertyType.otherNonResidential => PropertyKind.nonResidential,
  };

  /// Shu turdagi qadamlar ketma-ketligi.
  ///
  /// "Boshqa noturar joy" da "Параметры" qadami YO'Q — shu sababli unda 6 ta
  /// qadam va narx UCHINCHI o'rinda turadi (dizaynda `3/6`), qolganlarida esa
  /// to'rtinchi (`4/7`). Raqamlar hech qayerda qo'lda yozilmasin: ekranlar
  /// [BozorDraft.stepNumber] dan so'raydi.
  List<WizardStep> get wizardSteps =>
      this == PropertyType.otherNonResidential
      ? const [
          WizardStep.type,
          WizardStep.address,
          WizardStep.price,
          WizardStep.description,
          WizardStep.contacts,
          WizardStep.terms,
        ]
      : const [
          WizardStep.type,
          WizardStep.address,
          WizardStep.params,
          WizardStep.price,
          WizardStep.description,
          WizardStep.contacts,
          WizardStep.terms,
        ];

  int get stepCount => wizardSteps.length;
}

/// Sehrgar qadamlari. Ro'yxati mulk turiga bog'liq —
/// [PropertyTypeX.wizardSteps] ga qarang.
enum WizardStep { type, address, params, price, description, contacts, terms }

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
      PropertyType.apartment => const [
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
    PropertyType.apartment => tr(l, 'bozor.desc.about.apartment'),
    PropertyType.house => tr(l, 'bozor.desc.about.house'),
    PropertyType.land => tr(l, 'bozor.desc.about.land'),
    PropertyType.commercial => tr(l, 'bozor.desc.about.commercial'),
    PropertyType.garage => tr(l, 'bozor.desc.about.garage'),
    PropertyType.otherNonResidential => tr(l, 'bozor.desc.about.other'),
  };

  /// Manzil qatorining sarlavhasi — faqat kvartirada boshqacha.
  String addressRowLabel(Locale l) => this == PropertyType.apartment
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

  /// Sutkalik narx — faqat kvartira va uyda.
  String dailyAmount = '';
  String dailyUnit = 'UZS';
}

/// E'londa allaqachon turgan fayl — tahrirlashda qaytarib yuborish uchun.
class ExistingMedia {
  const ExistingMedia({
    required this.key,
    required this.role,
    required this.sortOrder,
    required this.isCover,
  });

  final String key;
  final String role;
  final int sortOrder;
  final bool isCover;
}

/// 5-qadamning ma'lumotlari.
///
/// Fayllar LOKAL yo'llar sifatida saqlanadi — yuklash endpoint'i hali yo'q.
/// Planirovka va 360 ham ro'yxat: dizaynda nechta fayl ruxsat etilgani
/// ko'rsatilmagan, ro'yxat bo'lsa chegarani keyin validatsiya hal qiladi.
class DescriptionDraft {
  String text = '';
  final List<String> planFiles = [];
  final List<String> photos = [];
  final List<String> panoramas = [];

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
  String youtubeUrl = '';
}

/// 6-qadamning ma'lumotlari.
class ContactsDraft {
  String name = '';

  /// Telefon raqamlari — FAQAT milliy qism (9 raqam), `+998` siz.
  /// Birinchisi majburiy, qolganini foydalanuvchi qo'shadi.
  final List<String> phones = [''];

  String email = '';

  /// SMS kod tasdiqlanganmi. Hozircha faqat UI holati — tekshiruvning
  /// backend tarafi yo'q (`bozor_contacts_step_screen.dart` izohiga qarang).
  bool phoneVerified = false;
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

  /// Tanlangan turdagi qadamlar ro'yxati. Tur hali tanlanmagan bo'lsa eng
  /// keng tarqalgan holat (7 qadam) — progress chizig'i sakramasligi uchun.
  List<WizardStep> get wizardSteps =>
      (type ?? PropertyType.apartment).wizardSteps;

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

  /// 4-qadam qiymatlari.
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
  }
}
