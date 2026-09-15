#!/usr/bin/env bash
#
# Regressiya bazasi — "buzdikmi?" savoliga bitta raqam bilan javob beradi.
#
# 360° panorama ishi (docs/panorama-360-plan.md) 23 qadamdan iborat va har
# qadamdan keyin shu skript yurgiziladi. Chiqishdagi ikki qator oldingisi
# bilan solishtiriladi.
#
# NEGA ODDIY `flutter test` EMAS:
#   `test/features/auth/otp_step_test.dart :: wrong code shows error toast`
#   596 sekund ishlaydi va timeout bilan tugaydi. Ya'ni butun to'plam ~600 s
#   oladi va uning 99 %i bitta osilgan testga ketadi. Shu fayl CHETLAB
#   O'TILADI (pastdagi ogohlantirishga qarang).
#
#   Bundan tashqari `flutter test` ning odatiy chiqishi yiqilganlar sonini
#   ishonchli bermaydi (yiqilish matni orasida yo'qoladi), shuning uchun
#   `--reporter json` va `testDone` hodisalari sanaladi.
#
# Ishlatish:
#   bash tool/pano/baseline.sh              # analyze + test
#   bash tool/pano/baseline.sh --analyze    # faqat analyze (tez)
#   bash tool/pano/baseline.sh --tests      # faqat test
#
# Chiqish (2026-09-10 dagi baza):
#   analyze: 27 issues (0 error, 4 warning)
#   tests: testDone=282 success=266 fail=16
#
# To'liq yugurish ~18 s (otp fayli bilan ~600 s bo'lardi).
#
set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1

MODE="${1:-all}"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

# ── analyze ─────────────────────────────────────────────────────────────────
run_analyze() {
  flutter analyze >"$OUT/analyze.txt" 2>&1
  local total error warning
  total=$(grep -cE '•' "$OUT/analyze.txt" || true)
  error=$(grep -E '^\s*error •' "$OUT/analyze.txt" | wc -l | tr -d ' ')
  warning=$(grep -E '^\s*warning •' "$OUT/analyze.txt" | wc -l | tr -d ' ')
  echo "analyze: ${total} issues (${error} error, ${warning} warning)"
  # Xato BO'LMASLIGI shart — warning va info baza bilan solishtiriladi.
  if [ "$error" != "0" ]; then
    echo "  ⚠️ ERROR bor — quyida:"
    grep -E '^\s*error •' "$OUT/analyze.txt" | sed 's/^/  /'
    return 1
  fi
  return 0
}

# ── test ────────────────────────────────────────────────────────────────────
# `otp_step_test.dart` dan boshqa hamma test fayli. Ro'yxat HAR SAFAR qayta
# tuziladi, ya'ni yangi test fayli qo'shilsa o'zi qamrab olinadi.
run_tests() {
  local files
  files=$(find test -name '*_test.dart' | grep -v 'otp_step_test' | sort)
  if [ -z "$files" ]; then
    echo "tests: test fayli topilmadi"
    return 1
  fi
  # shellcheck disable=SC2086
  flutter test $files --reporter json >"$OUT/tests.json" 2>"$OUT/tests.err"

  python3 - "$OUT/tests.json" <<'PYEOF'
import json, sys

tests = {}
for line in open(sys.argv[1], encoding='utf-8'):
    line = line.strip()
    if not line.startswith('{'):
        continue
    try:
        e = json.loads(line)
    except ValueError:
        continue
    t = e.get('type')
    if t == 'testStart':
        tests[e['test']['id']] = None
    elif t == 'testDone':
        # `hidden` — guruh/`setUpAll` kabi ichki yozuvlar, sanoqqa kirmaydi.
        if e.get('hidden'):
            tests.pop(e['testID'], None)
        elif e['testID'] in tests:
            tests[e['testID']] = (e.get('result') == 'success'
                                  and not e.get('skipped'))

total = len(tests)
ok = sum(1 for v in tests.values() if v)
fail = sum(1 for v in tests.values() if v is False)
print('tests: testDone=%d success=%d fail=%d' % (total, ok, fail))
PYEOF
}

rc=0
case "$MODE" in
  --analyze) run_analyze || rc=1 ;;
  --tests)   run_tests   || rc=1 ;;
  *)         run_analyze || rc=1; run_tests || rc=1 ;;
esac
exit "$rc"
