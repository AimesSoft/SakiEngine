import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_steamworks/flutter_steamworks.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final FlutterSteamworks _steamworks = FlutterSteamworks();
  static const String _demoAchievementId = 'FIRST_STEP';

  String _platformVersion = 'Unknown';
  bool _steamInitialized = false;
  bool _achievementUnlocked = false;

  @override
  void initState() {
    super.initState();
    _initSteam();
  }

  Future<void> _initSteam() async {
    String platformVersion = 'Unknown platform version';
    bool steamInitialized = false;
    bool achievementUnlocked = false;

    try {
      platformVersion = await _steamworks.getPlatformVersion() ?? platformVersion;
      steamInitialized = await _steamworks.initSteam(480);
      if (steamInitialized) {
        await _steamworks.requestCurrentStats();
        achievementUnlocked = await _steamworks.getAchievement(_demoAchievementId);
      }
    } on PlatformException catch (error) {
      platformVersion = 'Failed to initialize Steam: ${error.message ?? error.code}';
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _platformVersion = platformVersion;
      _steamInitialized = steamInitialized;
      _achievementUnlocked = achievementUnlocked;
    });
  }

  Future<void> _unlockAchievement() async {
    final ok = await _steamworks.setAchievement(_demoAchievementId);
    if (!ok) {
      return;
    }
    await _steamworks.storeStats();
    final unlocked = await _steamworks.getAchievement(_demoAchievementId);
    if (!mounted) {
      return;
    }
    setState(() {
      _achievementUnlocked = unlocked;
    });
  }

  Future<void> _clearAchievement() async {
    final ok = await _steamworks.clearAchievement(_demoAchievementId);
    if (!ok) {
      return;
    }
    await _steamworks.storeStats();
    final unlocked = await _steamworks.getAchievement(_demoAchievementId);
    if (!mounted) {
      return;
    }
    setState(() {
      _achievementUnlocked = unlocked;
    });
  }

  @override
  Widget build(BuildContext context) {
    final statusText = _steamInitialized ? 'Steam: initialized' : 'Steam: not initialized';
    final achievementText = _achievementUnlocked
        ? 'Achievement FIRST_STEP: unlocked'
        : 'Achievement FIRST_STEP: locked';

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('flutter_steamworks example')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Running on: $_platformVersion'),
              const SizedBox(height: 8),
              Text(statusText),
              const SizedBox(height: 8),
              Text(achievementText),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: _steamInitialized ? _unlockAchievement : null,
                    child: const Text('Unlock FIRST_STEP'),
                  ),
                  ElevatedButton(
                    onPressed: _steamInitialized ? _clearAchievement : null,
                    child: const Text('Clear FIRST_STEP'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
