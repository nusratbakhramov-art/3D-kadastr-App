#!/usr/bin/env bash
#
# 13-qadam (MIL-1) — kadrlarni QURILMADA tikib vaqtni o'lchaydi va yagona
# `PANOSTITCH ...` qatorini ajratib chiqaradi.
#
# Reja: docs/panorama-360-plan.md §9 (13-qadam). Bu BUTUN YONDASHUVNING
# qaror darvozasi: sof Dart bilan 76 kadrli panorama telefonda tikiladimi.
#
# ⚠️ QAROR `extrapolated76_s` GA QARAB QABUL QILINADI, `measured_ms` ga EMAS.
#     Bu bosqichda gains (14), seam (15) va blend (16) hali yozilmagan, ya'ni
#     o'lchov yakuniy quvurning atigi ~56 %ini ko'radi. Xom raqamga qarash
#     «GO» ni qariyb ikki barobar optimistik qilardi.
#
# ⚠️ NEGA `flutter drive --profile`: butun quvur sof Dart va JIT'da bir necha
#     barobar sekin. `flutter test integration_test/...` ilovani DEBUG da
#     yig'adi — u raqam bilan qaror qabul qilib bo'lmaydi.
#
# ⚠️ EMULYATOR/SIMULYATOR YARAMAYDI — natija host protsessorini ko'rsatadi.
#
# Ishlatish:
#   bash tool/pano/bench_stitch.sh -f ~/Desktop/kadrlar    # host papkasi (Android: adb push)
#   bash tool/pano/bench_stitch.sh -d <device-id> -f <papka>
#   bash tool/pano/bench_stitch.sh --device-dir <qurilmadagi yo'l>
#   bash tool/pano/bench_stitch.sh --debug                 # faqat "yurishini" tekshirish
#
# Kadr fayllari `y<yaw>_p<pitch>.jpg` deb nomlanishi SHART, masalan:
#   y000_p0.jpg  y045_p0.jpg  y090_p0.jpg ...
# Burchaklar shu nomlardan o'qiladi (capture ekrani hali yo'q).
#
set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1

APP_ID="uz.kadastr.kadastr"
TARGET="integration_test/pano_stitch_bench_test.dart"
DRIVER="integration_test/pano_bench_driver.dart"
DEVICE_DIR="/sdcard/Android/data/${APP_ID}/files/pano_frames"

DEVICE=""
HOST_DIR=""
REMOTE_DIR=""
MODE="--profile"

while [ $# -gt 0 ]; do
  case "$1" in
    -d|--device)     DEVICE="${2:-}"; shift 2 ;;
    -f|--frames)     HOST_DIR="${2:-}"; shift 2 ;;
    --device-dir)    REMOTE_DIR="${2:-}"; shift 2 ;;
    --debug)         MODE="--debug"; shift ;;
    -h|--help)       sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "noma'lum argument: $1"; exit 2 ;;
  esac
done

# ── 1. Qurilma ──────────────────────────────────────────────────────────────
echo "── flutter devices ─────────────────────────────────────────────"
flutter devices 2>&1 | sed 's/^/  /'
echo

if [ -z "$DEVICE" ]; then
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
  echo "     bash tool/pano/bench_stitch.sh -d <device-id> -f <papka>"
  echo "   Emulator/simulator YARAMAYDI — profile rejimi ularda yo'q."
  exit 1
fi
echo "qurilma : $DEVICE"
echo "rejim   : $MODE"

