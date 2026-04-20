# Save Button Mobile

iOS and Android apps for Save Button, the local-first bookmarking engine.

## Minimum Android and iOS Versions

* Android: `grep "val minSdkVersion" "$(flutter sdk-path)/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt"` => 24
* iOS: `grep '^platform' ios/Podfile` => 14

## Development Environment Setup

### Prerequisites

1. **mise** - Install [mise](https://mise.jdx.dev/) for managing Flutter and Ruby versions
2. **Xcode** (macOS only) - Required for iOS builds. Install from the Mac App Store.
3. **Android Studio** - Required for Android builds. Install from https://developer.android.com/studio

### Ruby and CocoaPods Setup (macOS only)

CocoaPods is required for iOS dependencies. Install it via mise-managed Ruby:

```bash
# Install Ruby via mise (version specified in mise.toml)
mise install ruby

# Install CocoaPods
gem install cocoapods
```

### Flutter Setup

```bash
# Install Flutter via mise
mise install

# Verify Flutter installation
flutter doctor

# Get dependencies
flutter pub get

# Generate code (Riverpod, Freezed)
flutter pub run build_runner build --delete-conflicting-outputs
```

### IDE Setup (Optional)

For VS Code, install the Flutter and Dart extensions.

For Android Studio, install the Flutter and Dart plugins.

## Local Build

### Android

#### Run on Connected Device

```bash
# List connected devices
flutter devices

# Run on a specific device (replace DEVICE_ID with your device ID)
flutter run -d DEVICE_ID

# Run on any available Android device
flutter run -d android
```

#### Build APK

```bash
# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release

# The APK will be at: build/app/outputs/flutter-apk/app-debug.apk (or app-release.apk)
```

#### Build App Bundle (for Play Store)

```bash
flutter build appbundle --release
```

### iOS

#### Run on Connected Device

```bash
# List connected devices
flutter devices

# Run on a specific iOS device (replace DEVICE_ID with your device ID)
flutter run -d DEVICE_ID

# Run on any available iOS device
flutter run -d ios
```

#### Run on Simulator

```bash
# Open iOS Simulator
open -a Simulator

# Run on simulator
flutter run -d simulator
```

#### Build for Device

```bash
# Debug build
flutter build ios --debug

# Release build (requires signing configuration)
flutter build ios --release
```

Note: For iOS device builds, you need to:
1. Open `ios/Runner.xcworkspace` in Xcode
2. Select your Development Team in Signing & Capabilities
3. Ensure the device is trusted and paired

## Testing

```bash
# Run all tests
flutter test

# Run tests with coverage
flutter test --coverage

# Run a specific test file
flutter test test/features/anga/models/anga_test.dart
```

## Code Quality

```bash
# Analyze code for issues
flutter analyze

# Format code
dart format lib test
```

## Screenshots

FYI: `bin/take-screenshots.sh` seems to be broken, but I don't have the time to debug it right now. -sd

Store listing screenshots can be generated from emulators using `bin/take-screenshots.sh`. Output goes to `tmp/screenshots/`.

```bash
# Take all screenshots (Android + iOS)
./bin/take-screenshots.sh

# Android only
./bin/take-screenshots.sh android

# iOS only
./bin/take-screenshots.sh ios
```

### Android (Google Play)

Google Play requires screenshots for phone, 7-inch tablet, and 10-inch tablet. The script creates AVDs for each:

| Form Factor | AVD Device   | Resolution  |
|-------------|-------------|-------------|
| Phone       | Pixel 4      | 1080x2280   |
| 7" Tablet   | Nexus 7 2013 | 1200x1920   |
| 10" Tablet  | Nexus 10     | 2560x1600   |

Requires an x86_64 system image. The script installs `system-images;android-30;google_apis;x86_64` if missing.

To take screenshots manually:

```bash
# Create and boot an AVD
$ANDROID_SDK/cmdline-tools/latest/bin/avdmanager create avd --name my_avd --package "system-images;android-30;google_apis;x86_64" --device "pixel_4"
$ANDROID_SDK/emulator/emulator -avd my_avd &

# Build, install, and launch
flutter build apk --debug
adb install build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n org.savebutton.app/.MainActivity

# Capture
adb exec-out screencap -p > screenshot.png

# Shut down
adb emu kill
```

### iOS (App Store)

App Store requires screenshots for 6.9" iPhone (1290x2796) and 13" iPad (2064x2752). Apple auto-scales for other device sizes.

| Form Factor | Simulator             | Resolution  |
|-------------|-----------------------|-------------|
| 6.9" iPhone | iPhone 16 Pro Max     | 1260x2736   |
| 13" iPad    | iPad Pro 13-inch (M4) | 2064x2752   |

To take screenshots manually:

```bash
# List available simulators
xcrun simctl list devices available

# Boot a simulator
xcrun simctl boot "iPhone 16 Pro Max"

# Build, install, and launch
flutter build ios --debug --simulator
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl launch booted org.savebutton.app

# Capture
xcrun simctl io booted screenshot screenshot.png

# Shut down
xcrun simctl shutdown booted
```

## Troubleshooting

### Gradle Lock Issues (Android)

If you see "Timeout waiting to lock" errors:

```bash
# Kill Gradle daemons
pkill -9 -f GradleDaemon

# Remove lock files
find ~/.gradle -name "*.lock" -delete

# Clean and rebuild
flutter clean
flutter pub get
flutter build apk --debug
```

### CocoaPods Issues (iOS)

If you see CocoaPods-related errors:

```bash
cd ios
pod deintegrate
pod install --repo-update
cd ..
flutter clean
flutter pub get
```

### Testing OAuth Sign-In Against a Local Server

Google OAuth rejects callback URLs with private IP addresses (e.g. `http://192.168.x.x:3000`). When testing "Sign In with Browser" on a real device against a local `savebutton-web` server, use [ngrok](https://ngrok.com/) to expose the server with a public URL.

1. **Install ngrok:**

   ```bash
   # macOS (Homebrew)
   brew install ngrok

   # Debian/Ubuntu (apt)
   curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
     | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
   echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
     | sudo tee /etc/apt/sources.list.d/ngrok.list
   sudo apt update && sudo apt install ngrok

   # Then authenticate
   ngrok config add-authtoken YOUR_AUTH_TOKEN
   ```

2. **Start the Rails server and ngrok tunnel:**

   ```bash
   # In one terminal, start savebutton-web
   cd ../savebutton-web
   bin/rails server

   # In another terminal, tunnel port 3000
   ngrok http 3000
   ```

3. **Register the ngrok URL with Google:**

   In Google Cloud Console, go to **APIs & Services > Credentials**, click your OAuth 2.0 Client ID, and add the ngrok callback URL to **Authorized redirect URIs**:

   ```
   https://your-subdomain.ngrok-free.app/auth/google_oauth2/callback
   ```

   Replace `your-subdomain` with the actual subdomain from the `ngrok http` output. Free ngrok accounts get a random subdomain that changes on each restart; paid accounts can reserve a stable subdomain to avoid re-registering the URI each time.

4. **Use the ngrok URL in the mobile app:**

   On the Account screen, set the server URL to the ngrok HTTPS URL (e.g. `https://XXXX-XX-XX-XX-XX.ngrok-free.app`). "Sign In with Browser" will now work with Google OAuth.

Note: Email/password sign-in does not use OAuth and works fine with a LAN IP address. Use the app's localhost detection to scan for your dev server on the local network.

## Releasing

Releases are triggered manually from the Codemagic dashboard ("Start new build" on the `master` branch). Codemagic builds both the Android AAB and iOS IPA and publishes them.

### Before every release: update `RELEASE_NOTES.md`

`RELEASE_NOTES.md` at the repo root is the single source of truth for end-user release notes on both stores. **Overwrite it with the notes for the upcoming release, commit, and push before starting the Codemagic build.**

Constraints:

- **Google Play caps release notes at 500 bytes.** Codemagic's build fails fast if `RELEASE_NOTES.md` exceeds this or is empty. Keep it short and user-facing.
- Apple allows up to 4000 characters in "What's New"; 500 is fine there too.
- Plain text only. No markdown — both stores render it as-is.

Example:

```
- Sign in with Google or Apple accounts
- Automatic LAN discovery for local dev servers
- Bug fixes and performance improvements
```

### Android (Google Play)

**Fully automatic.** Codemagic copies `RELEASE_NOTES.md` into `android/fastlane/metadata/android/en-US/changelogs/$PROJECT_BUILD_NUMBER.txt` at build time, then publishes the AAB to the production track (`track: production`, `submit_as_draft: false` in `codemagic.yaml`). Google Play picks up the release notes from the fastlane metadata path. No manual steps required.

> **Note:** This setup assumes Codemagic's `google_play` publisher auto-detects the fastlane changelogs directory. If the "What's New" field shows empty on Play Store after a release, the fix is to bypass auto-detection and call the [`google-play`](https://github.com/codemagic-ci-cd/cli-tools/blob/master/docs/google-play/README.md) CLI directly from a script step — the CLI accepts explicit `--bundles-release-notes` arguments. Verify on the first release using this setup and adjust if needed.

### iOS (App Store)

**Partially automatic.** Each build uploads a signed IPA to App Store Connect and distributes it to the "Save Button App Beta" TestFlight group. Submission to App Store review runs via `submit_to_app_store: true`, but an App Store Connect version only enters review if all required metadata is in place *at the moment Codemagic publishes*.

Export compliance is pre-answered via `ITSAppUsesNonExemptEncryption=false` in `ios/Runner/Info.plist` — the app uses only exempt encryption (HTTPS + PKCE hashing), so the France/export compliance prompts are skipped automatically. Do not flip this to `true` unless the app adds custom encryption beyond Apple-provided APIs.

Remaining manual steps per release (in App Store Connect):

1. **App Store** tab → if the new version (e.g. `1.1.N`) isn't already listed, click **"+"** next to iOS App to create it
2. Under **Build**, click **"+"** to attach the build Codemagic uploaded
3. Paste the contents of `RELEASE_NOTES.md` into **What's New in This Version**
4. Confirm screenshots and review info are current
5. Choose a release option (Manual / Automatic after approval / Scheduled)
6. Click **Add for Review** → **Submit for Review**

If you want step 3 automated in the future, add a Codemagic script step that calls `app-store-connect app-store-version-localizations` to push `RELEASE_NOTES.md` into the new version before `submit_to_app_store` fires.

## Codemagic

Use [codemagic-cli-tools](https://docs.codemagic.io/knowledge-codemagic/codemagic-cli-tools/) whenever possible:

* [`codemagic-cli-tools`](https://github.com/codemagic-ci-cd/cli-tools/blob/master/docs/codemagic-cli-tools/README.md)
* [`git-changelog`](https://github.com/codemagic-ci-cd/cli-tools/blob/master/docs/git-changelog/README.md)

**iOS:**
* [`app-store-connect`](https://github.com/codemagic-ci-cd/cli-tools/blob/master/docs/app-store-connect/README.md)
* [`xcode-project`](https://github.com/codemagic-ci-cd/cli-tools/blob/master/docs/xcode-project/README.md)
* [`keychain`](https://github.com/codemagic-ci-cd/cli-tools/blob/master/docs/keychain/README.md)

**Android:**
* [`android-app-bundle`](https://github.com/codemagic-ci-cd/cli-tools/blob/master/docs/android-app-bundle/README.md)
* [`android-keystore`](https://github.com/codemagic-ci-cd/cli-tools/blob/master/docs/android-keystore/README.md)
* [`google-play`](https://github.com/codemagic-ci-cd/cli-tools/blob/master/docs/google-play/README.md)
* [`universal-apk`](https://github.com/codemagic-ci-cd/cli-tools/blob/master/docs/universal-apk/README.md)
