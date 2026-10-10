# android-dev

Tooling repo. Do not turn it into an apps monorepo or a toolchain tarball.

- Pin versions in `versions.env`. Never commit JDK/SDK/NDK/GGUF/APK/keystores.
- Fold transport: SSH host `fold` (Termux) → device-local adb. Do not scan
  the rotating Wireless Debugging port over the network.
- Preserve ADB pairing identity and app signing certificates.
- Iterative deploy: `adb install -r -d -t`. Never uninstall/`pm clear` to
  "fix" an iteration.
- `lib/fold.sh` is extracted from `xrctl`. Do not break `xrctl` callers;
  do not migrate XR projects here.
- Companion app is `atacolak/android-transcribe`. Use that repo's Gradle
  wrapper.
- `scripts/ci-smoke.sh` must pass without a phone.
