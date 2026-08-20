TARGET := iphone:clang:16.5:17.0
ARCHS = arm64e

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

include $(THEOS_MAKE_PATH)/tweak.mk
