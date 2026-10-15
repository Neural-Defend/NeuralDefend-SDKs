# NeuroVerify Flutter example

A minimal Flutter app that picks a photo or video with
[`image_picker`](https://pub.dev/packages/image_picker), uploads it with the
`neuraldefend` package, and shows the normalized result, upload progress, and
cancellation.

> This demo compiles the API key into the app so it can call NeuroVerify
> directly. Use a **staging** key only. Anyone who installs an app can extract
> keys from it, so production apps should upload media to your own backend and
> call NeuroVerify from there.

## Run

The repository does not check in platform folders. Generate the ones you need
once, then run with a staging key:

```sh
cd packages/dart/example/flutter_app
flutter create --platforms=android,ios,web --project-name neuraldefend_flutter_example .
flutter run --dart-define=NEURALDEFEND_API_KEY=<staging key>
```

`flutter create` keeps the existing `lib/` and `test/` files.

Add `--dart-define=NEURALDEFEND_PRODUCTION=true` to target the production API.

### iOS and macOS

`image_picker` needs photo library usage descriptions. Add these keys to
`ios/Runner/Info.plist`:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Choose a photo or video to check its authenticity.</string>
<key>NSCameraUsageDescription</key>
<string>Capture a photo or video to check its authenticity.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Record audio with videos for authenticity checks.</string>
```

### Android

Gallery picking needs no extra permissions. `flutter create` grants the
`INTERNET` permission only to debug and profile builds, so add it to
`android/app/src/main/AndroidManifest.xml` before building a release:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

## Test

```sh
flutter test
```

The widget tests inject a mock HTTP client and picker, so they do not need a
device, network access, or an API key.
