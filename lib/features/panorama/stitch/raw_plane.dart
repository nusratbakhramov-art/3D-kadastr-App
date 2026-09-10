/// Xom kadr keshi — 4K JPEG'ni BIR MARTA dekod qilish uchun.
///
/// NEGA KERAK. 76 kadr × 4K × 4 bayt ≈ **3.7 GB**, ya'ni hamma kadrni
/// xotirada ushlab turish imkonsiz. Quvur esa har kadrga bir necha marta
/// qaytadi (proyeksiya, nozik moslashtirish, ekspozitsiya tenglashtirish).
/// JPEG'ni har safar qayta dekod qilish esa eng qimmat amal — MIL-0
/// benchmarki aynan shuni o'lchaydi.
///
/// Yechim: JPEG bir marta dekod qilinadi, kerakli o'lchamga tushiriladi va
/// diskka XOM planar bufer sifatida yoziladi. Keyingi murojaatlar
/// dekodsiz, to'g'ridan-to'g'ri o'qiydi.
///
/// ⚠️ ENG XAVFLI JOY — YARIM YOZILGAN FAYL. Disk to'lib qolsa yoki ilova
/// yozish o'rtasida o'ldirilsa, keshda qisqa fayl qoladi. Uni jimgina
/// o'qish kadrni siljigan/buzilgan holda beradi va panorama sababsiz
/// buziladi — hech qanday xato chiqmasdan. Shu sababli sarlavhada o'lcham
/// bor va [RawPlane.decode] uzunlikni QAT'IY tekshiradi.
library;

import 'dart:typed_data';

/// Kesh fayli sarlavhasi — «Panorama RaW, 1-versiya».
///
/// Versiya raqami ATAYLAB: format o'zgarsa eski kesh fayllari jimgina
/// noto'g'ri o'qilmasligi kerak, ular RAD ETILISHI kerak.
const int kRawPlaneMagic = 0x50525731; // 'PRW1'

/// Sarlavha uzunligi: magic(4) + width(4) + height(4) + channels(1) +
/// to'ldirish(3) = 16 bayt.
///
/// To'ldirish ma'lumot boshini 4 baytga tekislaydi — `Uint8List.view`
/// tekislanmagan offsetda ham ishlaydi, lekin `Uint32List.view` ishlamaydi
/// va format keyinchalik 16-bitli chuqurlikka o'tsa shu muhim bo'ladi.
const int kRawPlaneHeaderBytes = 16;

class RawPlaneFormatException implements Exception {
  const RawPlaneFormatException(this.message);
  final String message;
  @override
  String toString() => 'RawPlaneFormatException: $message';
}

/// Bir yoki bir necha PLANAR kanalli xom tasvir.
///
/// Kanallar KETMA-KET saqlanadi (`RRR…GGG…BBB…`), interleaved emas
/// (`RGBRGB…`). Sabab: butun raster qatlami (`raster.dart`) bir kanalli
/// planar buferlar ustida ishlaydi — interleaved buferda har piksel uchun
/// indeks uch marta hisoblanadi va kesh yomon ishlaydi.
class RawPlane {
  RawPlane({
    required this.width,
    required this.height,
    required this.channels,
    required this.bytes,
  }) : assert(width > 0 && height > 0),
       assert(channels >= 1 && channels <= 4),
       assert(
         bytes.length == width * height * channels,
         'bufer uzunligi o‘lchamga mos emas',
       );

  final int width;
  final int height;
  final int channels;

  /// Hamma kanal, ketma-ket.
  final Uint8List bytes;

  int get pixelsPerChannel => width * height;

  /// [c] kanalining KO'RINISHI — nusxa EMAS.
  ///
  /// Ko'rinish ataylab: nusxa olish 76 kadr uchun yuzlab megabayt ortiqcha
  /// ish bo'lardi. Chaqiruvchi uni O'ZGARTIRMASLIGI kerak.
  Uint8List plane(int c) {
    assert(c >= 0 && c < channels, 'kanal $c mavjud emas ($channels ta)');
    return Uint8List.sublistView(
      bytes,
      c * pixelsPerChannel,
      (c + 1) * pixelsPerChannel,
    );
  }

  /// Diskka yoziladigan to'liq bayt ketma-ketligi (sarlavha + ma'lumot).
  Uint8List encode() {
    final out = Uint8List(kRawPlaneHeaderBytes + bytes.length);
    final head = ByteData.sublistView(out, 0, kRawPlaneHeaderBytes);
    // Endianlik OCHIQ ko'rsatiladi. Sukutga tashlab ketilsa kesh fayli
    // boshqa arxitekturada boshqacha o'qilardi — bugun ARM64, lekin
    // simulyator x86_64 bo'lishi mumkin.
    head.setUint32(0, kRawPlaneMagic, Endian.little);
    head.setUint32(4, width, Endian.little);
    head.setUint32(8, height, Endian.little);
    head.setUint8(12, channels);
    // 13..15 — to'ldirish, nol.
    out.setRange(kRawPlaneHeaderBytes, out.length, bytes);
    return out;
  }

  /// Kesh faylini o'qish. Har qanday nomuvofiqlikda ISTISNO tashlaydi.
  ///
  /// ⚠️ Bu yerda «yaxshi niyat» qilish MUMKIN EMAS. Yarim yozilgan yoki
  /// eski versiyadagi faylni «bor narsasi bilan» o'qish kadrni siljigan
  /// holda beradi va panorama sababsiz buziladi — hech qanday xato
  /// chiqmasdan. Rad etilgan kesh esa shunchaki qayta dekod qilinadi.
  static RawPlane decode(Uint8List raw) {
    if (raw.length < kRawPlaneHeaderBytes) {
      throw RawPlaneFormatException(
        'fayl sarlavhadan qisqa (${raw.length} < $kRawPlaneHeaderBytes bayt)',
      );
    }
    final head = ByteData.sublistView(raw, 0, kRawPlaneHeaderBytes);
    final int magic = head.getUint32(0, Endian.little);
    if (magic != kRawPlaneMagic) {
      throw RawPlaneFormatException(
        'sarlavha PRW1 emas (0x${magic.toRadixString(16)})',
      );
    }
    final int width = head.getUint32(4, Endian.little);
    final int height = head.getUint32(8, Endian.little);
    final int channels = head.getUint8(12);
    if (width <= 0 || height <= 0 || channels < 1 || channels > 4) {
      throw RawPlaneFormatException(
        'sarlavhadagi o‘lchamlar ma\'nosiz ($width×$height×$channels)',
      );
    }
    final int need = width * height * channels;
    final int have = raw.length - kRawPlaneHeaderBytes;
    if (have != need) {
      throw RawPlaneFormatException(
        'ma\'lumot uzunligi mos emas: $have bayt bor, $need kerak '
        '($width×$height×$channels) — fayl yarim yozilgan bo‘lishi mumkin',
      );
    }
    return RawPlane(
      width: width,
      height: height,
      channels: channels,
      // `sublistView` — NUSXA EMAS, ya'ni katta kadr uchun ikkinchi marta
      // xotira ajratilmaydi.
      bytes: Uint8List.sublistView(raw, kRawPlaneHeaderBytes),
    );
  }
}
