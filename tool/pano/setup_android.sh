#!/bin/sh
# OpenCV 5.0 Android SDK, official 16-KiB-page fixed release. Native sources remain shared with iOS.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
temp_dir=$(mktemp -d -t opencv-android)
archive="$temp_dir/opencv.zip"
trap 'rm -rf "$temp_dir"' EXIT
curl -fL --retry 2 https://github.com/opencv/opencv/releases/download/5.0.0/opencv-5.0.0-android-sdk-16kb-page-fix.zip -o "$archive"
printf '%s  %s\n' 43ab9792096a4e52e97024913bb21c71a8adb884acbe0ddec3190a00b38b6619 "$archive" | shasum -a 256 -c -
mkdir -p "$root/android/third_party"
unzip -q -o "$archive" 'OpenCV-android-sdk/sdk/native/*' -d "$root/android/third_party"
