#import "SteamBridge.h"
#include "steam_api.h"

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

+ (void)shutdown {
    SteamAPI_Shutdown();
    NSLog(@"Steam API shutdown");
}

@end
