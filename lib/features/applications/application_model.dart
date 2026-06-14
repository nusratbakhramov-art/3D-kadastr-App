enum ApplicationStatusGroup { sent, inProgress, completed, cancelled }

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
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
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
