#!/usr/bin/env bash
# Builds the signed APK for a GitHub release: build/release/jnote-<version>.apk and its SHA-256.
# It builds the last commit in a clean folder under /tmp, so no local paths end up in the APK.
# See docs/RELEASING.md.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f android/key.properties ]; then
  echo "android/key.properties is missing: releases must be signed with the jNote release key (see docs/RELEASING.md)." >&2
  exit 1
fi
if ! git diff --quiet HEAD; then
  echo "Commit your changes first: the release is built from the last commit." >&2
  exit 1
fi
version=$(sed -n 's/^version: *\([0-9][0-9.]*\)+.*/\1/p' pubspec.yaml)

# Flutter embeds the build folder's path in the app code, so build where it holds no user name.
work=$(mktemp -d /tmp/jnote-release.XXXXXX)
trap 'rm -rf "$work"' EXIT
git archive HEAD | tar -x -C "$work"
cp android/key.properties "$work/android/"
(cd "$work" && flutter pub get >/dev/null && flutter build apk --release --obfuscate --split-debug-info=build/symbols)

mkdir -p build/release "build/symbols/$version"
apk="build/release/jnote-$version.apk"
cp "$work/build/app/outputs/flutter-apk/app-release.apk" "$apk"
cp -r "$work/build/symbols/." "build/symbols/$version/"
(cd build/release && sha256sum "jnote-$version.apk" > "jnote-$version.apk.sha256")

sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:?Set ANDROID_HOME to the Android SDK}}"
apksigner=$(ls -d "$sdk"/build-tools/*/apksigner | tail -1)
certs=$("$apksigner" verify --print-certs "$apk")
if grep -q "CN=Android Debug" <<<"$certs"; then
  echo "$apk is signed with the debug key, not the release key." >&2
  exit 1
fi
if unzip -p "$apk" | grep -aq "$HOME"; then
  echo "$apk contains your home folder path ($HOME); do not publish it." >&2
  exit 1
fi

echo "Built $apk ($(du -h "$apk" | cut -f1))"
grep -m1 "certificate DN" <<<"$certs"
cat "build/release/jnote-$version.apk.sha256"
