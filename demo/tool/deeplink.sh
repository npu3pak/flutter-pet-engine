#!/usr/bin/env bash
# Диплинки приложения-примера на macOS: открытие сцен и снимки экрана.
#
# Использование:
#   tool/deeplink.sh scene <фича> [ключ=значение …]
#   tool/deeplink.sh shot <имя> [delay=мс] [region=window|viewport] [scale=число]
#   tool/deeplink.sh capture <фича> <имя> [ключ=значение …] [delay=…] [region=…]
#   tool/deeplink.sh screen <checklist|about>
#
# Примеры:
#   tool/deeplink.sh scene rounded_box radius=0.4 segments=24
#   tool/deeplink.sh shot rounded_box_r04 delay=3000
#   tool/deeplink.sh capture weather_rain rain_default delay=3000
#
# Снимки складываются в <рабочая область>/temp/screenshots; команда
# shot/capture ждёт появления файла и печатает путь к PNG.
# Для iPad используйте постоянную debug-сессию: tool/ipad_session.sh и
# tool/ipad_cmd.dart.

set -euo pipefail

SCHEME="pet-engine-example"
BUNDLE_ID="com.mypet.demo"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SHOTS_DIR="$(cd "$REPO_ROOT/.." && pwd)/temp/screenshots"
APP_PATH="$REPO_ROOT/demo/build/macos/Build/Products/Debug/demo.app"

send_url() {
  local url="$1"
  if [[ -d "$APP_PATH" ]]; then
    open -a "$APP_PATH" "$url"
  else
    open -b "$BUNDLE_ID" "$url"
  fi
}

build_query() {
  local query=""
  for kv in "$@"; do
    if [[ -z "$query" ]]; then
      query="$kv"
    else
      query="$query&$kv"
    fi
  done
  printf '%s' "$query"
}

prepare_name() {
  local name="$1"
  mkdir -p "$SHOTS_DIR"
  rm -f "$SHOTS_DIR/$name.json" "$SHOTS_DIR/$name.png"
}

wait_screenshot() {
  local name="$1"
  local png="$SHOTS_DIR/$name.png"
  local sidecar="$SHOTS_DIR/$name.json"
  local deadline=$((SECONDS + 180))
  while (( SECONDS < deadline )); do
    if [[ -f "$sidecar" ]]; then
      printf '%s\n' "$png"
      return 0
    fi
    sleep 0.3
  done
  echo "Таймаут ожидания снимка: $name" >&2
  return 1
}

command="${1:-}"
case "$command" in
  scene)
    shift
    id="${1:?Укажите идентификатор фичи}"
    shift || true
    send_url "$SCHEME://scene?$(build_query "id=$id" "$@")"
    ;;
  shot)
    shift
    name="${1:?Укажите имя снимка}"
    shift || true
    prepare_name "$name"
    send_url "$SCHEME://screenshot?$(build_query "name=$name" "$@")"
    wait_screenshot "$name"
    ;;
  capture)
    shift
    id="${1:?Укажите идентификатор фичи}"
    name="${2:?Укажите имя снимка}"
    shift 2 || true
    prepare_name "$name"
    send_url "$SCHEME://capture?$(build_query "id=$id" "name=$name" "$@")"
    wait_screenshot "$name"
    ;;
  screen)
    shift
    name="${1:?Укажите экран: checklist или about}"
    send_url "$SCHEME://screen?$(build_query "name=$name")"
    ;;
  *)
    sed -n '2,18p' "${BASH_SOURCE[0]}"
    exit 1
    ;;
esac
