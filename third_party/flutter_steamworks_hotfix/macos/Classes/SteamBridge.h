#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SteamBridge : NSObject

+ (BOOL)initSteamWithAppId:(NSString *)appId;
+ (void)shutdown;

@end

NS_ASSUME_NONNULL_END
