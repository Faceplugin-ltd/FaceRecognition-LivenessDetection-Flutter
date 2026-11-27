#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'face_recognition_sdk'
  s.version          = '0.1.0'
  s.summary          = 'FacePlugin Face Recognition SDK for Flutter'
  s.description      = <<-DESC
FacePlugin Face Recognition SDK — on-device face detect, templates, VideoWorker.
                       DESC
  s.homepage         = 'https://faceplugin.com'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'FacePlugin' => 'info@faceplugin.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'face_recognition_sdk/Sources/face_recognition_sdk/**/*.{h,m,mm}'
  s.public_header_files = 'face_recognition_sdk/Sources/face_recognition_sdk/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.libraries = 'c++'

  # Prefer flat ios-arm64 *.framework (from runtime.zip via python3 run_ios.py /
  # fp_releases.py). Fall back to xcframework / FacePlugin slice when present.
  frameworks = []
  missing = []
  %w[
    facerecognitionsdk
    FacePluginSDK
    FacePPlugin
    FaceDetect
  ].each do |base|
    xc = File.join(__dir__, 'Frameworks', "#{base}.xcframework")
    fw = File.join(__dir__, 'Frameworks', "#{base}.framework")
    # FacePPlugin is the ios-arm64 slice inside FacePlugin.xcframework.
    slice = File.join(__dir__, 'Frameworks', 'FacePlugin.xcframework', 'ios-arm64', "#{base}.framework")
    if File.directory?(fw)
      frameworks << "Frameworks/#{base}.framework"
    elsif File.directory?(xc)
      frameworks << "Frameworks/#{base}.xcframework"
    elsif File.directory?(slice)
      frameworks << "Frameworks/FacePlugin.xcframework/ios-arm64/#{base}.framework"
    else
      missing << fw
    end
  end
  unless missing.empty?
    raise Pod::Informative, <<~MSG

      Missing Face Recognition iOS frameworks (#{missing.size}):
      #{missing.map { |p| "  - #{p}" }.join("\n")}

      From the plugin root run: python3 run_ios.py
      (downloads runtime.zip into ios/Frameworks/ and slices device frameworks).
      Or unzip runtime.zip from
      https://github.com/Faceplugin-ltd/FaceRecognition-LivenessDetection-iOS/releases/tag/latest
      into ios/Frameworks/, then: cd example/ios && pod install
    MSG
  end
  s.vendored_frameworks = frameworks

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    # Ensure the plugin dylib loads the native SDK (needed when vendoring .framework).
    'OTHER_LDFLAGS' => '$(inherited) -framework "facerecognitionsdk" -framework "FacePluginSDK" -framework "FacePPlugin" -framework "FaceDetect" -framework "UniformTypeIdentifiers" -lc++'
  }
  s.swift_version = '5.0'
end
