#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

packages=()
while IFS= read -r spec; do
  packages+=("$spec")
done < <(find "$ROOT" -name pubspec.yaml \
  -not -path '*/.dart_tool/*' \
  -not -path '*/build/*' \
  -not -path '*/.git/*' | sort)

if [ "${#packages[@]}" -eq 0 ]; then
  echo "pubspec.yaml не найдено"
  exit 0
fi

for spec in "${packages[@]}"; do
  dir="$(dirname "$spec")"
  echo "=== $dir ==="
  (
    cd "$dir"
    fvm flutter clean
    fvm flutter pub get
  )
done

echo "Готово: обработано ${#packages[@]} пакетов"
