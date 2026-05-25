# Safari Extension

The existing `extension/` folder is a WebExtension. Safari uses the same web extension files, but Apple requires them to be wrapped inside a native app target for macOS, iOS, and iPadOS.

## Prerequisite

Install full Xcode from the App Store or Apple Developer downloads. Command Line Tools alone does not include `safari-web-extension-converter`.

After installing Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Check the converter:

```bash
xcrun safari-web-extension-converter --help
```

## Convert

From the repo root:

```bash
mkdir -p safari
xcrun safari-web-extension-converter extension \
  --project-location safari \
  --app-name "Library" \
  --bundle-identifier com.giacomodaros.library
```

This creates an Xcode project containing a native app and Safari extension targets.

## Run On iPhone Or iPad

1. Open the generated Xcode project.
2. Select your Apple Developer team.
3. Choose the iOS app scheme.
4. Run it on a simulator or device.
5. On the device, enable it in Settings > Safari > Extensions.

## Before Shipping

Update the production app URL in `extension/popup.js`:

```js
const APP_ORIGIN = "https://your-domain.vercel.app";
```

Update host permissions in `extension/manifest.json`:

```json
"host_permissions": ["https://your-domain.vercel.app/*"]
```

Safari extensions for iOS/iPadOS are distributed through the App Store as part of the containing native app.
