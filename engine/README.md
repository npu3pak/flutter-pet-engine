# pet_engine

Движок нового поколения для трёхмерных сцен `model_v1`/`project_v1`:
документ, рендер, ресурсы, уровневый слой, навигация, частицы. Публичный API
нового поколения — `SceneViewport` (виджет), `SceneController` (контроллер),
`SceneNode` (живые ноды) — проектируется в фазе 1 и реализуется в фазе 2.

Пакет вырос из кода v1 (`pet_engine` 0.5.0); старые фасады
(`GameScene`, `EngineSceneView`, ...) с фазы 5 удалены.

- Идея и фазы: [`../docs/plan.md`](../docs/plan.md)
- Архитектура: [`../docs/architecture.md`](../docs/architecture.md)
- API: [`../docs/api.md`](../docs/api.md)
- Конвенции: [`../docs/conventions.md`](../docs/conventions.md)

```bash
fvm flutter pub get
fvm flutter analyze
fvm flutter test
```

Публичные входы пакета:

- `package:pet_engine/pet_engine.dart` — движок целиком (пока это
  перенесённый v1-набор);
- `package:pet_engine/models.dart` — только типы документа;
- `package:pet_engine/build_hooks.dart` — обёртка сборки для hook-ов
  приложений (`petBuildMaterials`).
