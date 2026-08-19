//
//  GraphicsConfigManager.m
//  GhostKit
//
//  Modifies UE4 game UserCustom.ini files to adjust graphics quality.
//  Supported games: 和平精英, 王者荣耀, 光遇, 穿越火线, 使命召唤,
//  火影忍者, DNF.
//
//  Config path: dynamically discovered per game by scanning
//  Documents/UE4Game/<ProjectName>/Saved/Config/IOS/UserCustom.ini
//  Each UE4 game uses a different project name, so the path is
//  resolved at runtime rather than hardcoded.
//

#import "GraphicsConfigManager.h"
#import "AppListManager.h"

@implementation GraphicsConfigManager

+ (instancetype)sharedInstance {
    static GraphicsConfigManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[GraphicsConfigManager alloc] init];
    });
    return instance;
}

#pragma mark - Game / path mapping

- (NSDictionary *)supportedGames {
    return @{
        // 和平精英 (Game for Peace / PUBG Mobile)
        @"com.tencent.tmgp.pubgmhd": @"和平精英",
        // 王者荣耀 (Honor of Kings)
        @"com.tencent.smoba":        @"王者荣耀",
        // 光遇 (Sky: Children of the Light)
        @"com.netease.sky":          @"光遇",
        // 穿越火线 (CrossFire Mobile)
        @"com.tencent.tmgp.cf":      @"穿越火线",
        // 使命召唤 (Call of Duty Mobile)
        @"com.tencent.tmgp.codm":    @"使命召唤",
        // 火影忍者 (Naruto Mobile)
        @"com.tencent.tmgp.hgjy":    @"火影忍者",
        // DNF (DNF Mobile)
        @"com.tencent.cdnf":         @"DNF",
    };
}

- (NSString *)configPathForBundleID:(NSString *)bundleID {
    /*
     * Each UE4 game uses a different project name (e.g., ShadowTrackerExtra
     * for PUBG Mobile, SkyGame for 光遇, etc.).  Instead of hardcoding,
     * we scan the Documents/UE4Game/ directory for the project folder.
     *
     * This method returns a RELATIVE path.  fullConfigPathForBundleID:
     * prepends the app's data container path.
     */
    NSString *dataPath = [[AppListManager sharedInstance] getDataContainerPathForBundleID:bundleID];
    if (!dataPath) {
        // Fallback to the hardcoded PUBG path if we can't resolve.
        return @"Documents/UE4Game/ShadowTrackerExtra/Saved/Config/IOS/UserCustom.ini";
    }

    NSString *ue4Dir = [dataPath stringByAppendingPathComponent:@"Documents/UE4Game"];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *subdirs = [fm contentsOfDirectoryAtPath:ue4Dir error:nil];

    for (NSString *subdir in subdirs) {
        // Skip hidden files.
        if ([subdir hasPrefix:@"."]) continue;

        NSString *candidatePath = [NSString stringWithFormat:
            @"Documents/UE4Game/%@/Saved/Config/IOS/UserCustom.ini", subdir];

        // Check if this looks like a UE4 project directory.
        NSString *savedDir = [dataPath stringByAppendingPathComponent:
            [NSString stringWithFormat:@"Documents/UE4Game/%@/Saved", subdir]];
        if ([fm fileExistsAtPath:savedDir]) {
            return candidatePath;
        }
    }

    // Fallback: use the first subdirectory found, even if Saved doesn't exist yet.
    for (NSString *subdir in subdirs) {
        if (![subdir hasPrefix:@"."]) {
            return [NSString stringWithFormat:
                @"Documents/UE4Game/%@/Saved/Config/IOS/UserCustom.ini", subdir];
        }
    }

    // Last resort: PUBG Mobile default.
    return @"Documents/UE4Game/ShadowTrackerExtra/Saved/Config/IOS/UserCustom.ini";
}

- (NSString *)fullConfigPathForBundleID:(NSString *)bundleID {
    NSString *dataPath = [[AppListManager sharedInstance] getDataContainerPathForBundleID:bundleID];
    if (!dataPath) {
        return nil;
    }
    return [dataPath stringByAppendingPathComponent:[self configPathForBundleID:bundleID]];
}

#pragma mark - Preset settings

