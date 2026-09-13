import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  /// URL, открывший приложение (холодный старт).
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    for context in connectionOptions.urlContexts {
      DeeplinkBridge.shared.receive(context.url)
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  /// URL, открытый у уже запущенного приложения (тёплый старт).
  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    for context in URLContexts {
      DeeplinkBridge.shared.receive(context.url)
    }
    super.scene(scene, openURLContexts: URLContexts)
  }
}
