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
    case "requestCurrentStats":
      result(SteamBridge.requestCurrentStats())
    case "getAchievement":
      guard
        let arguments = call.arguments as? [String: Any],
        let achievementIdValue = arguments["achievementId"],
        let achievementId = FlutterSteamworksPlugin.nonEmptyString(from: achievementIdValue)
      else {
        result(FlutterError(code: "invalid-argument", message: "achievementId is required", details: nil))
        return
      }

      var unlocked = ObjCBool(false)
      let ok = SteamBridge.getAchievementWithId(achievementId, unlocked: &unlocked)
      result(ok ? unlocked.boolValue : false)
    case "setAchievement":
      guard
        let arguments = call.arguments as? [String: Any],
        let achievementIdValue = arguments["achievementId"],
        let achievementId = FlutterSteamworksPlugin.nonEmptyString(from: achievementIdValue)
      else {
        result(FlutterError(code: "invalid-argument", message: "achievementId is required", details: nil))
        return
      }
      result(SteamBridge.setAchievementWithId(achievementId))
    case "clearAchievement":
      guard
        let arguments = call.arguments as? [String: Any],
        let achievementIdValue = arguments["achievementId"],
        let achievementId = FlutterSteamworksPlugin.nonEmptyString(from: achievementIdValue)
      else {
        result(FlutterError(code: "invalid-argument", message: "achievementId is required", details: nil))
        return
      }
      result(SteamBridge.clearAchievement(withId: achievementId))
    case "storeStats":
      result(SteamBridge.storeStats())
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

  static func nonEmptyString(from value: Any) -> String? {
    if let string = value as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return string
    }
    return nil
  }
}
