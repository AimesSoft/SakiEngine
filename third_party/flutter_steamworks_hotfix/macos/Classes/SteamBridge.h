#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SteamBridge : NSObject

+ (BOOL)initSteamWithAppId:(NSString *)appId;
+ (BOOL)requestCurrentStats;
+ (BOOL)getAchievementWithId:(NSString *)achievementId unlocked:(BOOL *)unlocked;
+ (BOOL)setAchievementWithId:(NSString *)achievementId;
+ (BOOL)clearAchievementWithId:(NSString *)achievementId;
+ (BOOL)storeStats;
+ (void)shutdown;

@end

NS_ASSUME_NONNULL_END
