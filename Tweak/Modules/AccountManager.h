//
//  AccountManager.h
//  GhostKit
//
//  App Store account management: store multiple Apple IDs,
//  read the current signed-in account, and switch between them.
//

#import <Foundation/Foundation.h>

@interface AppStoreAccount : NSObject

@property (nonatomic, copy) NSString *appleID;
@property (nonatomic, copy) NSString *password;
@property (nonatomic, copy) NSString *countryCode;
@property (nonatomic, copy) NSString *displayName;

- (NSDictionary *)toDictionary;

@end

@interface AccountManager : NSObject

+ (instancetype)sharedInstance;

/// Read all stored accounts from the plist.
- (NSArray<AppStoreAccount *> *)getAccountList;

/// Persist a new account.
- (BOOL)addAccount:(AppStoreAccount *)account;

/// Remove an account by Apple ID.
- (BOOL)deleteAccount:(NSString *)appleID;

/// Read the currently signed-in App Store account.
- (AppStoreAccount *)getCurrentAccount;

/// Switch the App Store to the given account (modify preferences + kill AppStore).
- (BOOL)switchAccount:(AppStoreAccount *)account;

@end
