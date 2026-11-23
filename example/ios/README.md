# iOS example host

Requirements: **Flutter 3.44+**, **macOS + Xcode**, physical device recommended.

Demo license bundle id: **`com.faceplugin.facerecognition.app`**
(Android demo `applicationId` is `com.faceplugin.facerecognitionsdk` — different on purpose.)

1. Unzip the frameworks from the iOS release into the **plugin** folder (not `example/ios/`):

   ```text
   Face-Recognition-LivenessDetection-Flutter/ios/Frameworks/
   ├── facerecognitionsdk.framework
   ├── FacePluginSDK.xcframework
   ├── FacePlugin.xcframework
   └── FaceDetect.xcframework
   ```

2. From the **plugin root**: `dart run tool/bootstrap.dart` (should print `ok:` for each framework)
3. `cd example && flutter pub get`
4. `cd ios && pod install`  ← required again after copying frameworks
5. Open `Runner.xcworkspace` and set **Team** / signing

Camera / photos: `Podfile` `post_install` sets `PERMISSION_CAMERA=1` and
`PERMISSION_PHOTOS=1` for `permission_handler`.


## Get the runtimes

**[iOS runtime — GitHub release](https://github.com/Faceplugin-ltd/FaceRecognition-LivenessDetection-iOS/releases/tag/latest)**
