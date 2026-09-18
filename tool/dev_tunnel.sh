#!/usr/bin/env bash
# Telefonni lokal backendga ulaydi (USB shart emas).
#
# NEGA KERAK: ilova `--dart-define=API_BASE_URL=http://localhost:8009` bilan
# yig'ilganda so'rovlar TELEFONNING localhost'iga ketadi, ularni esa
# `adb reverse` Mac'ga uzatadi. Tunnel uzilsa ilova backendni umuman
# ko'rmaydi va bu JIMGINA sodir bo'ladi — yangilanish chiqmaydi,
# bildirishnomalar ro'yxati eskiligicha qoladi. Xuddi xatodek ko'rinadi,
# aslida esa tunnel yo'q.
#
# LAN manzili (http://<mac-ip>:8009) o'rniga shu tanlangan: telefon mobil
# internetga o'tsa LAN yo'li o'ladi, simsiz adb esa bir xil Wi-Fi'da
# turgani uchun holat aniq — yo ulangan, yo yo'q.
#
# Ishlatish:  tool/dev_tunnel.sh [port]
set -euo pipefail

PORT="${1:-8009}"

# Simsiz transport (mDNS, `_adb-tls-connect._tcp`) BIRINCHI o'rinda: u USB
# uzilganda ham tirik qoladi. Telefonda "Wireless debugging" yoqilgan va bir
# marta `adb pair` qilingan bo'lishi kerak.
device="$(adb devices | awk '/_adb-tls-connect\._tcp[[:space:]]+device/ {print $1; exit}')"
kind="simsiz"

if [ -z "$device" ]; then
  device="$(adb devices | awk '$2 == "device" {print $1; exit}')"
  kind="USB"
fi

if [ -z "$device" ]; then
  echo "✗ Ulangan qurilma yo'q." >&2
  echo "  USB: kabelni ulang va telefondagi so'rovni tasdiqlang." >&2
  echo "  Simsiz: Developer options → Wireless debugging → Pair device," >&2
  echo "          so'ng: adb pair <ip>:<port> <kod>" >&2
  exit 1
fi

adb -s "$device" reverse "tcp:$PORT" "tcp:$PORT" >/dev/null

# Tunnel bor deb ishonmaymiz — TELEFONDAN so'rab tekshiramiz.
if adb -s "$device" shell curl -s --max-time 5 "http://localhost:$PORT/health" \
     2>/dev/null | grep -q '"status"'; then
  echo "✓ $kind tunnel tayyor ($device): telefon → localhost:$PORT → Mac"
else
  echo "✗ Tunnel o'rnatildi, lekin telefon backendga yeta olmadi." >&2
  echo "  Mac'da backend ishlayaptimi? curl http://localhost:$PORT/health" >&2
  exit 1
fi