- (NSDictionary *)settingsForPreset:(NSString *)preset {
    if ([preset isEqualToString:@"流畅"]) {
        return @{
            @"r.MobileContentScaleFactor":   @"0.85",
            @"r.AmbientOcclusion":           @"0",
            @"r.DepthOfField":               @"0",
            @"r.LensFlare":                  @"0",
            @"r.Bloom":                      @"0",
            @"r.MobileHDR":                  @"0",
            @"r.MobileHDR32bpp":             @"0",
            @"r.PostProcessing":             @"0",
            @"r.ShadowQuality":              @"0",
            @"r.MobileDynamicCSMShadow":      @"0",
            @"r.MobileShadowQuality":         @"0",
            @"r.MobileAntiAliasing":         @"0",
            @"r.MobileMSAA":                 @"0",
            @"r.MobileFXAA":                 @"0",
            @"r.RefractionQuality":          @"0",
            @"r.ReflectionEnvironment":       @"0",
            @"r.MobileReflectionCapture":    @"0",
            @"r.SceneColorFringeQuality":     @"0",
            @"r.VolumetricFog":              @"0",
            @"r.ViewDistanceScale":          @"0.4",
            @"r.TextureStreaming":           @"1",
            @"r.TextureMinQuality":          @"0",
            @"foliage.AntiTileNormal":      @"0",
            @"r.Decale.DitherThreshold":     @"0",
            @"r.MobileNumDynamicPointLights": @"0",
            @"r.Mobile.EnableMovableLightCSM": @"0",
            @"r.LightMaxDrawDistanceScale":  @"0.5",
            @"foliage.DitheringLOD":         @"0",
            @"r.Mobile.AdaptiveHQ":          @"0",
        };
    }

    if ([preset isEqualToString:@"平衡"]) {
        return @{
            @"r.MobileContentScaleFactor":   @"1.0",
            @"r.AmbientOcclusion":           @"1",
            @"r.DepthOfField":               @"1",
            @"r.LensFlare":                  @"0",
            @"r.Bloom":                      @"1",
            @"r.MobileHDR":                  @"0",
            @"r.PostProcessing":             @"1",
            @"r.ShadowQuality":              @"1",
            @"r.MobileDynamicCSMShadow":      @"1",
            @"r.MobileShadowQuality":         @"1",
            @"r.MobileAntiAliasing":         @"1",
            @"r.MobileMSAA":                 @"0",
            @"r.MobileFXAA":                 @"1",
            @"r.RefractionQuality":          @"1",
            @"r.ReflectionEnvironment":       @"1",
            @"r.MobileReflectionCapture":    @"1",
            @"r.SceneColorFringeQuality":     @"0",
            @"r.VolumetricFog":              @"0",
            @"r.ViewDistanceScale":          @"1.0",
            @"r.TextureStreaming":           @"1",
            @"r.TextureMinQuality":          @"1",
            @"foliage.AntiTileNormal":      @"1",
            @"r.MobileNumDynamicPointLights": @"1",
            @"r.Mobile.EnableMovableLightCSM": @"1",
            @"r.LightMaxDrawDistanceScale":  @"1.0",
            @"foliage.DitheringLOD":         @"1",
            @"r.Mobile.AdaptiveHQ":          @"1",
        };
    }

    if ([preset isEqualToString:@"高清"]) {
        return @{
            @"r.MobileContentScaleFactor":   @"1.1",
            @"r.AmbientOcclusion":           @"1",
            @"r.DepthOfField":               @"1",
            @"r.LensFlare":                  @"0",
            @"r.Bloom":                      @"1",
            @"r.MobileHDR":                  @"1",
            @"r.MobileHDR32bpp":             @"1",
            @"r.PostProcessing":             @"1",
            @"r.ShadowQuality":              @"1",
            @"r.MobileDynamicCSMShadow":      @"1",
            @"r.MobileShadowQuality":         @"2",
            @"r.MobileAntiAliasing":         @"1",
            @"r.MobileMSAA":                 @"0",
            @"r.MobileFXAA":                 @"1",
            @"r.RefractionQuality":          @"1",
            @"r.ReflectionEnvironment":       @"2",
            @"r.MobileReflectionCapture":    @"2",
            @"r.SceneColorFringeQuality":     @"0",
            @"r.VolumetricFog":              @"0",
            @"r.ViewDistanceScale":          @"1.2",
            @"r.TextureStreaming":           @"1",
            @"r.TextureMinQuality":          @"2",
            @"foliage.AntiTileNormal":      @"1",
            @"r.MobileNumDynamicPointLights": @"1",
            @"r.Mobile.EnableMovableLightCSM": @"1",
            @"r.LightMaxDrawDistanceScale":  @"1.2",
            @"foliage.DitheringLOD":         @"1",
            @"r.Mobile.AdaptiveHQ":          @"1",
        };
    }

    if ([preset isEqualToString:@"极致"]) {
        return @{
            @"r.MobileContentScaleFactor":   @"1.2",
            @"r.AmbientOcclusion":           @"2",
            @"r.DepthOfField":               @"2",
            @"r.LensFlare":                  @"1",
            @"r.Bloom":                      @"1",
            @"r.MobileHDR":                  @"1",
            @"r.PostProcessing":             @"2",
            @"r.ShadowQuality":              @"2",
            @"r.MobileDynamicCSMShadow":      @"1",
            @"r.MobileShadowQuality":         @"2",
            @"r.MobileAntiAliasing":         @"2",
            @"r.MobileMSAA":                 @"1",
            @"r.MobileFXAA":                 @"1",
            @"r.RefractionQuality":          @"2",
            @"r.ReflectionEnvironment":       @"2",
            @"r.MobileReflectionCapture":    @"2",
            @"r.SceneColorFringeQuality":     @"1",
            @"r.VolumetricFog":              @"1",
            @"r.ViewDistanceScale":          @"1.5",
            @"r.TextureStreaming":           @"1",
            @"r.TextureMinQuality":          @"2",
            @"foliage.AntiTileNormal":      @"1",
            @"r.MobileNumDynamicPointLights": @"2",
            @"r.Mobile.EnableMovableLightCSM": @"1",
            @"r.LightMaxDrawDistanceScale":  @"1.5",
            @"foliage.DitheringLOD":         @"1",
            @"r.Mobile.AdaptiveHQ":          @"1",
        };
    }

    if ([preset isEqualToString:@"自定义"]) {
        // Custom preset: same as 平衡 as a starting point.
        // Users can manually edit the INI afterwards.
        return [self settingsForPreset:@"平衡"];
    }

    return @{};
}

