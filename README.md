# pet_engine

Движок нового поколения для трёхмерных сцен `model_v1`/`project_v1`:
документ, рендер, ресурсы, уровневый слой, навигация, частицы. Публичный
API в стиле Flutter — виджет `SceneViewport`, контроллеры
(`SceneController`, `CameraController`) и живые ноды (`SceneNode`).

Пакет вырос из кода v1 (`pet_engine` 0.5.0); старые фасады
(`GameScene`, `EngineSceneView`, ...) с фазы 5 удалены. История v1 —
репозиторий `npu3pak/flutter-pet-engine`.

## Состав репозитория

| Каталог | Назначение | Статус |
|---|---|---|
| `lib/` | код пакета `pet_engine` | фаза 2: API реализован |
| `example/` | приложение-пример: все возможности движка, документация кодом | фаза 3 |
| `docs/` | единая база знаний | ведётся с фазы 0 |
| `third_party/flutter_scene` | общий форк `flutter_scene` | вложен в движок, без своего git |
| `example/assets/` | проекты сцен (Pet, House) и шейдеры; читаются из бандла | в git, самостоятельные |
| `scripts/` | чистка пакетов, perf-скрипты | — |
| `temp/` | временные файлы (в git не попадают) | — |

Общий форк `flutter_scene` лежит внутри движка:
`third_party/flutter_scene` — обычный каталог, без вложенного
git-репозитория (общий для движка и проектов через path-зависимость).

Редактор сцен вынесен из репозитория в `../pet_engine_scene_editor`
(фаза 4, API v2); его история осталась в этом репозитории.

Публичные входы пакета:

- `package:pet_engine/pet_engine.dart` — движок целиком;
- `package:pet_engine/models.dart` — только типы документа;
- `package:pet_engine/build_hooks.dart` — обёртка сборки для hook-ов
  приложений (`petBuildMaterials`).

## Команды

Flutter master через FVM (`.fvmrc`); всегда с префиксом `fvm`.

```bash
# движок (из корня репозитория)
fvm flutter pub get
fvm flutter analyze
fvm flutter test

# форк (после правок)
cd third_party/flutter_scene/packages/flutter_scene
fvm flutter test

# example (исходники проектов — в example/assets, отдельный staging не нужен)
cd example && fvm flutter run -d macos --enable-flutter-gpu --enable-impeller
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
