//
//  IdentifierManager.h
//  GhostKit
//
//  Device identifier management: IDFA, IDFV, UDID.
//

#import <Foundation/Foundation.h>

@interface IdentifierManager : NSObject

+ (instancetype)sharedInstance;

/// Current IDFA string (may be all-zeros if user has limited ad tracking).
- (NSString *)getCurrentIDFA;

/// Delete IDFA-related keychain/DB records so a new IDFA is generated.
- (BOOL)refreshIDFA;

/// Refresh IDFA and reset IDFV preferences.
- (BOOL)changeIdentifier;

/// Return a dictionary with IDFA, IDFV, UDID, and system version.
- (NSDictionary *)getCurrentIdentifiers;

@end
