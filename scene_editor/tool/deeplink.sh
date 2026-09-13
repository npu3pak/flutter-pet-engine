#!/usr/bin/env bash
# Диплинки редактора на macOS: открытие проекта/модели и снимки экрана.
#
# Использование:
#   tool/deeplink.sh model <путь-проекта> [id=<модель>]
#   tool/deeplink.sh shot <имя> [delay=мс] [region=window|viewport] [scale=число]
#   tool/deeplink.sh capture <путь-проекта> <id-модели> <имя> [delay=…] [region=…]
#   tool/deeplink.sh screen <start|about>
#   tool/deeplink.sh settings gizmos=1 ssao=0 ambient=1.0
#
# Примеры:
#   tool/deeplink.sh model ../projects/Pet id=model_1
#   tool/deeplink.sh capture ../projects/Pet model_1 pet_viewport region=viewport delay=3000
#
# Снимки складываются в <рабочая область>/temp/screenshots; команда
# shot/capture ждёт появления файла и печатает путь к PNG.

set -euo pipefail

SCHEME="pet-scene-editor"
BUNDLE_ID="ru.safronov.sceneeditor"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SHOTS_DIR="$(cd "$REPO_ROOT/.." && pwd)/temp/screenshots"
APP_PATH="$REPO_ROOT/scene_editor/build/macos/Build/Products/Debug/Scene Editor.app"

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
  model)
    shift
    project="${1:?Укажите путь к проекту}"
    shift || true
    send_url "$SCHEME://model?$(build_query "project=$project" "$@")"
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
    project="${1:?Укажите путь к проекту}"
    id="${2:?Укажите идентификатор модели}"
    name="${3:?Укажите имя снимка}"
    shift 3 || true
    prepare_name "$name"
    send_url "$SCHEME://capture?$(build_query "project=$project" "id=$id" "name=$name" "$@")"
    wait_screenshot "$name"
    ;;
  screen)
    shift
    name="${1:?Укажите экран: start или about}"
    send_url "$SCHEME://screen?$(build_query "name=$name")"
    ;;
  settings)
    shift
    send_url "$SCHEME://settings?$(build_query "$@")"
    ;;
  *)
    sed -n '2,18p' "${BASH_SOURCE[0]}"
    exit 1
    ;;
esac
