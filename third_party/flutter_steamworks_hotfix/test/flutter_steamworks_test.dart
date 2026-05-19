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

  @override
  Future<bool> requestCurrentStats() => Future.value(true);

  @override
  Future<bool> getAchievement(String achievementId) =>
      Future.value(achievementId == 'test.achievement');

  @override
  Future<bool> setAchievement(String achievementId) =>
      Future.value(achievementId == 'test.achievement');

  @override
  Future<bool> clearAchievement(String achievementId) =>
      Future.value(achievementId == 'test.achievement');

  @override
  Future<bool> storeStats() => Future.value(true);
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

  test('achievement APIs', () async {
    FlutterSteamworks flutterSteamworksPlugin = FlutterSteamworks();
    MockFlutterSteamworksPlatform fakePlatform = MockFlutterSteamworksPlatform();
    FlutterSteamworksPlatform.instance = fakePlatform;

    expect(await flutterSteamworksPlugin.requestCurrentStats(), isTrue);
    expect(await flutterSteamworksPlugin.getAchievement('test.achievement'), isTrue);
    expect(await flutterSteamworksPlugin.getAchievement('nope'), isFalse);
    expect(await flutterSteamworksPlugin.setAchievement('test.achievement'), isTrue);
    expect(await flutterSteamworksPlugin.clearAchievement('test.achievement'), isTrue);
    expect(await flutterSteamworksPlugin.storeStats(), isTrue);
  });
}
