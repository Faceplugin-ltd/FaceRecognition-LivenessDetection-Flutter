# iOS frameworks

Same LX runtimes as `Face-Recognition-LivenessDetection-iOS`:

```text
facerecognitionsdk.framework
FacePluginSDK.xcframework
FacePlugin.xcframework
FaceDetect.xcframework
```

Copy them from the iOS app repo (or `python3 scripts/export.py` in Face-Recognition-LivenessDetection-iOS-LX-SDK). Device `ios-arm64` only.

Then: `dart run tool/bootstrap.dart` and `cd example/ios && pod install`.
