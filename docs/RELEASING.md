# Releasing

Releases are built by CI and signed by hand. The keystore never leaves the
maintainer's machine, and it never goes into GitHub secrets.

The APKs published here are the reference F-Droid rebuilds and verifies against,
so this process is more constrained than it looks. Read [Why it is like
this](#why-it-is-like-this) before changing any of it.

## Cutting a release

1. **Bump the version.** Seven places. Searching the repository for the old
   version string is the quickest way to be sure none is missed.

   - `app/pubspec.yaml`: `version: X.Y.Z+N`
   - `app/lib/src/update_check/app_version.dart`: the `appVersion` constant.
     Keep it equal to the pubspec `version:`. It is the baseline the update
     check compares against and what the settings screen shows, so bumping it
     also updates the displayed version. A test holds the two equal.
   - `app/lib/src/screens/changelog/release_notes.dart`: a new entry at the
     top of `releaseNotes`
   - `fastlane/metadata/android/en-US/changelogs/<N>.txt`, named for the build
     number, not the version
   - `README.md`: the status line
   - `.github/ISSUE_TEMPLATE/bug_report.yml`: the version placeholder
   - `site/src/components/hero.html`: the version chip

2. **Verify.** `flutter analyze` and `flutter test` from `app/`, both clean.

3. **Merge to `main`** and tag it there:

   ```sh
   git tag vX.Y.Z origin/main
   git push origin vX.Y.Z
   ```

   Pushing the tag triggers `.github/workflows/release.yml`, which builds the
   three split APKs **unsigned** at `/tmp/build` and uploads them as the
   `unsigned-apks` artifact.

4. **Download the artifact** from the workflow run.

5. **Sign each APK locally.** Use build-tools **34**, not the newest one:
   apksigner 35 and later write APKs that F-Droid's `apksigcopier` cannot
   verify, which silently breaks reproducible builds.

   ```sh
   # apksigner from build-tools 34 in the Android SDK; KEYSTORE is wherever you
   # keep the release key, which is not in this repository.
   for abi in arm64-v8a armeabi-v7a x86_64; do
     apksigner sign --ks "$KEYSTORE" --ks-key-alias atrium \
       --out "signed/app-$abi-release.apk" "unsigned/app-$abi-release.apk"
   done
   ```

6. **Check what you signed** before it goes anywhere:

   ```sh
   apksigner verify --print-certs signed/app-arm64-v8a-release.apk
   ```

   It must report `CN=Atrium, O=Atrium` and SHA-256
   `5ebad1ff2f9cdc63f28b364addf9e858330db26909d9eba8dfbccb998de37351`. A
   different fingerprint means the wrong key, and shipping it would break
   updates for everyone.

7. **Publish** the release with all three signed APKs attached. The asset names
   have to keep matching the `binary:` URLs in fdroiddata's
   `metadata/app.atrium.yml`, or F-Droid cannot find them.

8. **Let F-Droid pick it up.** There is nothing to edit by hand. The recipe at
   `metadata/app.atrium.yml` in fdroiddata carries `UpdateCheckMode: Tags` and
   `AutoUpdateMode: Version`, so their bot notices the new tag, appends the
   three per-ABI build blocks itself, and moves `CurrentVersion` /
   `CurrentVersionCode`. It then builds and publishes on F-Droid's own
   schedule, which usually lands the new version a few days after the tag, so
   f-droid.org trailing the releases page for a while is expected rather than a
   fault. Edit the recipe by hand only when the recipe itself has to change (a
   new build step, a changed dependency, different metadata) - never for a
   routine version bump.

   Version codes remain `build number * 10 + abi`, where abi is 1 armeabi-v7a,
   2 arm64-v8a, 3 x86_64: see the override at the foot of
   `app/android/app/build.gradle.kts`, which must stay in step with the
   `VercodeOperation` in their metadata.

## Why it is like this

**The build path is part of the APK.** Flutter writes the absolute path of
`.dart_tool/flutter_build/dart_plugin_registrant.dart` into the AOT snapshot as
a string constant. Build at a different path and the bytes differ. There is no
Dart equivalent of `--remap-path-prefix`; matching the path is the only known
fix. This is why the workflow copies the checkout to `/tmp/build`, and why
fdroiddata's recipe moves its checkout to exactly the same place. **Changing one
without the other silently breaks verification.**

**Which is also why releases cannot be built by hand any more.** A local build
on another OS, or at any other path, can never match a Debian build at
`/tmp/build`. Every published APK has to come out of the workflow.

**The APKs are unsigned until step 5 on purpose.** F-Droid rebuilds the app from
source on their own machines, then copies the signature off the published APK
onto their build and asks apksigner to verify it. That only works if their build
carries no signature, which is why `app/android/app/build.gradle.kts` attaches
no signing config when `key.properties` is absent. It also means the keystore is
only ever needed on one machine.

**Everything is pinned.** Flutter, JDK and NDK versions all change the emitted
bytes. The workflow pins them and fdroiddata's recipe reads the Flutter version
out of the workflow, so the two cannot disagree. Bump them deliberately.

**The jni library has its build-id stripped.** `app/android/build.gradle.kts`
passes `--build-id=none` for it. The linker otherwise derives that id from
object data carrying the NDK's install path, so the same source built against
an NDK in a different directory produces a library differing in exactly those
20 bytes, which fails verification. Removing the id means no build of this app
has to care where its NDK lives.

## If verification fails

F-Droid's CI runs the comparison on every push to the merge request, so iterate
there rather than by cutting releases. The usual suspects, roughly in order:

- the build path drifted between the workflow and the recipe
- a toolchain version differs (Flutter, JDK, NDK, build-tools)
- the APK was signed with apksigner 35 or newer
- the wrong artifact shape: F-Droid must build the same split as the `binary:`
  URL points at, never a universal APK against split references
