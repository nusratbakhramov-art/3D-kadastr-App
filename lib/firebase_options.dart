// Firebase konfiguratsiyasi — GoogleService-Info.plist qiymatlaridan.
// `Firebase.initializeApp(options: ...)` uchun. iOS plist bundle'ga
// qo'shilmaganligi sabab native auto-init ishlamasdi; aniq options bu
// muammoni hal qiladi. (flutterfire generatsiyasiga mos format.)
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  /// iOS uchun Firebase options (loyiha `dkadastr-59574`).
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBoQM5D2YgxI0AZiVCRZ2a_kPlTclzldqw',
    appId: '1:722546785212:ios:41a67b295b117ee05189b9',
    messagingSenderId: '722546785212',
    projectId: 'dkadastr-59574',
    storageBucket: 'dkadastr-59574.firebasestorage.app',
    iosBundleId: 'uz.kadastr.kadastr',
  );
}
