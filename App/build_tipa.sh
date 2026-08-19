#!/bin/bash
###############################################################################
# build_tipa.sh - Build & package GhostKit as a TrollStore .tipa
#
# Usage:
#   VERSION=1.0.0 ./build_tipa.sh
#
# Requirements:
#   - Xcode command line tools (xcodebuild, PlistBuddy, zip)
#   - A valid GhostKit.xcodeproj alongside this script
###############################################################################

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
VERSION="${VERSION:-1.0.0}"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEME="GhostKit"
CONFIGURATION="Release"
BUILD_DIR="${PROJECT_DIR}/build"
PAYLOAD_DIR="${BUILD_DIR}/Payload"
TIPA_PATH="${BUILD_DIR}/GhostKit_${VERSION}.tipa"
INFO_PLIST="${PROJECT_DIR}/GhostKitApp/Info.plist"

echo "==> GhostKit TIPA build"
echo "    Version : ${VERSION}"
echo "    Project : ${PROJECT_DIR}"

# ---------------------------------------------------------------------------
# Step 1 - Update Info.plist version number
# ---------------------------------------------------------------------------
if [ -f "${INFO_PLIST}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${INFO_PLIST}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "${INFO_PLIST}" 2>/dev/null || true
    echo "==> Updated Info.plist -> CFBundleShortVersionString=${VERSION}"
else
    echo "Warning: Info.plist not found at ${INFO_PLIST}, skipping version update"
fi

# ---------------------------------------------------------------------------
# Step 2 - Clean previous build artefacts
# ---------------------------------------------------------------------------
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# ---------------------------------------------------------------------------
# Step 3 - Compile with xcodebuild (no code signing, TrollStore injects entitlements)
# ---------------------------------------------------------------------------
echo "==> Compiling with xcodebuild ..."

xcodebuild \
    -project "${PROJECT_DIR}/GhostKit.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -sdk iphoneos \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    DEVELOPMENT_TEAM="" \
    CODE_SIGN_ENTITLEMENTS="" \
    CONFIGURATION_BUILD_DIR="${BUILD_DIR}" \
    clean build \
    2>&1 | tee "${BUILD_DIR}/build.log"

# ---------------------------------------------------------------------------
# Step 4 - Locate the .app bundle
# ---------------------------------------------------------------------------
APP_BUNDLE="$(find "${BUILD_DIR}" -name "GhostKit.app" -type d | head -n 1)"
if [ -z "${APP_BUNDLE}" ]; then
    echo "Error: GhostKit.app bundle not found after build"
    exit 1
fi
echo "==> Found bundle: ${APP_BUNDLE}"

# ---------------------------------------------------------------------------
# Step 5 - Copy RootHelper binary into the bundle (if compiled separately)
# ---------------------------------------------------------------------------
ROOTHELPER_BIN="${PROJECT_DIR}/GhostKitApp/RootHelper/RootHelper"
if [ -f "${ROOTHELPER_BIN}" ]; then
    cp "${ROOTHELPER_BIN}" "${APP_BUNDLE}/RootHelper"
    chmod 0755 "${APP_BUNDLE}/RootHelper"
    echo "==> Bundled RootHelper binary"
fi

# ---------------------------------------------------------------------------
# Step 5b - Fakesign binaries with entitlements via ldid
#           TrollStore reads embedded entitlements from the code signature.
#           Also fakesign bundled tool binaries (ldid, insert_dylib, etc.)
# ---------------------------------------------------------------------------
ENTITLEMENTS="${PROJECT_DIR}/GhostKitApp/Entitlements/GhostKit.entitlements"
if command -v ldid &> /dev/null; then
    echo "==> Fakesigning with entitlements via ldid"
    # Main app binary: embed entitlements
    if [ -f "${ENTITLEMENTS}" ]; then
        ldid -S"${ENTITLEMENTS}" "${APP_BUNDLE}/GhostKit" 2>/dev/null || \
            echo "Warning: ldid failed for main binary, continuing without entitlements"
    else
        ldid -S "${APP_BUNDLE}/GhostKit" 2>/dev/null || true
    fi
    # RootHelper binary
    if [ -f "${APP_BUNDLE}/RootHelper" ]; then
        ldid -S "${APP_BUNDLE}/RootHelper" 2>/dev/null || true
    fi
    # Bundled tool binaries
    for tool in ldid insert_dylib ct_bypass trollstorehelper; do
        TOOL_PATH="${APP_BUNDLE}/${tool}"
        if [ -f "${TOOL_PATH}" ]; then
            chmod 0755 "${TOOL_PATH}"
            ldid -S "${TOOL_PATH}" 2>/dev/null || true
            echo "==> Fakesigned tool: ${tool}"
        fi
    done
    # Bundled dylibs
    for dylib in libiosexec.1.dylib libcrypto.3.dylib; do
        DYLIB_PATH="${APP_BUNDLE}/${dylib}"
        if [ -f "${DYLIB_PATH}" ]; then
            chmod 0755 "${DYLIB_PATH}"
            ldid -S "${DYLIB_PATH}" 2>/dev/null || true
            echo "==> Fakesigned dylib: ${dylib}"
        fi
    done
    # Any other embedded .dylib
    find "${APP_BUNDLE}" -name "*.dylib" ! -name "libiosexec*" ! -name "libcrypto*" -exec ldid -S {} \; 2>/dev/null || true
    echo "==> Entitlements embedded, tools fakesigned"
else
    echo "Warning: ldid not found, entitlements will NOT be embedded"
    echo "         This may cause private API failures at runtime"
fi

# ---------------------------------------------------------------------------
# Step 6 - Create Payload directory & package as .tipa (zip)
# ---------------------------------------------------------------------------
rm -rf "${PAYLOAD_DIR}"
mkdir -p "${PAYLOAD_DIR}"
cp -R "${APP_BUNDLE}" "${PAYLOAD_DIR}/"

echo "==> Packaging ${TIPA_PATH}"
cd "${BUILD_DIR}"
rm -f "${TIPA_PATH}"
zip -rq "${TIPA_PATH}" Payload/

echo "==> Done"
echo "    Output: ${TIPA_PATH}"
