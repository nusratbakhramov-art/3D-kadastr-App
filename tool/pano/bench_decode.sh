#!/usr/bin/env bash
#
# 3-qadam (MIL-0) — JPEG dekod/resize/enkod benchmarkini QURILMADA yurgizadi
# va yagona `PANOBENCH ...` qatorini ajratib chiqaradi.
#
# Reja: docs/panorama-360-plan.md §9 (3-qadam), qaror jadvali: tool/pano/README.md
#
# ⚠️ NEGA `flutter drive --profile`, `flutter test` EMAS:
#     `flutter test integration_test/...` ilovani DEBUG (JIT) da yig'adi va
#     `--profile` bayrog'ini umuman qabul qilmaydi. `package:image` sof Dart,
#     ya'ni JIT'da AOT'ga qaraganda bir necha barobar sekin. Debug raqami
#     bilan «native kanal kerak» degan xulosa chiqarish — eng qimmat xato.
#
# ⚠️ EMULYATOR/SIMULYATOR YARAMAYDI: profile rejimi ularda qo'llab
#     -quvvatlanmaydi, ustiga natija host protsessorining tezligini ko'rsatadi.
#     HAQIQIY telefon kerak.
#
# Ishlatish:
#   bash tool/pano/bench_decode.sh                     # qurilmani o'zi topadi
#   bash tool/pano/bench_decode.sh -d <device-id>
#   bash tool/pano/bench_decode.sh -j /tmp/foto.jpg    # haqiqiy 4K foto (Android: adb push)
#   bash tool/pano/bench_decode.sh --device-jpeg /sdcard/.../pano_bench.jpg
#   bash tool/pano/bench_decode.sh --debug             # faqat "yurishini" tekshirish
#
# Manba foto berilmasa test SINTETIK kadr yasaydi
# (tool/pano/gen_test_jpeg.dart) — u shovqinli, ya'ni natija PESSIMISTIK.
#
set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1

APP_ID="uz.kadastr.kadastr"
TARGET="integration_test/pano_decode_bench_test.dart"
DRIVER="integration_test/pano_bench_driver.dart"
DEVICE_DIR="/sdcard/Android/data/${APP_ID}/files"

DEVICE=""
HOST_JPEG=""
DEVICE_JPEG=""
MODE="--profile"

while [ $# -gt 0 ]; do
  case "$1" in
    -d|--device)      DEVICE="${2:-}"; shift 2 ;;
    -j|--jpeg)        HOST_JPEG="${2:-}"; shift 2 ;;
    --device-jpeg)    DEVICE_JPEG="${2:-}"; shift 2 ;;
    --debug)          MODE="--debug"; shift ;;
    -h|--help)        sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "noma'lum argument: $1"; exit 2 ;;
  esac
done

# ── 1. Qurilmalar ───────────────────────────────────────────────────────────
echo "── flutter devices ─────────────────────────────────────────────"
flutter devices 2>&1 | sed 's/^/  /'
echo

