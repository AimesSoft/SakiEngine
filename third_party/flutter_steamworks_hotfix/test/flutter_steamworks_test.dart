import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_steamworks/flutter_steamworks.dart';
import 'package:flutter_steamworks/flutter_steamworks_platform_interface.dart';
import 'package:flutter_steamworks/flutter_steamworks_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterSteamworksPlatform
    with MockPlatformInterfaceMixin
    implements FlutterSteamworksPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<bool> initSteam(int appId) => Future.value(appId == 480);
}

void main() {
  final FlutterSteamworksPlatform initialPlatform = FlutterSteamworksPlatform.instance;

  test('$MethodChannelFlutterSteamworks is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterSteamworks>());
  });

  test('getPlatformVersion', () async {
    FlutterSteamworks flutterSteamworksPlugin = FlutterSteamworks();
    MockFlutterSteamworksPlatform fakePlatform = MockFlutterSteamworksPlatform();
    FlutterSteamworksPlatform.instance = fakePlatform;

    expect(await flutterSteamworksPlugin.getPlatformVersion(), '42');
  });

  test('initSteam forwards appId', () async {
    FlutterSteamworks flutterSteamworksPlugin = FlutterSteamworks();
    MockFlutterSteamworksPlatform fakePlatform = MockFlutterSteamworksPlatform();
    FlutterSteamworksPlatform.instance = fakePlatform;

    expect(await flutterSteamworksPlugin.initSteam(480), isTrue);
    expect(await flutterSteamworksPlugin.initSteam(123), isFalse);
  });
}
