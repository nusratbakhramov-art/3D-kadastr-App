class ApiConfig {
  const ApiConfig._();

  /// Backend host (no path). Used for static assets, presigned URLs that
  /// come back relative, etc.
  static const String serverBaseUrl = 'https://api.3dkadastr.uz';
  // Dev (telefon LAN): 'http://192.168.1.15:8009'
  // Dev (simulator): 'http://localhost:8009'

  /// API prefix — versioned REST endpoints live here.
  static const String baseUrl = '$serverBaseUrl/api/v1';

  /// Yandex Geocoder API key. Empty by default — the [GeocoderClient]
  /// then falls back to OpenStreetMap Nominatim (free, works for UZ
  /// addresses). Drop a real key here when you have one.
  static const String yandexGeocoderApiKey = '';

  /// Resolve a possibly-relative URL returned by the backend (e.g.
  /// `/static/...`) into an absolute URL the device can fetch. Absolute URLs
  /// are returned untouched.
  static String resolveUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('/')) return '$serverBaseUrl$url';
    return '$serverBaseUrl/$url';
  }
}
