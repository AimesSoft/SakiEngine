
import 'flutter_steamworks_platform_interface.dart';

class FlutterSteamworks {
  Future<String?> getPlatformVersion() {
    return FlutterSteamworksPlatform.instance.getPlatformVersion();
  }

  /// 初始化 Steam API 并通知 Steam 正在游玩指定 App
  /// [appId] 对应 Steam 上的应用 ID
  Future<bool> initSteam(int appId) async {
    return FlutterSteamworksPlatform.instance.initSteam(appId);
  }
}
