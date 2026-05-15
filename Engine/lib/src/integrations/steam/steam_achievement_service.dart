import 'package:sakiengine/src/integrations/steam/steamworks_manager.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';

class SteamAchievementService {
  SteamAchievementService._();

  static final SteamAchievementService instance = SteamAchievementService._();

  final Set<String> _registeredAchievements = <String>{};

  bool isRegistered(String achievementId) {
    return _registeredAchievements.contains(achievementId);
  }

  bool registerAchievement(String achievementId) {
    final normalized = _normalizeAchievementId(achievementId);
    if (normalized == null) {
      return false;
    }
    _registeredAchievements.add(normalized);
    return true;
  }

  Future<bool> unlockAchievement(String achievementId, {bool autoRegister = true}) async {
    final normalized = _normalizeAchievementId(achievementId);
    if (normalized == null) {
      return false;
    }

    if (autoRegister) {
      _registeredAchievements.add(normalized);
    } else if (!_registeredAchievements.contains(normalized)) {
      return false;
    }

    final manager = SteamworksManager.instance;
    if (!manager.isInitialized) {
      _debugLog('unlockAchievement skipped: Steamworks is not initialized.');
      return false;
    }

    final requestOk = await manager.requestCurrentStats();
    if (!requestOk) {
      _debugLog('unlockAchievement failed: requestCurrentStats returned false.');
      return false;
    }

    return manager.unlockAchievement(normalized);
  }

  Future<bool> clearAchievement(String achievementId) async {
    final normalized = _normalizeAchievementId(achievementId);
    if (normalized == null) {
      return false;
    }

    final manager = SteamworksManager.instance;
    if (!manager.isInitialized) {
      _debugLog('clearAchievement skipped: Steamworks is not initialized.');
      return false;
    }

    final requestOk = await manager.requestCurrentStats();
    if (!requestOk) {
      _debugLog('clearAchievement failed: requestCurrentStats returned false.');
      return false;
    }

    return manager.clearAchievement(normalized);
  }

  Future<bool> isUnlocked(String achievementId) async {
    final normalized = _normalizeAchievementId(achievementId);
    if (normalized == null) {
      return false;
    }

    final manager = SteamworksManager.instance;
    if (!manager.isInitialized) {
      _debugLog('isUnlocked skipped: Steamworks is not initialized.');
      return false;
    }

    final requestOk = await manager.requestCurrentStats();
    if (!requestOk) {
      _debugLog('isUnlocked failed: requestCurrentStats returned false.');
      return false;
    }

    return manager.isAchievementUnlocked(normalized);
  }

  String? _normalizeAchievementId(String achievementId) {
    final normalized = achievementId.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  void _debugLog(String message) {
    if (kEngineDebugMode) {
      debugPrint('[SteamAchievementService] $message');
    }
  }
}
