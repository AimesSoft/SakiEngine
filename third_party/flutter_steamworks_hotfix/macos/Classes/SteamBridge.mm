#import "SteamBridge.h"
#include "steam_api.h"

namespace {
bool gStatsReady = false;
}

@implementation SteamBridge

+ (BOOL)initSteamWithAppId:(NSString *)appId {
    if (appId.length == 0) {
        NSLog(@"[SteamBridge] Invalid App ID");
        return NO;
    }

    const char *appIdCString = [appId UTF8String];
    setenv("SteamAppId", appIdCString, 1);
    setenv("SteamGameId", appIdCString, 1);

    bool success = SteamAPI_Init();
    if (success) {
        NSLog(@"Steam API initialized successfully");
    } else {
        NSLog(@"Failed to initialize Steam API - Make sure Steam is running");
    }
    return success;
}

+ (BOOL)requestCurrentStats {
    if (SteamUserStats() == nullptr) {
        NSLog(@"[SteamBridge] SteamUserStats unavailable");
        return NO;
    }

    gStatsReady = true;
    return YES;
}

+ (BOOL)getAchievementWithId:(NSString *)achievementId unlocked:(BOOL *)unlocked {
    if (achievementId.length == 0 || unlocked == nullptr) {
        return NO;
    }
    if (!gStatsReady && ![self requestCurrentStats]) {
        return NO;
    }

    bool achieved = false;
    const bool ok = SteamUserStats() != nullptr &&
                    SteamUserStats()->GetAchievement(achievementId.UTF8String, &achieved);
    *unlocked = achieved;
    return ok;
}

+ (BOOL)setAchievementWithId:(NSString *)achievementId {
    if (achievementId.length == 0) {
        return NO;
    }
    if (!gStatsReady && ![self requestCurrentStats]) {
        return NO;
    }
    if (SteamUserStats() == nullptr) {
        return NO;
    }

    return SteamUserStats()->SetAchievement(achievementId.UTF8String);
}

+ (BOOL)clearAchievementWithId:(NSString *)achievementId {
    if (achievementId.length == 0) {
        return NO;
    }
    if (!gStatsReady && ![self requestCurrentStats]) {
        return NO;
    }
    if (SteamUserStats() == nullptr) {
        return NO;
    }

    return SteamUserStats()->ClearAchievement(achievementId.UTF8String);
}

+ (BOOL)storeStats {
    if (!gStatsReady && ![self requestCurrentStats]) {
        return NO;
    }
    if (SteamUserStats() == nullptr) {
        return NO;
    }

    return SteamUserStats()->StoreStats();
}

+ (void)shutdown {
    SteamAPI_Shutdown();
    gStatsReady = false;
    NSLog(@"Steam API shutdown");
}

@end
