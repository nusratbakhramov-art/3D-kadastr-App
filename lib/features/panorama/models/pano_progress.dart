/// Tikish jarayonining holati — foydalanuvchiga ko'rsatiladigan yagona
/// manba.
///
/// NEGA ALOHIDA MODEL. Tikish isolate ichida ketadi va u yerdan faqat
/// PRIMITIVLAR o'tadi. Progress'ni `SendPort` ga xom `Map` bo'lib
/// yuborish kalitlarni ikki joyda qo'lda ushlab turishni talab qilardi;
/// bitta model ikkala tomonni bog'laydi.
///
/// ⚠️ Bosqichlar ULUSHI o'lchangan, teng emas. Ularni teng deb
/// ko'rsatish progress chizig'ini yolg'onchi qiladi: dekod tez o'tadi,
/// keyin proyeksiya uzoq turadi va foydalanuvchi ilova qotib qoldi deb
/// o'ylaydi.
library;

import 'package:flutter/foundation.dart';

enum StitchPhase {
  /// Kadrlarni dekod qilish va xom keshga yozish.
  decode,

  /// Kadrlarni tuvalga qo'yish — eng qimmat bosqich.
  project,

  /// Ekspozitsiyani tenglashtirish (14-qadam).
  gains,

  /// Chok yo'nalishi (15-qadam).
  seam,

  /// Ko'p bandli aralashtirish (16-qadam).
  blend,

  /// Qamrovni o'lchash va faylga yozish.
  finish,
}

/// Har bosqichning taxminiy ULUSHI, 0..1 ga normallashtiriladi.
///
/// Rejadagi (§5.1) o'lchovdan: MIL-1 gains/seam/blend'siz quvurning
/// atigi ~41–60 %ini ko'radi, ya'ni seam 0.11 va blend 0.28 qolganini
/// tashkil qiladi.
const Map<StitchPhase, double> kPhaseShare = <StitchPhase, double>{
  StitchPhase.decode: 0.10,
  StitchPhase.project: 0.44,
  StitchPhase.gains: 0.05,
  StitchPhase.seam: 0.11,
  StitchPhase.blend: 0.28,
  StitchPhase.finish: 0.02,
};

/// MIL-1 o'lchovi KO'RADIGAN bosqichlar (13-qadam qamrovi).
///
/// Gains, seam va blend hali yozilmagan, ya'ni o'lchov quvurning faqat
/// shu qismini ko'radi.
const Set<StitchPhase> kMil1Phases = <StitchPhase>{
  StitchPhase.decode,
  StitchPhase.project,
  StitchPhase.finish,
};

/// MIL-1 o'lchovi ko'radigan ULUSH, [kPhaseShare] dan HISOBLANADI.
///
/// ⚠️ Hisoblanadi, yozib qo'yilmaydi. Ilgari bu son `dart_stitcher.dart`
/// da `0.10 + 0.44 + 0.02` bo'lib takrorlangan edi — [kPhaseShare]
/// o'zgarsa ekstrapolyatsiya JIMGINA noto'g'ri bo'lib qolardi va bu
/// «GO» qarorini buzardi.
double get kMil1Share =>
    kMil1Phases.fold(0.0, (a, p) => a + kPhaseShare[p]!);

@immutable
class PanoProgress {
  const PanoProgress({
    required this.phase,
    required this.done,
    required this.total,
    this.elapsed = Duration.zero,
  }) : assert(total >= 0),
       assert(done >= 0);

  final StitchPhase phase;

  /// Shu bosqichda bajarilgan birlik (kadr, tasma, oktava).
  final int done;

  /// Shu bosqichdagi jami birlik. `0` — noma'lum (aniqlanmagan
  /// uzunlikdagi bosqich).
  final int total;

  final Duration elapsed;

  /// Shu bosqichning ichidagi ulush, 0..1.
  double get phaseFraction =>
      total == 0 ? 0 : (done / total).clamp(0.0, 1.0).toDouble();

  /// BUTUN ishning ulushi, 0..1. Bosqichlar og'irligi [kPhaseShare] dan.
  ///
  /// O'tib ketilgan bosqichlar (masalan MIL-1 da gains/seam/blend)
  /// hisobga OLINMAYDI — ular baribir tugallangan deb qaraladi, aks
  /// holda chiziq 60 % da to'xtab qolardi.
  double get overall {
    double before = 0;
    for (final p in StitchPhase.values) {
      if (p == phase) break;
      before += kPhaseShare[p]!;
    }
    return (before + kPhaseShare[phase]! * phaseFraction)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  /// Isolate chegarasidan o'tadigan shakl — faqat primitivlar.
  Map<String, Object?> toMap() => <String, Object?>{
    'phase': phase.name,
    'done': done,
    'total': total,
    'elapsedMs': elapsed.inMilliseconds,
  };

  static PanoProgress fromMap(Map<String, Object?> m) => PanoProgress(
    phase: StitchPhase.values.firstWhere(
      (p) => p.name == m['phase'],
      // Noma'lum bosqich kelsa YIQILMAYDI: progress ko'rsatkichi
      // tikishni to'xtatishga arzimaydi.
      orElse: () => StitchPhase.project,
    ),
    done: (m['done'] as num?)?.toInt() ?? 0,
    total: (m['total'] as num?)?.toInt() ?? 0,
    elapsed: Duration(milliseconds: (m['elapsedMs'] as num?)?.toInt() ?? 0),
  );

  @override
  String toString() =>
      'PanoProgress(${phase.name} $done/$total, '
      '${(overall * 100).toStringAsFixed(0)}%)';
}
