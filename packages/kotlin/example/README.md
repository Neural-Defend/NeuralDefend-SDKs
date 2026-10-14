# NeuroVerify Android example

A Jetpack Compose app that checks a photo or video with the NeuroVerify SDK. It shows how
to:

- pick media with the Android photo picker and upload it with `MediaInputs.fromUri`;
- upload the bundled sample image and video (copied from `tests/fixtures/media` at build
  time) as files;
- show upload progress, cancel an upload, and explain every error type in plain language;
- keep the client in a `ViewModel` and share one `OkHttpClient` across the app; and
- branch on `status` so rejections are shown as results rather than errors.

The key you type stays in memory for the session. The app exists for development with a
staging key; production apps should upload through their own backend. See
[Android credential safety](../README.md#android-credential-safety).

## Run it

From `packages/kotlin`, with an Android SDK configured:

```sh
./gradlew :example:installDebug
```

Then enter a staging API key, keep **Staging** selected, and tap **Sample image**.

## Tests

```sh
./gradlew :example:testDebugUnitTest              # ViewModel and Robolectric screen tests
./gradlew :example:connectedDebugAndroidTest      # the same screen tests on a device
./gradlew :example:assembleRelease                # R8-minified build
```

The screen tests replace the app's `ClientFactory` with one pointed at a local HTTPS
`MockWebServer`, so they never call the real API. The Robolectric run also saves
screenshots to `build/screenshots`.
