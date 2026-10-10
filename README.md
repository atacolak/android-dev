# android-dev

Portable Linux toolchain and Fold device harness for Android app work.
Not an apps monorepo and not a dump of JDK/SDK/NDK binaries.

Pinned versions live in [`versions.env`](versions.env). Bootstrap is
idempotent and writes under `~/.local/opt` by default.

Companion app: [atacolak/android-transcribe](https://github.com/atacolak/android-transcribe)
(fork of [notune/android_transcribe_app](https://github.com/notune/android_transcribe_app)).

## New host

```sh
git clone git@github.com:atacolak/android-dev.git
cd android-dev
# cmake + ninja from the host package manager (not installed by bootstrap)
sudo apt-get install -y cmake ninja-build curl unzip tar python3
./scripts/bootstrap.sh
./scripts/doctor.sh
eval "$(./bin/adev env)"
```

Bootstrap installs, if missing:

| piece | pin | default path |
|---|---|---|
| JDK | Temurin 17 | `~/.local/opt/jdk-17` |
| Android SDK | API 35, build-tools 35.0.0 | `~/.local/opt/android-sdk` |
| NDK | 28.0.13004108 (side-by-side) | `$SDK/ndk/28.0.13004108` |
| Rust target | `aarch64-linux-android` | rustup |
| cargo-ndk | 4.1.2 | `~/.cargo/bin` |

Existing installs are reused. NDK 30 already on a machine is left in place.

## Clone the companion app

```sh
./bin/adev clone-app              # default: ~/workspace/android-transcribe
# adds origin (atacolak fork) and upstream (notune)
```

Create `local.properties` in the app (`sdk.dir=...`). `adev build` passes
`-Dorg.gradle.java.home` so a stale Studio JBR pin in `gradle.properties`
does not break the build. Use the **app's** Gradle wrapper; this repo does
not vendor Gradle.

## Build / test / deploy

```sh
source scripts/env.sh             # or: eval "$(./bin/adev env)"
./bin/adev build                  # ./gradlew assembleDebug
./bin/adev test                   # cargo test in the app (no phone)

# Fold (default profile): workstation -> SSH host `fold` (Termux)
# -> Fold-local adb -> 127.0.0.1:<rotating wireless port>
./bin/adev device status
./bin/adev adb ensure
./bin/adev deploy path/to/app-debug.apk --package dev.notune.transcribe
./bin/adev launch dev.notune.transcribe
./bin/adev smoke dev.notune.transcribe
./bin/adev logs dev.notune.transcribe
./bin/adev screenshot /tmp/fold.png
```

USB/emulator:

```sh
ADEV_PROFILE=generic ./bin/adev device status
```

`adev` never uninstalls, never `pm clear`s, never deletes Termux ADB keys,
and never force-pushes. Iterative installs are `adb install -r -d -t`.

## Fold pairing (rare)

Pair once per ADB identity. If `adev adb ensure` cannot see `device`:

1. Fold: Developer options → Wireless debugging → Pair with pairing code
2. `./bin/adev adb pair <6-digit> <pairing-port>`

Do not recreate pairing because a script deleted `~/.android` in Termux.

The Fold adapter in `lib/fold.sh` is extracted from `xrctl`. XR projects
keep using `~/workspace/xr/scripts/xrctl`; this repo does not replace it.

## CI

```sh
./scripts/ci-smoke.sh     # no phone, no SDK download
```

GitHub Actions runs the same script.

## What is not in git

GGUF models, APKs, JDKs, SDKs, NDKs, keystores, recordings, secrets.
Tool *versions* and bootstrap URLs are versioned.
