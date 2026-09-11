# pet_engine_v2

Новое поколение игрового движка `pet_engine`: трёхмерные сцены формата
`model_v1` с публичным API в стиле Flutter — виджет `SceneViewport` плюс
контроллеры (`SceneController`, `CameraController`) и живые ноды
(`SceneNode`).

Движок пишется параллельно с v1 и не ломает существующие проекты. План,
идея и фазы работ — в [docs/plan.md](docs/plan.md).

## Состав репозитория

| Каталог | Назначение | Статус |
|---|---|---|
| `engine/` | пакет `pet_engine_v2`: движок | фаза 2: реализация API |
| `demo/` | приложение-пример: все возможности движка, документация кодом | фаза 3 |
| `scene_editor/` | редактор сцен на API v2 | фаза 4 |
| `docs/` | единая база знаний | ведётся с фазы 0 |
| `projects/` | проекты сцен и ресурсы (Pet, биомы) | скопированы из v1 |
| `scripts/` | staging ассетов, perf, служебные скрипты | перенесены из v1 |
| `temp/` | временные файлы (в git не попадают) | — |

Общий форк `flutter_scene` живёт отдельно: `../flutter_scene` (собственный
git-репозиторий, общий для v1, v2 и проектов).

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
cd ../flutter_scene/packages/flutter_scene
fvm flutter test

# staging ресурсов demo (из корня репозитория, когда появится demo)
fvm dart run scripts/stage_app_assets.dart
```

## Документы

- [docs/plan.md](docs/plan.md) — идея, интерпретация, фазы.
- [docs/features.md](docs/features.md) — реестр фич с примерами и ссылками.
- [docs/architecture.md](docs/architecture.md) — устройство движка.
- [docs/api.md](docs/api.md) — публичный API.
- [docs/migration.md](docs/migration.md) — переход с v1.
- [docs/conventions.md](docs/conventions.md) — священные конвенции.

## Правила

- Старый репозиторий v1 (`../pet_engine`) заморожен и не переписывается.
- Временные файлы — только в `temp/`.
- Коммиты — только по явной просьбе владельца, сообщения на русском.
