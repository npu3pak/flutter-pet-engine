import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Диплинки: канал живёт до конца работы приложения.
    DeeplinkBridge.shared.attach(
      messenger: flutterViewController.engine.binaryMessenger
    )

    super.awakeFromNib()

    // Для визуальной проверки нужен крупный кадр: сцены и панели видны
    // целиком. Размер не восстанавливается, окно задаётся кодом и не
    // выходит за видимую область экрана.
    self.isRestorable = false
    let visible = (self.screen ?? NSScreen.main)?.visibleFrame
        ?? NSRect(x: 0, y: 0, width: 1400, height: 900)
    let preferredSize = NSSize(
      width: min(1400, visible.width - 20),
      height: min(900, visible.height - 80)
    )
    if self.frame.width < preferredSize.width ||
        self.frame.height < preferredSize.height {
      self.setContentSize(preferredSize)
      self.center()
    }
  }
}

/// Мост диплинков: macOS открывает приложение по схеме `pet-scene-editor`,
/// а мост передаёт URL в Dart-код. URL, пришедшие до готовности Dart-кода
/// (холодный старт), ждут в очереди и отправляются по сигналу `ready`.
final class DeeplinkBridge {
  static let shared = DeeplinkBridge()

  private var channel: FlutterMethodChannel?
  private var pending: [String] = []
  private var dartReady = false

  private init() {}

  /// Подключает канал к движку и ждёт готовности обработчика в Dart.
  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "editor/deeplink",
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
