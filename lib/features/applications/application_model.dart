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

final List<ApplicationItem> mockApplicationItems = [
  ApplicationItem(
    id: 'app_1',
    serviceId: 'kad_3d',
    serviceLabel: '3D kadastr',
    statusGroup: ApplicationStatusGroup.inProgress,
    addressLabel: 'Manzil',
    addressValue: 'Toshkent, Chilonzor',
    dateLabel: 'Ariza sanasi',
    dateValue: '02.04.2026',
    timeline: _timelineInProgress,
  ),
  ApplicationItem(
    id: 'app_2',
    serviceId: 'ai_eval',
    serviceLabel: 'AI Baholash',
    statusGroup: ApplicationStatusGroup.completed,
    addressLabel: 'Manzil',
    addressValue: 'Toshkent, Chilonzor',
    dateLabel: 'Ariza sanasi',
    dateValue: '02.04.2026',
    timeline: _timelineCompleted,
  ),
  ApplicationItem(
    id: 'app_3',
    serviceId: 'calc',
    serviceLabel: 'Kalkulyator',
    statusGroup: ApplicationStatusGroup.completed,
    addressLabel: 'Turi',
    addressValue: 'Arxitektura',
    dateLabel: 'Ariza sanasi',
    dateValue: '02.04.2026',
    timeline: _timelineCompleted,
  ),
  ApplicationItem(
    id: 'app_4',
    serviceId: 'kad_3d',
    serviceLabel: '3D kadastr',
    statusGroup: ApplicationStatusGroup.completed,
    addressLabel: 'Manzil',
    addressValue: 'Toshkent, Chilonzor',
    dateLabel: 'Ariza sanasi',
    dateValue: '02.04.2026',
    timeline: _timelineCompleted,
  ),
  ApplicationItem(
    id: 'app_5',
    serviceId: 'ai_eval',
    serviceLabel: 'AI Baholash',
    statusGroup: ApplicationStatusGroup.cancelled,
    addressLabel: 'Manzil',
    addressValue: 'Toshkent, Chilonzor',
    dateLabel: 'Ariza sanasi',
    dateValue: '02.04.2026',
    timeline: _timelineCancelled,
  ),
];

final List<ApplicationTimelineStep> _timelineInProgress = [
  ApplicationTimelineStep(
    status: ApplicationTimelineStatus.accepted,
    at: DateTime(2025, 1, 23, 15, 1),
    completed: true,
  ),
  ApplicationTimelineStep(
    status: ApplicationTimelineStatus.sentToSystem,
    at: DateTime(2025, 1, 23, 15, 1),
    completed: true,
  ),
  ApplicationTimelineStep(
    status: ApplicationTimelineStatus.assignedSpecialist,
    at: DateTime(2025, 1, 23, 15, 1),
    completed: true,
  ),
  ApplicationTimelineStep(
    status: ApplicationTimelineStatus.scanned,
    at: DateTime(2025, 1, 23, 15, 1),
    completed: false,
  ),
  ApplicationTimelineStep(
    status: ApplicationTimelineStatus.reportReady,
    at: DateTime(2025, 1, 23, 15, 1),
    completed: false,
  ),
];

final List<ApplicationTimelineStep> _timelineCompleted = [
  ApplicationTimelineStep(
    status: ApplicationTimelineStatus.accepted,
    at: DateTime(2025, 1, 23, 15, 1),
    completed: true,
  ),
  ApplicationTimelineStep(
    status: ApplicationTimelineStatus.sentToSystem,
    at: DateTime(2025, 1, 23, 15, 1),
    completed: true,
  ),
  ApplicationTimelineStep(
    status: ApplicationTimelineStatus.assignedSpecialist,
    at: DateTime(2025, 1, 23, 15, 1),
    completed: true,
  ),
  ApplicationTimelineStep(
    status: ApplicationTimelineStatus.scanned,
    at: DateTime(2025, 1, 23, 15, 1),
    completed: true,
  ),
  ApplicationTimelineStep(
    status: ApplicationTimelineStatus.reportReady,
    at: DateTime(2025, 1, 23, 15, 1),
    completed: true,
  ),
];

final List<ApplicationTimelineStep> _timelineCancelled = [
  ApplicationTimelineStep(
    status: ApplicationTimelineStatus.accepted,
    at: DateTime(2025, 1, 23, 15, 1),
    completed: true,
  ),
  ApplicationTimelineStep(
    status: ApplicationTimelineStatus.sentToSystem,
    at: DateTime(2025, 1, 23, 15, 1),
    completed: true,
  ),
  ApplicationTimelineStep(
    status: ApplicationTimelineStatus.assignedSpecialist,
    at: DateTime(2025, 1, 23, 15, 1),
    completed: false,
  ),
  ApplicationTimelineStep(
    status: ApplicationTimelineStatus.scanned,
    at: DateTime(2025, 1, 23, 15, 1),
    completed: false,
  ),
  ApplicationTimelineStep(
    status: ApplicationTimelineStatus.reportReady,
    at: DateTime(2025, 1, 23, 15, 1),
    completed: false,
  ),
];
