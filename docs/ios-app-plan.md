# Native App

The Safari Xcode project now contains the first usable native app. It uses SwiftUI inside the generated iOS, iPadOS, and macOS container targets.

## Targets

- `Library (iOS)`: iPhone/iPad app with login, article list, reader, add URL, archive, and sign out.
- `Library (macOS)`: macOS app with the same native reader shell and embedded Safari extension.
- `Library Extension (iOS)`: Safari Web Extension for iOS/iPadOS Safari.
- `Library Extension (macOS)`: Safari Web Extension for macOS Safari.
- `Library Share (iOS)`: iOS/iPadOS Share Extension that receives a URL and opens the main app to save it.

## Test

In Xcode, run:

- `Library (macOS)` on `My Mac` to test the macOS app and Safari extension.
- `Library (iOS)` on an iPhone/iPad simulator or device to test the native app and share sheet.

The app talks to:

```text
https://readitlater-theta.vercel.app
```

## Share Sheet

The share extension accepts web URLs and plain text URLs. It opens the main app with:

```text
library://save?url=<encoded-url>
```

The main app then saves the article using the signed-in account token.

## Next Polish

- Move token storage from `UserDefaults` to Keychain before shipping.
- Add label editing and highlight viewing natively.
- Add offline article caching.
- Replace generated placeholder app icons.
