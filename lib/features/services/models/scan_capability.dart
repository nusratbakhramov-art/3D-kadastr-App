enum ScanTier { lidar, roomPlan, depthApi, photogrammetry, unsupported }

class ScanCapability {
  const ScanCapability({
    required this.platform,
    required this.hasLidar,
    required this.hasRoomPlan,
    required this.hasArCore,
    required this.hasDepthApi,
    required this.arWorldTrackingSupported,
    required this.deviceModel,
    required this.osVersion,
  });

  final String platform;
  final bool hasLidar;
  final bool hasRoomPlan;
  final bool hasArCore;
  final bool hasDepthApi;
  final bool arWorldTrackingSupported;
  final String deviceModel;
  final String osVersion;

  factory ScanCapability.fromMap(Map<dynamic, dynamic> m) => ScanCapability(
    platform: m['platform'] as String? ?? 'unknown',
    hasLidar: m['hasLidar'] as bool? ?? false,
    hasRoomPlan: m['hasRoomPlan'] as bool? ?? false,
    hasArCore: m['hasArCore'] as bool? ?? false,
    hasDepthApi: m['hasDepthApi'] as bool? ?? false,
    arWorldTrackingSupported: m['arWorldTrackingSupported'] as bool? ?? false,
    deviceModel: m['deviceModel'] as String? ?? 'unknown',
    osVersion: m['osVersion'] as String? ?? 'unknown',
  );

  ScanTier get tier {
    if (hasLidar && hasRoomPlan) return ScanTier.roomPlan;
    if (hasLidar) return ScanTier.lidar;
    if (hasDepthApi) return ScanTier.depthApi;
    if (arWorldTrackingSupported || hasArCore) return ScanTier.photogrammetry;
    return ScanTier.photogrammetry;
  }
}
