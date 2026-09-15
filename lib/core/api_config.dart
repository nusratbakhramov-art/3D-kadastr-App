class ApiConfig {
  const ApiConfig._();

  /// Backend host (no path). Used for static assets, presigned URLs that
  /// come back relative, etc.
  // PROD by default — a release build with no --dart-define stays on prod, so
  // master is still safe to build from.
  //
  // Local backend, without editing this file:
  //   simulator:  flutter run --dart-define=KADASTR_SERVER=http://localhost:8009
  //   real phone: flutter run --dart-define=KADASTR_SERVER=http://<mac-lan-ip>:8009
  //               (a phone also needs that IP added to NSExceptionDomains in
  //                ios/Runner/Info.plist — loopback is already covered by
  //                NSAllowsLocalNetworking)
  static const String serverBaseUrl = String.fromEnvironment(
    'KADASTR_SERVER',
    defaultValue: 'https://api.3dkadastr.uz',
  );

  /// API prefix — versioned REST endpoints live here.
  static const String baseUrl = '$serverBaseUrl/api/v1';

  // Geocoding (address autocomplete + reverse) is proxied through the backend
  // at `/api/v1/geo/*` — see GeocoderClient. No third-party key ships in the app.

  /// Resolve a possibly-relative URL returned by the backend (e.g.
  /// `/static/...`) into an absolute URL the device can fetch. Absolute URLs
  /// are returned untouched.
  static String resolveUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('/')) return '$serverBaseUrl$url';
    return '$serverBaseUrl/$url';
  }
}
