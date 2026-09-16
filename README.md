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

- [docs/api.md](docs/api.md) — публичный API: `SceneViewport`,
  `SceneController`, `SceneNode` и механизмы.
- [docs/architecture.md](docs/architecture.md) — устройство движка.
- [docs/features.md](docs/features.md) — реестр фич с примерами и ссылками.
- [docs/conventions.md](docs/conventions.md) — священные конвенции.
- [docs/visual_testing.md](docs/visual_testing.md) — методика визуальных
  проверок.
- [docs/perf_journal.md](docs/perf_journal.md) — замеры производительности.
- [CHANGELOG.md](CHANGELOG.md) — история версий и фич.

## Правила

- Временные файлы — только в `temp/`.
- Коммиты — только по явной просьбе владельца, сообщения на русском.
