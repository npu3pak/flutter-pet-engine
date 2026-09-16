# pet_engine

Игровой движок `pet_engine`: трёхмерные сцены формата `model_v1` с публичным
API в стиле Flutter — виджет `SceneViewport` плюс контроллеры
(`SceneController`, `CameraController`) и живые ноды (`SceneNode`).

Движок пришёл на смену v1 (каталог v1 удалён; история — репозиторий
`npu3pak/flutter-pet-engine`). План, идея и фазы работ — в
[docs/plan.md](docs/plan.md).

## Состав репозитория

| Каталог | Назначение | Статус |
|---|---|---|
| `engine/` | пакет `pet_engine`: движок | фаза 2: реализация API |
| `demo/` | приложение-пример: все возможности движка, документация кодом | фаза 3 |
| `docs/` | единая база знаний | ведётся с фазы 0 |
| `engine/third_party/flutter_scene` | общий форк `flutter_scene` | вложен в движок, без своего git |
| `demo/assets/` | проекты сцен (Pet, House) и шейдеры; читаются из бандла | в git, самостоятельные |
| `scripts/` | чистка пакетов, perf-скрипты | — |
| `temp/` | временные файлы (в git не попадают) | — |

Общий форк `flutter_scene` лежит внутри движка:
`engine/third_party/flutter_scene` — обычный каталог, без вложенного
git-репозитория (общий для движка и проектов через path-зависимость).

Редактор сцен вынесен из репозитория в `../pet_engine_scene_editor`
(фаза 4, API v2); его история осталась в этом репозитории.

## Команды

Flutter master через FVM (`.fvmrc`); всегда с префиксом `fvm`, из каталога
пакета.

```bash
# движок
cd engine
fvm flutter pub get
fvm flutter analyze
fvm flutter test

# форк (после правок)
cd third_party/flutter_scene/packages/flutter_scene
fvm flutter test

# demo (исходники проектов — в demo/assets, отдельный staging не нужен)
cd demo && fvm flutter run -d macos --enable-flutter-gpu --enable-impeller
```

## Документы

- [docs/plan.md](docs/plan.md) — идея, интерпретация, фазы.
- [docs/features.md](docs/features.md) — реестр фич с примерами и ссылками.
- [docs/architecture.md](docs/architecture.md) — устройство движка.
- [docs/api.md](docs/api.md) — публичный API.
- [docs/migration.md](docs/migration.md) — переход с v1.
- [docs/conventions.md](docs/conventions.md) — священные конвенции.

## Правила

- Временные файлы — только в `temp/`.
- Коммиты — только по явной просьбе владельца, сообщения на русском.
