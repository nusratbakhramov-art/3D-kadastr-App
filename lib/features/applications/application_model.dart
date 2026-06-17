enum ApplicationStatusGroup { sent, received, inProgress, completed, cancelled }

enum ApplicationTimelineStatus {
  accepted,
  sentToSystem,
  assignedSpecialist,
  scanned,
  reportReady,
}

class ApplicationTimelineStep {
  const ApplicationTimelineStep({
    required this.status,
    required this.at,
    required this.completed,
  });

  final ApplicationTimelineStatus status;
  final DateTime at;
  final bool completed;
}

class ApplicationItem {
  const ApplicationItem({
    required this.id,
    this.orderNo,
    this.aiJobId,
    required this.serviceId,
    required this.serviceLabel,
    required this.statusGroup,
    required this.addressLabel,
    required this.addressValue,
    required this.dateLabel,
    required this.dateValue,
    required this.timeline,
    this.typeLabel,
    this.typeValue,
    this.detailRows = const <(String, String)>[],
    this.hasDeliverable = false,
    this.isDraft = false,
    this.resumeJobId,
    this.aiScanJobId,
    this.aiReportJobId,
    this.k3dJobId,
    this.k3dReportJobId,
    this.k3dModelJobId,
    this.k3dModelExt,
    this.estimatorComment,
    this.estimatorCause,
    this.hasResultPreview = false,
    this.formKey,
    this.formPayload,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// Backend numeric order/ariza id shown on the card as `#NN`. Same as the
  /// per-service job/order id (e.g. AI job id, calculator order id).
  final int? orderNo;

  /// AI Baholash job id — set only for AI items. Lets the detail screen fetch
  /// the FULL job snapshot (request + result payload) to show every field,
  /// instead of just the lightweight list summary.
  final int? aiJobId;

  final String serviceId;
  final String serviceLabel;
  final ApplicationStatusGroup statusGroup;
  final String addressLabel;
  final String addressValue;
  final String dateLabel;
  final String dateValue;
  final String? typeLabel;
  final String? typeValue;

  /// Real (label, value) rows shown on the detail "Ariza haqida" tab. Built
  /// from the backend summary per service type — replaces the old mock report.
  final List<(String, String)> detailRows;

  /// Whether a downloadable 3D model / report deliverable exists for this
  /// item (only completed photogrammetry scans today). Drives whether the
  /// file / 3D-model / AR cards are shown on the detail screen.
  final bool hasDeliverable;

  /// Tugallanmagan (DRAFT) AI Baholash arizasi — kartada "Qoralama" badge va
  /// "Davom etish" tugmasi chiqadi (natija o'rniga).
  final bool isDraft;

  /// DRAFT bo'lsa, davom ettirish uchun AI Baholash job id (resume).
  final int? resumeJobId;

  /// AI Baholash arizasiga teksturali 3D (USDZ) skan biriktirilgan bo'lsa,
  /// o'sha job id — detail ekranida "3D skan" kartasi ko'rsatiladi va
  /// `/ai-valuations/{id}/scan` dan yuklab olinadi. Skan yo'q bo'lsa null.
  final int? aiScanJobId;

  /// AI Baholash arizasi COMPLETED (mutaxassis hisobotni generatsiya qilган)
  /// bo'lsa, o'sha job id — detail ekranida yakuniy "Xulosa (PDF)" yuklab olish
  /// kartasi ko'rsatiladi (`/ai-valuations/{id}/report`). Aks holda null.
  final int? aiReportJobId;

  /// 3D Kadastr job id — set for every 3D item. Lets the detail screen fetch the
  /// FULL job snapshot (request_payload) and render all the data the user gave,
  /// not just the lightweight list summary (mirrors [aiJobId] for AI Baholash).
  final int? k3dJobId;

  /// 3D Kadastr arizasi COMPLETED bo'lib, mutaxassis yetkazgan deliverable'lar:
  ///   • k3dReportJobId — xulosa PDF mavjud (`/3d-kadastr-jobs/{id}/report`)
  ///   • k3dModelJobId  — 3D model mavjud (`/3d-kadastr-jobs/{id}/model`)
  ///   • k3dModelExt    — model kengaytmasi (glb/usdz) — to'g'ri viewer tanlash uchun
  /// Yo'q bo'lsa null — detail ekranida tegishli karta ko'rsatilmaydi.
  final int? k3dReportJobId;
  final int? k3dModelJobId;
  final String? k3dModelExt;

  /// Baholash guruhi xulosasi (egasi bilan bog'langач yozilgan) — berilgan
  /// bo'lsa ariza detalida foydalanuvchiga ko'rsatiladi.
  final String? estimatorComment;
  final String? estimatorCause;

  /// AI Baholash natijasi tayyor (taxminiy qiymat mavjud) — ariza hali
  /// yakunlanmagan bo'lsa ham foydalanuvchi "Natijani ko'rish" orqali ko'radi.
  final bool hasResultPreview;

  /// Dinamik forma kaliti (masalan "arxitektura_tz"). Berilgan bo'lsa, detail
  /// ekrani arizani backend sxemasi bo'yicha to'liq (barcha maydonlar, bo'limga
  /// ajratilgan) ko'rsatadi — `detailRows` o'rniga.
  final String? formKey;

  /// Yuborilgan ariza payload'i (kalit→qiymat, ichki `details` bilan) — sxema
  /// bo'yicha renderlash uchun. Backend list/detail javobining xom ko'rinishi.
  final Map<String, dynamic>? formPayload;

  /// Ariza yaratilgan vaqt (detail'da ko'rsatiladi).
  final DateTime createdAt;

  /// Oxirgi yangilanish (status o'zgargan vaqt) — ro'yxat shu bo'yicha
  /// saralanadi (yangisi tepada) va sana+soat shu ko'rsatiladi.
  final DateTime updatedAt;

  final List<ApplicationTimelineStep> timeline;
}

class ApplicationServiceChip {
  const ApplicationServiceChip({required this.id, required this.label});

  final String id;
  final String label;
}

const List<ApplicationServiceChip> applicationServiceChips = [
  ApplicationServiceChip(id: 'all', label: 'Barchasi'),
  ApplicationServiceChip(id: 'kad_3d', label: '3D Kadastr'),
  ApplicationServiceChip(id: 'ai_eval', label: 'AI Baholash'),
  ApplicationServiceChip(id: 'calc', label: 'Kalkulyator'),
];
