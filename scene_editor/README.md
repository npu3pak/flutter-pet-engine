# scene_editor — редактор сцен pet_engine_v2

Редактор `pet_engine/tools/scene_editor`, переписанный на публичный API
`pet_engine_v2` (`SceneViewport`/`SceneController`/`SceneNode`). Целится в
macOS и iPadOS.

Назначение:

- создание и редактирование сцен формата `model_v1` и проектов
  `project_v1` на macOS и iPadOS;
- документ с отменой действий, панели свойств, ресурсы, шаблоны;
- трёхмерный вьюпорт: выделение объектов и граней, гизмо, оверлеи,
  служебные слои;
- разметка уровня: входы, двери, мета-объекты.

Правила:

- здесь важнее оптимизация, чем наглядность;
- редактор использует те же контроллер и ноды, что и игры, плюс
  низкоуровневые точки входа API (слои, picking, произвольная геометрия);
- потребности редактора, не покрытые API, возвращаются в движок (фаза 2),
  а не обходятся локальными копиями.

## Запуск

Flutter **master** через FVM (`.fvmrc`); команды из каталога `scene_editor`.

```bash
fvm flutter pub get
fvm flutter analyze
fvm flutter test
fvm flutter run -d macos --enable-flutter-gpu --enable-impeller
```

Ресурсы редактора для iPad собираются из корня репозитория:

```bash
fvm dart run scripts/stage_app_assets.dart --full --out scene_editor/assets/pet_project
```

## Визуальные проверки

На macOS диплинки и снимки — `tool/deeplink.sh` (схема
`pet-scene-editor`, канал `editor/deeplink`):

```bash
tool/deeplink.sh model ../projects/Pet id=model_2 mode=markup select=meta_1
tool/deeplink.sh settings gizmos=1
tool/deeplink.sh settings grid=0
tool/deeplink.sh shot my_check delay=4000
tool/deeplink.sh capture ../projects/Pet model_2 my_check region=viewport
```

Снимки складываются в `temp/screenshots`; журнал проверок —
`visual_tests.json` (`note`/`fixed` пишет агент, вердикт `ok` — владелец).

## Устройство

- `lib/src/state/app_state.dart` — документ, undo/redo (стеки на модель,
  слияние быстрых правок), выбор, режимы; документ живёт в
  `SceneController`, пересборка по ревизии.
- `lib/src/scene/editor_scene.dart` — оверлеи (сетка, рамка, курсор,
  контуры, гизмо), picking через `SceneController.raycast` с `FaceRef`,
  меты, маркеры света, камера на `FlyCameraController`.
- `lib/src/services/` — ресурсы (`ResourceStore`), каталог `3d_models/`
  (`Model3dStore`), шаблоны дома/комнаты, обработка изображений.
- `lib/src/ui/` — панели, вкладки, вьюпорт, просмотрщик моделей.
