# FileGlance Beta 1 (0.1.2)

Hover over a file in Finder or on the desktop for about half a second to see its name, size, and a preview. Images, the first page of a PDF, and plain text have built-in previews. Other formats use a Quick Look thumbnail or a file icon.

## Install

1. Download the macOS app ZIP from [Releases](https://github.com/HowardJiangj/FileGlance/releases), unzip it, and move FileGlance.app to Applications.
2. Open FileGlance and allow Accessibility access when prompted. This lets FileGlance identify the Finder item under the pointer.
3. If an older copy had Accessibility access and previews do not appear, quit FileGlance, remove the old FileGlance entry in Accessibility settings, add the installed copy, and reopen it.
4. Hover over a file. Use the eye icon in the menu bar to pause previews or quit.

This beta is ad hoc signed and has not been notarized by Apple. For first-launch instructions, see [Apple Support](https://support.apple.com/en-us/102445).

## Compatibility and build

The universal binary targets macOS 10.15 or later on Intel and macOS 11 or later on Apple silicon. File metadata and image, PDF, and text preview generation have been tested. Hover previews were verified in both a Finder window and on the desktop on the test Mac.

To build locally, install the Xcode Command Line Tools with a recent macOS SDK and run `bash build.sh` from the repository root. The application is written to `build/FileGlance.app`.

## License

Copyright © 2026 Haocheng Jiang. Authorized recipients may run the beta for personal evaluation. See [LICENSE](LICENSE) for copying and redistribution terms.
