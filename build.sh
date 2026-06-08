#!/bin/bash
set -e

# Setup Dev Environment
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)

APP_NAME="SwiftSeis"
APP_BUNDLE="${APP_NAME}.app"
MACOS_DIR="${APP_BUNDLE}/Contents/MacOS"
RESOURCES_DIR="${APP_BUNDLE}/Contents/Resources"

echo "Cleaning previous builds..."
rm -rf "${APP_BUNDLE}" "${APP_NAME}" "MacSEGY.app" "MacSEGY"

echo "Creating bundle directory structure..."
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

echo "Compiling Swift files with optimized build settings..."
xcrun -sdk macosx swiftc -O \
  -sdk "${SDK_PATH}" \
  -target arm64-apple-macosx14.0 \
  main.swift \
  SEGYModel.swift \
  MetalRenderer.swift \
  ContentView.swift \
  TraceInspectorView.swift \
  TraceHeaderTable.swift \
  LocationMapView.swift \
  LocationMapWindowController.swift \
  HeaderPlotView.swift \
  QCReportWindowController.swift \
  QCModels.swift \
  QCAnalyzer.swift \
  QCReportView.swift \
  QCExport.swift \
  -o "${MACOS_DIR}/${APP_NAME}"

echo "Packaging Info.plist..."
cp Info.plist "${APP_BUNDLE}/Contents/Info.plist"

echo "Packaging AppIcon..."
cp AppIcon.icns "${RESOURCES_DIR}/AppIcon.icns"

echo "Applying ad-hoc code signature..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "==========================================="
echo "Build Successful: ${APP_BUNDLE}"
echo "Run the application using: open ${APP_BUNDLE}"
echo "==========================================="
