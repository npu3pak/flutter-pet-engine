import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Диплинки схемы `pet-engine-example`: передаём URL в Dart-код.
  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      DeeplinkBridge.shared.receive(url)
    }
    super.application(application, open: urls)
  }
}
