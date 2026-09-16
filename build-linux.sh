#!/bin/bash
# KRemote Linux build script for v0.2.0-alpha
set -e

echo "Building KRemote for Linux..."

# Install dependencies if needed
if ! command -v flutter &> /dev/null; then
    echo "Flutter not found. Please install Flutter for Linux first:"
    echo "https://docs.flutter.dev/get-started/install/linux"
    exit 1
fi

# Check for required Linux dependencies
echo "Checking Linux build dependencies..."
MISSING_DEPS=""
for dep in clang cmake ninja-build pkg-config libgtk-3-dev; do
    if ! dpkg -l | grep -q "^ii  $dep"; then
        MISSING_DEPS="$MISSING_DEPS $dep"
    fi
done

if [ -n "$MISSING_DEPS" ]; then
    echo "Missing dependencies:$MISSING_DEPS"
    echo "Install with: sudo apt-get install$MISSING_DEPS"
    exit 1
fi

# Clean and build
flutter clean
flutter pub get
flutter build linux --release

# Package
echo "Creating release package..."
cd build/linux/x64/release/bundle
tar -czf ../../../../../KRemote-v0.2.0-alpha-linux-x64.tar.gz *
cd ../../../../..

echo "✓ Build complete: KRemote-v0.2.0-alpha-linux-x64.tar.gz"
ls -lh KRemote-v0.2.0-alpha-linux-x64.tar.gz
