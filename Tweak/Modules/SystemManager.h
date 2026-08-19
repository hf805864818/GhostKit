//
//  SystemManager.h
//  GhostKit
//
//  Low-level system operations: safe exit, respring, ldrestart.
//

#import <Foundation/Foundation.h>

@interface SystemManager : NSObject

+ (instancetype)sharedInstance;

/// Exit the current process gracefully.
- (void)safeExit;

/// Restart SpringBoard (respring).
- (void)respring;

/// Restart all daemons (ldrestart).
- (void)ldrestart;

@end
