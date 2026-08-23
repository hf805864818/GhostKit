# GhostKit Tweak Makefile
# Supports both rootful and rootless jailbreaks

# Base target - adjust to your iOS version
TARGET := iphone:clang:16.5:17.0
ARCHS = arm64e

# CRITICAL: Enable rootless mode for Dopamine/RelaXin
export THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GhostKit

GhostKit_FILES = \
    Tweak.x \
    Modules/KeychainManager.m \
    Modules/IdentifierManager.m \
    Modules/DeviceResetManager.m \
    Modules/CacheCleaner.m \
    Modules/AppListManager.m \
    Modules/AccountManager.m \
    Modules/PermissionManager.m \
    Modules/SystemManager.m \
    Modules/InjectionManager.m \
    Modules/GraphicsConfigManager.m \
    Modules/DarwinNotifyManager.m \
    Modules/OverlayController.m \
    Modules/GhostKitSettingsViewController.m \
    Modules/GhostKitFeatureButtonsViewController.m

GhostKit_CFLAGS = -fobjc-arc -IModules -Wno-unused-variable -Wno-unused-function
GhostKit_FRAMEWORKS = UIKit Security Foundation AdSupport CoreFoundation
GhostKit_PRIVATE_FRAMEWORKS = SpringBoardServices MobileContainerManager AppSupport
GhostKit_LIBRARIES = sqlite3

# Rootless installs to /Library/RootlessTweaks instead of /Library/MobileSubstrate/DynamicLibraries
# This is handled automatically by THEOS_PACKAGE_SCHEME = rootless

include $(THEOS_MAKE_PATH)/tweak.mk