#pragma mark - INI parsing

- (NSMutableDictionary *)parseIniFile:(NSString *)path {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSString *content = [NSString stringWithContentsOfFile:path
                                                encoding:NSUTF8StringEncoding
                                                   error:nil];
    if (!content) {
        return result;
    }

    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    NSString *currentSection = @"";

    for (NSString *rawLine in lines) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (line.length == 0 || [line hasPrefix:@";"] || [line hasPrefix:@"#"]) {
            continue;
        }

        if ([line hasPrefix:@"["] && [line hasSuffix:@"]"]) {
            currentSection = [line substringWithRange:NSMakeRange(1, line.length - 2)];
            if (![result objectForKey:currentSection]) {
                result[currentSection] = [NSMutableDictionary dictionary];
            }
            continue;
        }

        NSRange equalsRange = [line rangeOfString:@"="];
        if (equalsRange.location != NSNotFound) {
            NSString *key = [[line substringToIndex:equalsRange.location]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSString *value = [[line substringFromIndex:equalsRange.location + 1]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

            if (key.length > 0) {
                NSMutableDictionary *section = result[currentSection];
                if (!section) {
                    section = [NSMutableDictionary dictionary];
                    result[currentSection] = section;
                }
                section[key] = value;
            }
        }
    }

    return result;
}

- (NSString *)writeIniFromDictionary:(NSDictionary *)dict {
    NSMutableString *output = [NSMutableString string];

    NSArray *sections = [dict allKeys];
    // Always put SystemSettings first if present.
    NSMutableArray *sortedSections = [NSMutableArray arrayWithArray:sections];
    if ([sortedSections containsObject:@"SystemSettings"]) {
        [sortedSections removeObject:@"SystemSettings"];
        [sortedSections insertObject:@"SystemSettings" atIndex:0];
    }

    for (NSString *section in sortedSections) {
        [output appendFormat:@"[%@]\n", section];
        NSDictionary *sectionDict = dict[section];
        // Sort keys for deterministic output.
        NSArray *sortedKeys = [[sectionDict allKeys]
            sortedArrayUsingSelector:@selector(compare:)];
        for (NSString *key in sortedKeys) {
            [output appendFormat:@"%@=%@\n", key, sectionDict[key]];
        }
        [output appendString:@"\n"];
    }

    return output;
}

#pragma mark - Apply config

- (BOOL)applyGraphicsConfig:(NSString *)preset forBundleID:(NSString *)bundleID {
    if (!preset || !bundleID) {
        return NO;
    }

    NSDictionary *supported = [self supportedGames];
    if (!supported[bundleID]) {
        NSLog(@"[GhostKit] Unsupported game: %@", bundleID);
        return NO;
    }

    NSDictionary *newSettings = [self settingsForPreset:preset];
    if (newSettings.count == 0) {
        NSLog(@"[GhostKit] Unknown preset: %@", preset);
        return NO;
    }

    NSString *configPath = [self fullConfigPathForBundleID:bundleID];
    if (!configPath) {
        NSLog(@"[GhostKit] Cannot resolve config path for %@", bundleID);
        return NO;
    }

    // Ensure the config directory exists.
    NSString *configDir = [configPath stringByDeletingLastPathComponent];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:configDir
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];

    // Read existing config.
    NSMutableDictionary *ini = [self parseIniFile:configPath];

    // Ensure SystemSettings section exists.
    NSMutableDictionary *systemSettings = ini[@"SystemSettings"];
    if (!systemSettings) {
        systemSettings = [NSMutableDictionary dictionary];
    }

    // Apply new settings.
    for (NSString *key in newSettings) {
        systemSettings[key] = newSettings[key];
    }
    ini[@"SystemSettings"] = systemSettings;

    // Write a preset marker so we can detect the current preset.
    NSMutableDictionary *ghostSection = ini[@"GhostKit"] ?: [NSMutableDictionary dictionary];
    ghostSection[@"Preset"] = preset;
    ghostSection[@"AppliedAt"] = [NSDate date].description;
    ini[@"GhostKit"] = ghostSection;

    // Write back.
    NSString *output = [self writeIniFromDictionary:ini];
    BOOL ok = [output writeToFile:configPath
                       atomically:YES
                         encoding:NSUTF8StringEncoding
                            error:nil];

    NSLog(@"[GhostKit] applyGraphicsConfig:%@ forBundleID:%@ -> %@",
          preset, bundleID, ok ? @"YES" : @"NO");
    return ok;
}

