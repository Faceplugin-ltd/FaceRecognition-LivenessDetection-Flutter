# Placeholder for optional in-package frameworks

CocoaPods vendors frameworks from `ios/Frameworks/` (see that README).

Drop the frameworks from the iOS release there:

- `facerecognitionsdk.framework`
- `FacePluginSDK.xcframework`
- `FacePlugin.xcframework`
- `FaceDetect.xcframework`

This folder is reserved if a future SPM `Package.swift` needs in-package binaries
(relative `../Frameworks` breaks under Flutter’s ephemeral Packages layout).


## Get the runtimes

**[iOS runtime — GitHub release](https://github.com/Faceplugin-ltd/FaceRecognition-LivenessDetection-iOS/releases/tag/latest)**
