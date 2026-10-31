#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
node -e 'const v=process.versions.node.split(".").map(Number); if(v[0]!==22 || v[1]<22 || (v[1]===22 && v[2]<1)) throw Error("Use Node >=22.22.1 <23")'
: "${JAVA_HOME:?Set JAVA_HOME to JDK 17}"
: "${ANDROID_HOME:?Set ANDROID_HOME to the installed Android SDK}"
key="${UNICLIP_PERSONAL_KEYSTORE:-$PWD/.personal/signing/adb-fix-test.keystore}"
test -f "$key" || { echo "Restore the original test signing keystore before building." >&2; exit 1; }
# The preserved test APK uses androiddebugkey / android, with a unique certificate.
# This key is for the personal test application only; keep it out of Git.
npm ci --ignore-scripts
npm run postinstall
npm run build --workspaces --if-present
npm run type-check
# Uses this checkout's exact Engine pin. Never substitute the historical AAR here.
npm run core:prepare -- --platform android
node scripts/verify-unified-engine-core.mjs --prepared --platform android
APP_VARIANT=test npx expo prebuild --platform android --no-install
cp "$key" android/app/debug.keystore
(cd android && ./gradlew :app:assembleRelease -PreactNativeArchitectures=arm64-v8a --no-daemon)
mkdir -p .personal/apk
find android/app/build/outputs/apk/release -name '*.apk' -exec cp {} .personal/apk/ \;
shasum -a 256 .personal/apk/*.apk
printf 'Built personal test APKs in %s/.personal/apk\n' "$PWD"