#pragma mark - Available presets

- (NSArray<NSString *> *)getAvailablePresets {
    return @[@"流畅", @"平衡", @"高清", @"极致", @"自定义"];
}

#pragma mark - Get current config

- (NSString *)getCurrentConfigForBundleID:(NSString *)bundleID {
    if (!bundleID) {
        return @"默认";
    }

    NSDictionary *supported = [self supportedGames];
    if (!supported[bundleID]) {
        return @"不支持";
    }

    NSString *configPath = [self fullConfigPathForBundleID:bundleID];
    if (!configPath) {
        return @"默认";
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:configPath]) {
        return @"默认";
    }

    NSMutableDictionary *ini = [self parseIniFile:configPath];
    NSDictionary *ghostSection = ini[@"GhostKit"];

    if (ghostSection[@"Preset"]) {
        return ghostSection[@"Preset"];
    }

    // If there is a config file but no marker, it was manually modified.
    if (ini.count > 0) {
        return @"自定义";
    }

    return @"默认";
}

#pragma mark - Restore default

- (BOOL)restoreDefaultForBundleID:(NSString *)bundleID {
    if (!bundleID) {
        return NO;
    }

    NSDictionary *supported = [self supportedGames];
    if (!supported[bundleID]) {
        return NO;
    }

    NSString *configPath = [self fullConfigPathForBundleID:bundleID];
    if (!configPath) {
        return NO;
    }

    NSFileManager *fm = [NSFileManager defaultManager];

    // Back up before removing (optional).
    if ([fm fileExistsAtPath:configPath]) {
        NSString *backupPath = [configPath stringByAppendingString:@".bak"];
        [fm removeItemAtPath:backupPath error:nil];
        [fm copyItemAtPath:configPath toPath:backupPath error:nil];

        // Delete the custom ini to restore defaults.
        BOOL ok = [fm removeItemAtPath:configPath error:nil];
        NSLog(@"[GhostKit] restoreDefaultForBundleID:%@ -> %@", bundleID, ok ? @"YES" : @"NO");
        return ok;
    }

    NSLog(@"[GhostKit] No custom config to restore for %@", bundleID);
    return YES;
}

@end