# ── 2. Kadrlarni qurilmaga ko'chirish ───────────────────────────────────────
DEFINES=()
if [ -n "$HOST_DIR" ]; then
  if [ ! -d "$HOST_DIR" ]; then
    echo "⚠️ papka yo'q: $HOST_DIR"; exit 1
  fi
  N=$(find "$HOST_DIR" -maxdepth 1 -type f 2>/dev/null \
      | grep -cE 'y-?[0-9.]+_p-?[0-9.]+\.(jpg|jpeg|JPG|JPEG)$')
  if [ "$N" -lt 2 ]; then
    echo "⚠️ $HOST_DIR ichida 'y<yaw>_p<pitch>.jpg' ko'rinishidagi kadr topilmadi ($N ta)."
    echo "   Masalan: y000_p0.jpg  y045_p0.jpg  y090_p0.jpg"
    exit 1
  fi
  echo "kadrlar : $N ta"
  if command -v adb >/dev/null 2>&1 && adb -s "$DEVICE" get-state >/dev/null 2>&1; then
    echo "push    : $HOST_DIR → $DEVICE_DIR"
    adb -s "$DEVICE" shell mkdir -p "$DEVICE_DIR" >/dev/null 2>&1
    # Eski kadrlar qolib ketmasin — aks holda o'lchov boshqa to'plamniki
    # bo'lib chiqadi va buni sezish qiyin.
    adb -s "$DEVICE" shell "rm -f $DEVICE_DIR/*" >/dev/null 2>&1
    if adb -s "$DEVICE" push "$HOST_DIR/." "$DEVICE_DIR" >/dev/null; then
      REMOTE_DIR="$DEVICE_DIR"
    else
      echo "⚠️ adb push yiqildi."; exit 1
    fi
  else
    echo "⚠️ Bu qurilma adb orqali ko'rinmaydi (iOS?). Kadrlarni o'zingiz"
    echo "   qurilmaga joylang va papka yo'lini bering:"
    echo "     bash tool/pano/bench_stitch.sh --device-dir <qurilmadagi papka>"
    exit 1
  fi
fi
if [ -n "$REMOTE_DIR" ]; then
  DEFINES+=(--dart-define="PANO_STITCH_DIR=$REMOTE_DIR")
  echo "manba   : $REMOTE_DIR"
else
  echo "manba   : qurilmaning o'z papkasi (pano_frames)"
fi
echo

# ── 3. Yurgizish ────────────────────────────────────────────────────────────
LOG="$(mktemp -t panostitch).log"
echo "── flutter drive ───────────────────────────────────────────────"
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
grep -o 'PANOSTITCH bosqich=.*' "$LOG" | sed 's/^/  /'
LINE=$(grep -o 'PANOSTITCH frames=.*' "$LOG" | tail -1)
if [ -z "$LINE" ]; then
  echo "⚠️ PANOSTITCH qatori topilmadi — o'lchov olinmadi."
  grep -o 'PANOSTITCH xato=.*' "$LOG" | tail -1 | sed 's/^/  /'
  echo "   To'liq log: $LOG"
  [ "${rc:-0}" -ne 0 ] && exit "$rc"
  exit 1
fi
echo "$LINE"
grep -o 'PANOSTITCH_NOTE .*' "$LOG" | tail -1 | fold -s -w 72 | sed 's/^/  /'
echo

VERDICT=$(echo "$LINE" | grep -o 'verdict=[A-Z]*' | cut -d= -f2)
EXTRA=$(echo "$LINE" | grep -o 'extrapolated76_s=[0-9]*' | cut -d= -f2)
if [ "$VERDICT" = "GO" ]; then
  echo "✅ GO — 76 kadr uchun ~${EXTRA}s (chegara 120s). Sof Dart yetadi."
  echo "   Keyingi qadamlar: 14 (gains) → 15 (seam) → 16 (blend)."
else
  echo "❌ NO — 76 kadr uchun ~${EXTRA}s, 120s chegarasidan oshadi."
  echo "   Variantlar: kadr sonini kamaytirish (76 → 40), tuvalni"
  echo "   kichraytirish (3072 → 2048), yoki proyeksiyani isolate'larga"
  echo "   bo'lish (horizontalSlices allaqachon tayyor)."
fi
echo "   To'liq log: $LOG"
exit 0
