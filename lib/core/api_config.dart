import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  const ApiConfig._();

  /// Backend host (no path). Used for static assets, presigned URLs that
  /// come back relative, etc.
  // PROD — telefon prod backendga ulanadi.
  static const String serverBaseUrl = 'https://api.3dkadastr.uz';
  // Dev (telefon → Mac LAN IP): 'http://192.168.1.64:8009'
  // Dev (simulator only): 'http://localhost:8009'

  /// API prefix — versioned REST endpoints live here.
  static const String baseUrl = '$serverBaseUrl/api/v1';

  // Geocoding (address autocomplete + reverse) is proxied through the backend
  // at `/api/v1/geo/*` — see GeocoderClient. No third-party key ships in the app.

  /// V2M (3DGS) server — video → gaussian splat.
  ///
  /// TEMPORARY: during the first phase the phone uploads straight to the GPU
  /// box, so the app has to know its address. Once the main backend brokers
  /// the upload (it returns `upload_url` + a ticket) this goes away and the
  /// app stops knowing where the GPU lives.
  ///
  /// The box is a Vast.ai instance whose host and port change on every
  /// restart — override it without rebuilding by putting
  /// `v2m_base_url=http://host:port` into `.env`.
  static String get v2mBaseUrl {
    final override =
        dotenv.isInitialized ? dotenv.maybeGet('v2m_base_url') : null;
    final url = (override != null && override.isNotEmpty)
        ? override
        : _v2mFallback;
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  static const String _v2mFallback = 'http://45.81.32.55:16219';

  /// Resolve a possibly-relative URL returned by the backend (e.g.
  /// `/static/...`) into an absolute URL the device can fetch. Absolute URLs
  /// are returned untouched.
  static String resolveUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('/')) return '$serverBaseUrl$url';
    return '$serverBaseUrl/$url';
  }
}
