import Cocoa
import FlutterMacOS

public class FlutterSteamworksPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_steamworks", binaryMessenger: registrar.messenger)
    let instance = FlutterSteamworksPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
    case "initSteam":
      guard
        let arguments = call.arguments as? [String: Any],
        let appIdValue = arguments["appId"],
        let appIdString = FlutterSteamworksPlugin.appIdString(from: appIdValue)
      else {
        result(FlutterError(code: "invalid-argument", message: "App ID is required", details: nil))
        return
      }

      let success = SteamBridge.initSteam(withAppId: appIdString)
      result(success)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

private extension FlutterSteamworksPlugin {
  static func appIdString(from value: Any) -> String? {
    if let string = value as? String, !string.isEmpty {
      return string
    }

    if let number = value as? NSNumber {
      return number.stringValue
    }

    return nil
  }
}
