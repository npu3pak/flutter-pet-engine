#!/usr/bin/env bash
# Постоянная debug-сессия приложения-примера на iPad.
#
#   tool/ipad_session.sh start   — staging ресурсов и запуск сессии в фоне
#   tool/ipad_session.sh wait    — дождаться готовности (app.started)
#   tool/ipad_session.sh stop    — остановка сессии
#   tool/ipad_session.sh status  — состояние сессии
#
# Сессия — это `flutter run --machine`: команды читаются из FIFO
# temp/ipad/machine_in, события пишутся в temp/ipad/machine.log. Команды
# отправляет tool/ipad_cmd.dart, hot reload — `ipad_cmd.dart reload`.
# Устройство берётся из PET_IPAD_UDID или ищется первое iOS-устройство.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TEMP_DIR="$REPO_ROOT/temp/ipad"
FIFO="$TEMP_DIR/machine_in"
LOG="$TEMP_DIR/machine.log"
PID_FILE="$TEMP_DIR/session.pid"
HOLDER_FILE="$TEMP_DIR/holder.pid"
IPAD_UDID="${PET_IPAD_UDID:-}"

ipad_udid() {
  if [[ -z "$IPAD_UDID" ]]; then
    IPAD_UDID="$(fvm flutter devices --machine 2>/dev/null | python3 -c '
import json, sys
for device in json.load(sys.stdin):
    if str(device.get("targetPlatform", "")).startswith("ios"):
        print(device["id"], end="")
        break
')"
  fi
  if [[ -z "$IPAD_UDID" ]]; then
    echo "Не найден подключённый iPad; задайте PET_IPAD_UDID" >&2
    exit 1
  fi
}

stop_session() {
  if [[ -f "$PID_FILE" ]]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
    rm -f "$PID_FILE"
  fi
  if [[ -f "$HOLDER_FILE" ]]; then
    kill "$(cat "$HOLDER_FILE")" 2>/dev/null || true
    rm -f "$HOLDER_FILE"
  fi
}

wait_ready() {
  local timeout="${1:-300}"
  for _ in $(seq 1 "$timeout"); do
    if grep -q '"event":"app.started"' "$LOG" 2>/dev/null; then
      echo "Сессия готова"
      return 0
    fi
    if [[ -f "$PID_FILE" ]] &&
      ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
      echo "Сессия завершилась. Последние строки журнала:" >&2
      tail -20 "$LOG" >&2
      return 1
    fi
    sleep 1
  done
  echo "Таймаут ожидания app.started; смотрите $LOG" >&2
  return 1
}

command="${1:-status}"
case "$command" in
  start)
    stop_session
    mkdir -p "$TEMP_DIR"
    ipad_udid
    cd "$REPO_ROOT"
    fvm dart run scripts/stage_app_assets.dart
    cd "$REPO_ROOT/demo"
    rm -f "$FIFO" "$LOG" "$PID_FILE" "$HOLDER_FILE" "$TEMP_DIR/app_id.txt"
    mkfifo "$FIFO"

    # Сессия и «держатель» FIFO запускаются в отдельных сессиях процессов,
    # поэтому прерывание управляющей команды их не убивает.
    python3 - "$LOG" "$FIFO" fvm flutter run --machine \
      -d "$IPAD_UDID" --dart-define=pet.control=true \
      > "$PID_FILE" 2>/dev/null <<'PY' &
import subprocess, sys
log = open(sys.argv[1], 'ab')
fifo = open(sys.argv[2], 'rb')
proc = subprocess.Popen(
    sys.argv[3:],
    stdin=fifo,
    stdout=log,
    stderr=log,
    start_new_session=True,
)
print(proc.pid, flush=True)
PY
    python3 - "$FIFO" > "$HOLDER_FILE" 2>/dev/null <<'PY' &
import subprocess, sys
fifo = open(sys.argv[1], 'wb')
proc = subprocess.Popen(['sleep', '86400'], stdout=fifo, start_new_session=True)
print(proc.pid, flush=True)
PY
    for _ in $(seq 1 100); do
      [[ -s "$PID_FILE" && -s "$HOLDER_FILE" ]] && break
      sleep 0.1
    done
    if [[ ! -s "$PID_FILE" || ! -s "$HOLDER_FILE" ]]; then
      echo "Не удалось запустить сессию; смотрите $LOG" >&2
      exit 1
    fi
    echo "Сессия запускается; готовность: tool/ipad_session.sh wait"
    ;;
  wait)
    shift || true
    wait_ready "${1:-300}"
    ;;
  stop)
    stop_session
    echo "Сессия остановлена"
    ;;
  status)
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
      if grep -q '"event":"app.started"' "$LOG" 2>/dev/null; then
        echo "Сессия работает и готова (pid $(cat "$PID_FILE"))"
      else
        echo "Сессия запускается (pid $(cat "$PID_FILE"))"
      fi
    else
      echo "Сессия не запущена"
    fi
    ;;
  *)
    sed -n '2,13p' "${BASH_SOURCE[0]}"
    exit 1
    ;;
esac
