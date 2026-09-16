import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    #if DEBUG
    // Во время автоматического прогона экран iPad не должен гаснуть.
    application.isIdleTimerDisabled = true
    #endif
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let messenger = engineBridge.pluginRegistry
      .registrar(forPlugin: "DeeplinkBridge")?.messenger() {
      DeeplinkBridge.shared.attach(messenger: messenger)
    }
  }
}

/// Мост диплинков на iOS: система открывает приложение по схеме
/// `pet-engine-example`, мост передаёт URL в Dart-код. URL, пришедшие до
/// готовности Dart-кода (холодный старт), ждут в очереди и отправляются по
/// сигналу `ready`.
final class DeeplinkBridge {
  static let shared = DeeplinkBridge()

  private var channel: FlutterMethodChannel?
  private var pending: [String] = []
  private var dartReady = false

  private init() {}

  /// Подключает канал к движку и ждёт готовности обработчика в Dart.
  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "example/deeplink",
      binaryMessenger: messenger
    )
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      if call.method == "ready" {
        self.dartReady = true
        self.flushPending()
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Принимает URL от системы.
  func receive(_ url: URL) {
    let absolute = url.absoluteString
    if let channel, dartReady {
      channel.invokeMethod("open", arguments: absolute)
    } else {
      pending.append(absolute)
    }
  }

  private func flushPending() {
    guard let channel else { return }
    for url in pending {
      channel.invokeMethod("open", arguments: url)
    }
    pending.removeAll()
  }
}
