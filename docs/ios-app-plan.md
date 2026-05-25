# iOS/iPadOS App Plan

The current native foundation is the Swift package at `ios/ReaderAPI`. It is not a full app yet. It gives a SwiftUI app typed access to the deployed web API.

## Recommended First App

Build a SwiftUI universal iPhone/iPad app with:

- Login and register screens.
- Keychain storage for the bearer token returned by `/api/auth/login`.
- Sidebar or split-view article list on iPad.
- Reader view that renders article HTML.
- Save URL action from the share sheet.
- Archive/delete/label support after the first usable version.

## How To Start In Xcode

1. File > New > Project.
2. Choose iOS > App.
3. Product name: `Library`.
4. Interface: SwiftUI.
5. Minimum deployment: iOS 17.
6. Add local package: `ios/ReaderAPI`.

The first screen should create a `ReaderAPIClient` with your deployed Vercel URL:

```swift
let client = ReaderAPIClient(baseURL: URL(string: "https://your-domain.vercel.app")!)
```

After login, store `response.token` in Keychain and pass it back into the client on app launch.
