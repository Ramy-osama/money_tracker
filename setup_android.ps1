# Money Tracker - Android Configuration Script
# Run this AFTER `flutter create .` to configure Android permissions

$manifestPath = "android\app\src\main\AndroidManifest.xml"

if (-not (Test-Path $manifestPath)) {
    Write-Host "ERROR: AndroidManifest.xml not found. Run 'flutter create .' first." -ForegroundColor Red
    exit 1
}

Write-Host "Configuring Android manifest for Money Tracker..." -ForegroundColor Cyan

$content = Get-Content $manifestPath -Raw

# Add permissions before <application> tag
$permissions = @"
    <uses-permission android:name="android.permission.READ_SMS"/>
    <uses-permission android:name="android.permission.RECEIVE_SMS"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.INTERNET"/>

"@

if ($content -notmatch "READ_SMS") {
    $content = $content -replace "(<application)", "$permissions    `$1"
    Write-Host "  + Added SMS, Audio, and Storage permissions" -ForegroundColor Green
}

# Add SMS receiver inside <application> tag, before closing </application>
$receiver = @"

        <receiver android:name="com.shounakmulay.telephony.sms.IncomingSmsReceiver"
            android:permission="android.permission.BROADCAST_SMS"
            android:exported="true">
            <intent-filter>
                <action android:name="android.provider.Telephony.SMS_RECEIVED"/>
            </intent-filter>
        </receiver>
"@

if ($content -notmatch "IncomingSmsReceiver") {
    $content = $content -replace "(</application>)", "$receiver`n    `$1"
    Write-Host "  + Added SMS BroadcastReceiver" -ForegroundColor Green
}

# Update app label
$content = $content -replace 'android:label="[^"]*"', 'android:label="Money Tracker"'
Write-Host "  + Set app label to 'Money Tracker'" -ForegroundColor Green

Set-Content $manifestPath -Value $content

# Set minimum SDK version to 21 (required for telephony package)
$buildGradle = "android\app\build.gradle"
if (Test-Path $buildGradle) {
    $gradleContent = Get-Content $buildGradle -Raw
    # Update minSdk if using old format
    if ($gradleContent -match "minSdk\s*=?\s*flutter\.minSdkVersion") {
        $gradleContent = $gradleContent -replace "minSdk\s*=?\s*flutter\.minSdkVersion", "minSdk = 23"
        Write-Host "  + Set minSdkVersion to 23" -ForegroundColor Green
    }
    elseif ($gradleContent -match "minSdkVersion\s+\d+") {
        $gradleContent = $gradleContent -replace "minSdkVersion\s+\d+", "minSdkVersion 23"
        Write-Host "  + Set minSdkVersion to 23" -ForegroundColor Green
    }

    # Enable multidex
    if ($gradleContent -notmatch "multiDexEnabled") {
        $gradleContent = $gradleContent -replace "(defaultConfig\s*\{)", "`$1`n            multiDexEnabled true"
        Write-Host "  + Enabled multiDex" -ForegroundColor Green
    }

    Set-Content $buildGradle -Value $gradleContent
}

# Also check for build.gradle.kts (newer Flutter projects use Kotlin DSL)
$buildGradleKts = "android\app\build.gradle.kts"
if (Test-Path $buildGradleKts) {
    $gradleContent = Get-Content $buildGradleKts -Raw
    if ($gradleContent -match "minSdk\s*=\s*flutter\.minSdkVersion") {
        $gradleContent = $gradleContent -replace "minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 23"
        Write-Host "  + Set minSdkVersion to 23 (build.gradle.kts)" -ForegroundColor Green
    }

    if ($gradleContent -notmatch "multiDexEnabled") {
        $gradleContent = $gradleContent -replace "(defaultConfig\s*\{)", "`$1`n            multiDexEnabled = true"
        Write-Host "  + Enabled multiDex (build.gradle.kts)" -ForegroundColor Green
    }

    Set-Content $buildGradleKts -Value $gradleContent
}

Write-Host ""
Write-Host "Android configuration complete!" -ForegroundColor Green
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Run: flutter pub get"
Write-Host "  2. Run: flutter build apk --release"
Write-Host "  3. APK will be at: build\app\outputs\flutter-apk\app-release.apk"
