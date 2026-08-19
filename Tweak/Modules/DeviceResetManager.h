//
//  DeviceResetManager.h
//  GhostKit
//
//  One-tap device reset: clears keychain, IDFA, caches, cookies,
//  pasteboard, notifications, WebKit data, then resprings.
//

#import <Foundation/Foundation.h>

@interface DeviceResetManager : NSObject

+ (instancetype)sharedInstance;

/// Full device reset: clean keychain + IDFA + system residue + IDFV prefs +
/// cookies + pasteboard + notification data + WebKit data, then respring.
- (BOOL)resetDevice;

/// Return basic device info dictionary.
- (NSDictionary *)getDeviceInfo;

@end
