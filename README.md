# Kuitti

Personal family finance app for a Finnish household. Core idea: photograph a receipt → Gemini Flash extracts structured data → review → saved locally. Cross-store product price history via canonical product names, barcode lookup via Open Food Facts.

- iOS 17+, SwiftUI, SwiftData, Swift Charts. Zero third-party packages.
- Project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen): `xcodegen generate` (the `.xcodeproj` is not committed).
- The Gemini API key is entered in-app (Settings) and stored in the Keychain — it exists nowhere in this repo or the binary.

## Build

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Kuitti.xcodeproj -scheme Kuitti \
  -destination "platform=iOS Simulator,name=<an available iPhone>" build
```

The full architecture plan lives in the owner's planning notes (`pfm-ios-app-distributed-mitten.md`).
