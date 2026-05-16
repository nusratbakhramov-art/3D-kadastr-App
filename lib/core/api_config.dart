class ApiConfig {
  const ApiConfig._();

  /// Backend host (no path). Used for static assets, presigned URLs that
  /// come back relative, etc.
  static const String serverBaseUrl = 'https://api.3dkadastr.uz';
  // Dev: 'http://192.168.1.37:8009'

  /// API prefix — versioned REST endpoints live here.
  static const String baseUrl = '$serverBaseUrl/api/v1';

  /// Resolve a possibly-relative URL returned by the backend (e.g.
  /// `/static/...`) into an absolute URL the device can fetch. Absolute URLs
  /// are returned untouched.
  static String resolveUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('/')) return '$serverBaseUrl$url';
    return '$serverBaseUrl/$url';
  }
}
