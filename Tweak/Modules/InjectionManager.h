//
//  InjectionManager.h
//  GhostKit
//
//  Dylib injection management: inject / remove / list dylibs in app binaries.
//  Supports the 520.dylib injection pattern.
//

#import <Foundation/Foundation.h>

@interface InjectionManager : NSObject

+ (instancetype)sharedInstance;

/// Inject a dylib into an app's binary.
/// Copies the dylib into the app bundle, adds a LC_LOAD_DYLIB load command
/// via insert_dylib, and re-signs the binary.
/// @param dylibPath Path to the .dylib file to inject.
/// @param bundleID  Target app bundle identifier.
/// @return YES on success.
- (BOOL)injectDylib:(NSString *)dylibPath forBundleID:(NSString *)bundleID;

/// Remove a previously injected dylib from an app's binary.
/// Restores the original binary from backup and removes the dylib file.
- (BOOL)removeDylib:(NSString *)dylibPath forBundleID:(NSString *)bundleID;

/// List all dylib load commands in an app's binary.
- (NSArray<NSString *> *)getInjectedDylibsForBundleID:(NSString *)bundleID;

@end
