# NeuroVerify SwiftUI demo

A small SwiftUI screen: pick a photo or video with `PhotosPicker`, upload it with the
NeuralDefend Swift SDK, and show the risk band, the rejection message, or guidance for the error.

- `DetectionModel` holds the logic: branch on `status` first, treat rejections as normal outcomes,
  and map each `NeuroVerifyError` case to a message.
- `ContentView` is the screen (iOS 17, macOS 14, and visionOS 1 or later).
- The tests run the model against the repository's shared contract fixtures through a mocked
  `URLProtocol`, so they need no network access or API key.

## Run the tests

```sh
cd packages/swift/Examples/NeuroVerifyDemo
swift test
```

To test on the iOS Simulator:

```sh
xcodebuild test -scheme NeuroVerifyDemo -destination "platform=iOS Simulator,name=iPhone 16"
```

## Use it in an app

1. In Xcode, create an iOS App project (SwiftUI interface).
2. Choose **File > Add Package Dependencies… > Add Local…** and select this
   `NeuroVerifyDemo` folder. Add the `NeuroVerifyDemo` library to the app target.
3. Show the screen from your `App`:

```swift
import NeuralDefend
import NeuroVerifyDemo
import SwiftUI

@main
struct DemoApp: App {
    // Staging only. Do not ship a production key in an app; issue short-lived keys from your
    // backend, or call the API from your backend instead.
    let client = try! NeuroVerifyClient.staging(apiKey: "<staging key>")

    var body: some Scene {
        WindowGroup {
            ContentView(model: DetectionModel(client: client))
        }
    }
}
```

`PhotosPicker` runs out of process, so the app needs no photo-library permission prompt.
