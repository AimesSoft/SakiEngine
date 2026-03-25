#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_steamworks.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_steamworks'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter plugin project.'
  s.description      = <<-DESC
A new Flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'

  # Steam SDK
  s.vendored_libraries = 'libsteam_api.dylib'
  s.xcconfig = {
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/../third_party/steamworks/public/steam"',
    'LD_RUNPATH_SEARCH_PATHS' => '$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks',
    'OTHER_LDFLAGS' => '-lc++'
  }

  # If your plugin requires a privacy manifest, for example if it collects user
  # data, update the PrivacyInfo.xcprivacy file to describe your plugin's
  # privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'flutter_steamworks_privacy' => ['Resources/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'

  # Copy Steam library to app bundle
  s.script_phases = [{
    :name => 'Copy Steam Library',
    :execution_position => :after_compile,
    :input_files => ['${PODS_TARGET_SRCROOT}/libsteam_api.dylib'],
    :output_files => [
      '${TARGET_BUILD_DIR}/flutter_steamworks.framework/Versions/A/libsteam_api.dylib'
    ],
    :script => <<-SCRIPT
set -e

SRC="${PODS_TARGET_SRCROOT}/libsteam_api.dylib"

if [ -f "${SRC}" ]; then
  DEST="${TARGET_BUILD_DIR}/flutter_steamworks.framework/Versions/A"
  if [ -d "${DEST}" ]; then
    cp -f "${SRC}" "${DEST}/libsteam_api.dylib"

    if command -v /usr/bin/codesign >/dev/null 2>&1; then
      /usr/bin/codesign --force --sign - "${DEST}/libsteam_api.dylib"
      /usr/bin/codesign --force --sign - "$(dirname "$(dirname "${DEST}")")"
    fi
  fi
fi
SCRIPT
  }]
end
