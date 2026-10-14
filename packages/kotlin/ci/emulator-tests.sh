#!/usr/bin/env bash
# Boots a headless Android emulator and runs the example app's instrumented tests on it.
#
# Usage: ci/emulator-tests.sh <api-level> [output-dir]
# Requires ANDROID_HOME (or ANDROID_SDK_ROOT), Java 21, and a KVM-capable Linux host.
set -euo pipefail

api="${1:?usage: emulator-tests.sh <api-level> [output-dir]}"
output="${2:-build/emulator}"
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:?ANDROID_HOME is not set}}"
image="system-images;android-${api};google_apis;x86_64"
avd="neuraldefend-api-${api//./-}"
boot_timeout_seconds=900

cd "$(dirname "$0")/.."
mkdir -p "$output"
output="$(cd "$output" && pwd)"

sdkmanager="$sdk/cmdline-tools/latest/bin/sdkmanager"
avdmanager="$sdk/cmdline-tools/latest/bin/avdmanager"
adb="$sdk/platform-tools/adb"
emulator="$sdk/emulator/emulator"

# avdmanager honours XDG_CONFIG_HOME (set on GitHub runners) but the emulator does not, so
# without a shared ANDROID_AVD_HOME the emulator cannot find the AVD that was just created.
export ANDROID_AVD_HOME="${ANDROID_AVD_HOME:-$HOME/.android/avd}"
mkdir -p "$ANDROID_AVD_HOME"

yes | "$sdkmanager" --licenses >/dev/null || true
"$sdkmanager" --install "platform-tools" "emulator" "$image" >/dev/null
echo no | "$avdmanager" create avd --force --name "$avd" --package "$image" --device pixel_5 >/dev/null
if ! "$emulator" -list-avds | grep -qx "$avd"; then
  echo "::error::The emulator cannot see AVD ${avd} in ${ANDROID_AVD_HOME}." >&2
  exit 1
fi

"$emulator" -avd "$avd" -no-window -no-audio -no-boot-anim -no-snapshot -no-metrics \
  -gpu swiftshader_indirect -camera-back none -camera-front none >"$output/emulator.log" 2>&1 &
emulator_pid=$!

recorder_pid=""
# adb blocks while no device is online, so every cleanup call is bounded.
cleanup() {
  if [[ -n "$recorder_pid" ]]; then
    kill -INT "$recorder_pid" 2>/dev/null || true
    wait "$recorder_pid" 2>/dev/null || true
    sleep 2
    timeout 60 "$adb" pull /sdcard/instrumented-tests.mp4 "$output/instrumented-tests-api-${api}.mp4" >/dev/null 2>&1 || true
  fi
  timeout 60 "$adb" logcat -d >"$output/logcat.txt" 2>/dev/null || true
  timeout 30 "$adb" emu kill >/dev/null 2>&1 || true
  sleep 5
  kill "$emulator_pid" 2>/dev/null || true
}
trap cleanup EXIT

"$adb" start-server >/dev/null
deadline=$((SECONDS + boot_timeout_seconds))
until [[ "$("$adb" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do
  if ((SECONDS > deadline)); then
    echo "::error::Emulator for API ${api} did not boot within ${boot_timeout_seconds}s." >&2
    tail -50 "$output/emulator.log" >&2 || true
    exit 1
  fi
  if ! kill -0 "$emulator_pid" 2>/dev/null; then
    echo "::error::Emulator for API ${api} exited during boot." >&2
    tail -50 "$output/emulator.log" >&2 || true
    exit 1
  fi
  sleep 5
done
echo "Emulator API ${api} booted after ${SECONDS}s."

for setting in window_animation_scale transition_animation_scale animator_duration_scale; do
  "$adb" shell settings put global "$setting" 0
done
"$adb" shell input keyevent 82 || true

# screenrecord stops by itself after three minutes; the tests take far less.
"$adb" shell screenrecord --time-limit 180 /sdcard/instrumented-tests.mp4 &
recorder_pid=$!

./gradlew :example:connectedDebugAndroidTest --console=plain
cp -R example/build/reports/androidTests/connected "$output/report" 2>/dev/null || true
