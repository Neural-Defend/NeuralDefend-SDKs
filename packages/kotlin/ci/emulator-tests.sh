#!/usr/bin/env bash
# Boots a headless Android emulator and runs the example app's instrumented tests on it.
#
# Usage: ci/emulator-tests.sh <api-level> [output-dir]
# Set EMULATOR_RECORD_SCREEN=1 to save a screen recording of the run in the output directory.
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

# Recent images need more than the default 2 GB of RAM and data partition to install and run
# the APKs. Older images encrypt the whole data partition on first boot, so a larger one
# there only slows the boot down.
sizing=()
if ((${api%%.*} >= 30)); then
  sizing=(-memory 4096 -partition-size 6144)
fi
"$emulator" -avd "$avd" -no-window -no-audio -no-boot-anim -no-snapshot -no-metrics "${sizing[@]}" \
  -gpu swiftshader_indirect -camera-back none -camera-front none >"$output/emulator.log" 2>&1 &
emulator_pid=$!

recorder_pid=""
# adb blocks while no device is online, so every cleanup call is bounded.
cleanup() {
  if [[ -n "$recorder_pid" ]]; then
    # Signalling the local adb process does not reach screenrecord on older images, and an
    # unsignalled recording is never finalised.
    timeout 10 "$adb" shell 'pkill -INT screenrecord || killall -INT screenrecord' >/dev/null 2>&1 || true
    sleep 3
    kill "$recorder_pid" 2>/dev/null || true
    timeout 60 "$adb" pull /sdcard/instrumented-tests.mp4 "$output/instrumented-tests-api-${api}.mp4" >/dev/null 2>&1 || true
  fi
  timeout 60 "$adb" logcat -d >"$output/logcat.txt" 2>/dev/null || true
  timeout 30 "$adb" emu kill >/dev/null 2>&1 || true
  sleep 5
  kill "$emulator_pid" 2>/dev/null || true
}
trap cleanup EXIT

device_ready() {
  [[ "$(timeout 10 "$adb" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]] &&
    timeout 10 "$adb" shell pm path android 2>/dev/null | grep -q '^package:'
}

"$adb" start-server >/dev/null
deadline=$((SECONDS + boot_timeout_seconds))
until device_ready; do
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

# Opt-in because screenrecord's virtual display aborts SurfaceFlinger (and with it
# system_server) on the API 37 google_apis image. It stops by itself after three minutes.
if [[ "${EMULATOR_RECORD_SCREEN:-0}" == "1" ]]; then
  "$adb" shell screenrecord --time-limit 180 /sdcard/instrumented-tests.mp4 &
  recorder_pid=$!
fi

./gradlew :example:connectedDebugAndroidTest --console=plain
report=example/build/reports/androidTests/connected/debug/index.html
cp -R example/build/reports/androidTests/connected "$output/report" 2>/dev/null || true

# AGP reports success even when it could not install the APKs, so check what actually ran.
if [[ ! -f "$report" ]]; then
  echo "::error::No instrumented test report was produced for API ${api}." >&2
  exit 1
fi
mapfile -t counters < <(grep -oE '<div class="counter">[0-9]+</div>' "$report" | grep -oE '[0-9]+')
if ((${#counters[@]} < 2)) || ((counters[0] == 0)) || ((counters[1] != 0)); then
  echo "::error::API ${api} ran ${counters[0]:-0} instrumented tests with ${counters[1]:-unknown} failures." >&2
  exit 1
fi
echo "API ${api}: ${counters[0]} instrumented tests passed."
