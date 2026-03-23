import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_steamworks_method_channel.dart';

abstract class FlutterSteamworksPlatform extends PlatformInterface {
  /// Constructs a FlutterSteamworksPlatform.
  FlutterSteamworksPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterSteamworksPlatform _instance = MethodChannelFlutterSteamworks();

  /// The default instance of [FlutterSteamworksPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterSteamworks].
  static FlutterSteamworksPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterSteamworksPlatform] when
  /// they register themselves.
  static set instance(FlutterSteamworksPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<bool> initSteam(int appId) {
    throw UnimplementedError('initSteam() has not been implemented.');
  }
}
