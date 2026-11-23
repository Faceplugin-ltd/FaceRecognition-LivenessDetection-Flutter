// swift-tools-version: 5.9
// Flutter plugin package for face_recognition_sdk (CocoaPods + SwiftPM).
// Vendored native runtimes live in ios/Frameworks/*.xcframework (created by
// dart run tool/bootstrap.dart / example/ios pod install from Drive .frameworks).
//
// Local path checkouts named Face-Recognition-LivenessDetection-Flutter hit Flutter SPM
// identity bugs (flutter/flutter#186881). The example disables SPM and uses
// CocoaPods.

import PackageDescription

let package = Package(
  name: "face_recognition_sdk",
  platforms: [
    .iOS("13.0")
  ],
  products: [
    .library(name: "face-recognition-sdk", targets: ["face_recognition_sdk"])
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework")
  ],
  targets: [
    .binaryTarget(
      name: "facerecognitionsdk",
      path: "../Frameworks/facerecognitionsdk.xcframework"
    ),
    .binaryTarget(
      name: "FacePluginSDK",
      path: "../Frameworks/FacePluginSDK.xcframework"
    ),
    .binaryTarget(
      name: "FacePlugin",
      path: "../Frameworks/FacePlugin.xcframework"
    ),
    .binaryTarget(
      name: "FaceDetect",
      path: "../Frameworks/FaceDetect.xcframework"
    ),
    .target(
      name: "face_recognition_sdk",
      dependencies: [
        "facerecognitionsdk",
        "FacePluginSDK",
        "FacePlugin",
        "FaceDetect",
        .product(name: "FlutterFramework", package: "FlutterFramework")
      ],
      path: "Sources/face_recognition_sdk",
      publicHeadersPath: ".",
      cSettings: [
        .headerSearchPath(".")
      ],
      linkerSettings: [
        .linkedFramework("UIKit"),
        .linkedFramework("Foundation"),
        .linkedLibrary("c++")
      ]
    )
  ]
)
