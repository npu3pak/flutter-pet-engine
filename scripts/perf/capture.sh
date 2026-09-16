#!/usr/bin/env bash
# Снимает perf-сессию с подключённого Android-устройства (любая игра).
#
#   scripts/perf/capture.sh <tag> [seconds]
#   PERF_PKG=com.example.game scripts/perf/capture.sh <tag> [seconds]
#
# Пакет по умолчанию — com.mypet.example; переопределяется PERF_PKG.
# Каталог вывода — temp/perf/<tag>/ относительно текущего каталога.
#
# Пишет в temp/perf/<tag>/:
#   logcat.log  — весь лог процесса приложения ([perf], [pet_engine], ошибки)
#   meminfo.log — dumpsys meminfo каждые 30 с
#   thermal.log — частоты GPU/CPU, загрузка и температура GPU, батарея, uptime
#                 (каждые 5 с; uptime — для привязки к таймстампам logcat)
#
# Приложение должно быть уже запущено (flutter run --profile …).
set -euo pipefail

TAG="${1:?использование: scripts/perf/capture.sh <tag> [seconds]}"
DURATION="${2:-600}"
PKG="${PERF_PKG:-com.mypet.example}"
OUT="temp/perf/$TAG"

mkdir -p "$OUT"
: > "$OUT/logcat.log"
: > "$OUT/meminfo.log"
: > "$OUT/thermal.log"

PID=""
for _ in $(seq 1 120); do
  PID="$(adb shell pidof -s "$PKG" 2>/dev/null | tr -d '\r' || true)"
  [ -n "$PID" ] && break
  sleep 1
done
if [ -z "$PID" ]; then
  echo "Приложение $PKG не запущено" >&2
  exit 1
fi
echo "pid=$PID → $OUT (${DURATION}s)"

adb logcat --pid="$PID" -v monotonic > "$OUT/logcat.log" 2>/dev/null &
LOGCAT_PID=$!

(
  while :; do
    {
      echo -n "uptime=$(adb shell cat /proc/uptime 2>/dev/null | cut -d' ' -f1 | tr -d '\r' || true)"
      echo -n " battery=$(adb shell dumpsys battery 2>/dev/null | grep -m1 temperature | tr -d ' \r' | cut -d: -f2 || true)"
      echo -n " gpu_clock=$(adb shell cat /sys/kernel/gpu/gpu_clock 2>/dev/null | tr -d '\r' || true)"
      echo -n " gpu_max=$(adb shell cat /sys/kernel/gpu/gpu_max_clock 2>/dev/null | tr -d '\r' || true)"
      echo -n " gpu_busy=$(adb shell cat /sys/kernel/gpu/gpu_busy 2>/dev/null | tr -d ' \r%' || true)"
      echo -n " gpu_tmu=$(adb shell cat /sys/kernel/gpu/gpu_tmu 2>/dev/null | tr -d ' \r' || true)"
      echo -n " cpu7=$(adb shell cat /sys/devices/system/cpu/cpu7/cpufreq/scaling_cur_freq 2>/dev/null | tr -d '\r' || true)"
      echo
    } >> "$OUT/thermal.log"
    sleep 5
  done
) &
FREQ_PID=$!

(
  while :; do
    {
      echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
      adb shell dumpsys meminfo "$PKG" 2>/dev/null || true
    } >> "$OUT/meminfo.log"
    sleep 30
  done
) &
MEM_PID=$!

cleanup() {
  kill "$LOGCAT_PID" "$FREQ_PID" "$MEM_PID" 2>/dev/null || true
  wait "$LOGCAT_PID" "$FREQ_PID" "$MEM_PID" 2>/dev/null || true
}
trap cleanup EXIT

sleep "$DURATION"
echo "готово: $OUT"
