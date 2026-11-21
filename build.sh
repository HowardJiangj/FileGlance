#!/bin/bash
set -eu
cd "$(dirname "$0")"
dest=${1:-"$PWD/build"}
mkdir -p "$dest"
app="$dest/FileGlance.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Info.plist "$app/Contents/Info.plist"
cp AppIcon.icns "$app/Contents/Resources/"
for arch in x86_64 arm64; do
    minimum=10.15
    if [[ "$arch" == arm64 ]]; then minimum=11.0; fi
    xcrun clang -arch "$arch" -mmacosx-version-min="$minimum" -fobjc-arc -O2 -Wall -Wextra \
        -Werror=unguarded-availability-new -Wno-deprecated-declarations \
        main.m FinderItem.m HoverCard.m FilePreview.m \
        -framework AppKit -framework QuartzCore -framework ApplicationServices -framework ImageIO \
        -framework QuickLookThumbnailing -framework CoreServices -o "$dest/FileGlance-$arch"
done
xcrun lipo -create "$dest/FileGlance-x86_64" "$dest/FileGlance-arm64" -output "$app/Contents/MacOS/FileGlance"
codesign --force --sign - --identifier local.fileglance.hoverpreview "$app"
codesign --verify --strict --deep "$app"
