import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_steamworks_platform_interface.dart';

/// An implementation of [FlutterSteamworksPlatform] that uses method channels.
class MethodChannelFlutterSteamworks extends FlutterSteamworksPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_steamworks');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<bool> initSteam(int appId) async {
    final result =
        await methodChannel.invokeMethod<bool>('initSteam', <String, dynamic>{'appId': appId});
    return result ?? false;
  }
}