if [ -z "$DEVICE" ]; then
  # Faqat HAQIQIY telefon: emulator/simulator va desktop/web tashlanadi.
  DEVICE=$(flutter devices --machine 2>/dev/null | python3 -c '
import json, sys
try:
    devices = json.load(sys.stdin)
except ValueError:
    devices = []
real = [d for d in devices
        if not d.get("emulator", True)
        and str(d.get("targetPlatform", "")).startswith(("android-", "ios"))]
print(real[0]["id"] if len(real) == 1 else "")
')
fi

if [ -z "$DEVICE" ]; then
  echo "⚠️ Bitta ham (yoki bittadan ortiq) haqiqiy telefon topilmadi."
  echo "   Yuqoridagi ro'yxatdan tanlang:"
  echo "     bash tool/pano/bench_decode.sh -d <device-id>"
  echo "   Emulator/simulator YARAMAYDI — profile rejimi ularda yo'q."
  exit 1
fi
echo "qurilma : $DEVICE"
echo "rejim   : $MODE"

# ── 2. Manba foto (ixtiyoriy) ───────────────────────────────────────────────
DEFINES=()
if [ -n "$HOST_JPEG" ]; then
  if [ ! -f "$HOST_JPEG" ]; then
    echo "⚠️ fayl yo'q: $HOST_JPEG"; exit 1
  fi
  if command -v adb >/dev/null 2>&1 && adb -s "$DEVICE" get-state >/dev/null 2>&1; then
    echo "push    : $HOST_JPEG → $DEVICE_DIR/pano_bench.jpg"
    adb -s "$DEVICE" shell mkdir -p "$DEVICE_DIR" >/dev/null 2>&1
    if adb -s "$DEVICE" push "$HOST_JPEG" "$DEVICE_DIR/pano_bench.jpg" >/dev/null; then
      DEVICE_JPEG="$DEVICE_DIR/pano_bench.jpg"
    else
      echo "⚠️ adb push yiqildi — test SINTETIK kadrga tushadi (pessimistik)."
    fi
  else
    echo "⚠️ Bu qurilma adb orqali ko'rinmaydi (iOS?). Faylni o'zingiz"
    echo "   qurilmaga joylang va yo'lini bering:"
    echo "     bash tool/pano/bench_decode.sh --device-jpeg <qurilmadagi yo'l>"
    echo "   Hozircha SINTETIK kadr ishlatiladi (pessimistik)."
  fi
fi
if [ -n "$DEVICE_JPEG" ]; then
  DEFINES+=(--dart-define="PANO_BENCH_JPEG=$DEVICE_JPEG")
  echo "manba   : $DEVICE_JPEG"
else
  echo "manba   : sintetik (⚠️ PESSIMISTIK — haqiqiy foto tavsiya etiladi)"
fi
echo

# ── 3. Yurgizish ────────────────────────────────────────────────────────────
LOG="$(mktemp -t panobench).log"
echo "── flutter drive ───────────────────────────────────────────────"
echo "  flutter drive --driver=$DRIVER --target=$TARGET $MODE -d $DEVICE ${DEFINES[*]:-}"
echo "  log: $LOG"
echo
flutter drive \
  --driver="$DRIVER" \
  --target="$TARGET" \
  "$MODE" \
  -d "$DEVICE" \
  ${DEFINES[@]+"${DEFINES[@]}"} 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}

# ── 4. Natija ───────────────────────────────────────────────────────────────
echo
echo "── natija ──────────────────────────────────────────────────────"
# Qurilma loglari qatorga prefiks qo'shadi ("I/flutter (1234): ..."), shuning
# uchun qator boshiga emas, `PANOBENCH` so'ziga bog'lanamiz.
grep -o 'PANOBENCH_SRC .*' "$LOG" | tail -1
grep -o 'PANOBENCH_SPREAD .*' "$LOG" | tail -1
LINE=$(grep -o 'PANOBENCH decodeJpg_ms=.*' "$LOG" | tail -1)
if [ -z "$LINE" ]; then
  echo "⚠️ PANOBENCH qatori topilmadi — o'lchov olinmadi."
  echo "   To'liq log: $LOG"
  # `flutter drive` o'zi 0 qaytargan bo'lsa ham o'lchov YO'Q — bu muvaffaqiyat
  # emas, shuning uchun 1 bilan chiqamiz.
  [ "${rc:-0}" -ne 0 ] && exit "$rc"
  exit 1
fi
echo "$LINE"

DECODE=$(echo "$LINE" | sed -n 's/.*decodeJpg_ms=\([0-9]*\).*/\1/p')
echo
if [ -n "$DECODE" ] && [ "$DECODE" -le 1200 ]; then
  echo "QAROR: decodeJpg=${DECODE} ms ≤ 1200 → sof Dart dekod QOLADI,"
  echo "       4-qadam (native kadastr/pano_codec) O'TKAZILADI."
else
  echo "QAROR: decodeJpg=${DECODE} ms > 1200 → 4-qadam MAJBURIY"
  echo "       (native kadastr/pano_codec kanali)."
  echo "       ⚠️ Sintetik kadr bilan o'lchangan bo'lsa, qaror qilishdan"
  echo "          oldin HAQIQIY 4K foto bilan qayta o'lchang (-j <foto>)."
fi
echo
echo "Natijani tool/pano/README.md dagi bo'sh jadvalga yozing. Log: $LOG"
exit "${rc:-0}"
