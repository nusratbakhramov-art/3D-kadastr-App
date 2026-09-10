// `flutter drive` uchun host tomonidagi drayver.
//
// NEGA KERAK: `flutter test integration_test/...` ilovani faqat DEBUG (JIT)
// da yig'adi, `--profile` bayrog'i unda YO'Q. Sof Dart JPEG dekodini JIT'da
// o'lchash — noto'g'ri qaror uchun to'g'ri yo'l. AOT'da yurgizishning yagona
// yo'li `flutter drive --profile`, u esa drayver faylini talab qiladi.
//
// Nomi ataylab `*_test.dart` EMAS: aks holda `flutter test` uni ham test deb
// yig'ishga urinardi (u host-only `flutter_driver` ga tayanadi).
//
// Chaqiruvchi: tool/pano/bench_decode.sh

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
