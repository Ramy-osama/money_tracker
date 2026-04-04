# Money Tracker App - Setup Guide (Windows)

## Step 1: Install Flutter SDK

1. Download Flutter SDK from: https://docs.flutter.dev/get-started/install/windows/mobile
2. Extract the zip to `C:\flutter` (or your preferred location)
3. Add Flutter to your PATH:
   - Open **System Properties** > **Environment Variables**
   - Under **User variables**, edit `Path` and add `C:\flutter\bin`
4. Open a new terminal and verify:
   ```
   flutter --version
   ```

## Step 2: Install Android Studio

1. Download from: https://developer.android.com/studio
2. Run the installer with default options
3. On first launch, let it download the Android SDK
4. Go to **SDK Manager** > **SDK Tools** and ensure these are installed:
   - Android SDK Build-Tools
   - Android SDK Command-line Tools
   - Android SDK Platform-Tools
5. Accept Android licenses:
   ```
   flutter doctor --android-licenses
   ```

## Step 3: Verify Installation

```
flutter doctor
```

You should see checkmarks for Flutter and Android toolchain. You can ignore Chrome/Visual Studio items since we only need Android.

## Step 4: Set Up the Project

Open a **PowerShell terminal** in the `money_tracker` folder and run these commands in order:

```powershell
cd C:\Users\Ramy\Desktop\money_tracker

# Generate Android platform files around existing source code
flutter create --org com.ramy --project-name money_tracker .

# Configure Android permissions for SMS, microphone, etc.
powershell -ExecutionPolicy Bypass -File setup_android.ps1

# Install all dependencies
flutter pub get
```

## Step 5: Build the APK

Generate a release APK:

```
flutter build apk --release
```

The APK will be at:
```
build\app\outputs\flutter-apk\app-release.apk
```

If you want a smaller APK for a specific architecture (recommended):
```
flutter build apk --release --split-per-abi
```
This creates separate APKs. For most modern phones, use the `arm64-v8a` version.

## Step 6: Install on Your Phone

1. Connect your Android phone via USB
2. Enable **Developer Options** on your phone:
   - Go to Settings > About Phone > tap **Build Number** 7 times
3. Enable **USB Debugging** in Developer Options
4. Transfer the APK file to your phone
5. On the phone, open the APK and tap **Install**
   - You may need to enable "Install from Unknown Sources" for your file manager

## Alternative: Direct Install via ADB

If you have ADB set up (comes with Android Studio):

```
adb install build\app\outputs\flutter-apk\app-release.apk
```

## Troubleshooting

- If `flutter doctor` shows issues, follow the suggested fixes
- If SMS permission is denied at runtime, go to phone Settings > Apps > Money Tracker > Permissions > SMS > Allow
- The app needs "Background activity" permission for SMS auto-tracking to work when the app is closed
