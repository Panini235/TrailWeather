import Flutter
import UIKit

/// 山晴 iOS 入口。在 Flutter 3.47.7 模板基础上增加“用山晴打开”：
/// 从文件、微信、两步路等 App 打开 GPX / KML / KMZ 时，复制到 App 临时目录，
/// 经 `trailweather/incoming_file` 通道交给 Dart（与 Android MainActivity.kt 同一协议）。
/// 本文件提交入库；CI 中 `flutter create` 不覆盖已存在的文件。
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let channelName = "trailweather/incoming_file"
  private static let maxBytes = 30 * 1024 * 1024

  private var incomingChannel: FlutterMethodChannel?

  /// 冷启动时 Dart 尚未监听，文件先存这里，由 getInitialFile 取走。
  private var pendingFile: [String: String]?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ShanqingIncomingFile")
    else { return }
    let channel = FlutterMethodChannel(
      name: AppDelegate.channelName, binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "getInitialFile":
        result(self.pendingFile)
        self.pendingFile = nil
      case "readBytes":
        guard let args = call.arguments as? [String: Any],
          let uri = args["uri"] as? String,
          let url = URL(string: uri)
        else {
          result(FlutterError(code: "bad_args", message: "missing uri", details: nil))
          return
        }
        DispatchQueue.global(qos: .userInitiated).async {
          let outcome: Any
          do {
            let data = try Data(contentsOf: url)
            outcome =
              data.count > AppDelegate.maxBytes
              ? FlutterError(code: "too_large", message: "文件超过 30 MB 大小限制", details: nil)
              : FlutterStandardTypedData(bytes: data)
          } catch {
            outcome = FlutterError(
              code: "read_failed", message: error.localizedDescription, details: nil)
          }
          DispatchQueue.main.async { result(outcome) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    incomingChannel = channel
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    guard url.isFileURL, let file = copyIncoming(url) else {
      return super.application(app, open: url, options: options)
    }
    pendingFile = file
    // App 已在运行：直接通知 Dart；Dart 确认收到后清掉 pending，避免冷启动时再取一次。
    incomingChannel?.invokeMethod("onFile", arguments: file) { [weak self] reply in
      if !(reply is FlutterError) && (reply as AnyObject?) !== FlutterMethodNotImplemented {
        self?.pendingFile = nil
      }
    }
    return true
  }

  /// 外部文件可能位于其他 App 的沙盒（LSSupportsOpeningDocumentsInPlace），
  /// 需在安全作用域内复制一份到本 App 临时目录再读取。
  private func copyIncoming(_ url: URL) -> [String: String]? {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("incoming", isDirectory: true)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let dest = dir.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
    do {
      try fm.copyItem(at: url, to: dest)
    } catch {
      return nil
    }
    return ["uri": dest.absoluteString, "name": url.lastPathComponent]
  }
}
