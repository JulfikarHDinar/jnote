# Releasing a new version

jNote is published as an APK on [GitHub Releases](https://github.com/JulfikarHDinar/jnote/releases). Every release follows the same steps, so people can install it over their current version and keep their notes.

## One-time setup

1. Create the release key and keep it forever, outside the repo:
   ```bash
   mkdir -p ~/AndroidApp/keys
   keytool -genkeypair -v -keystore ~/AndroidApp/keys/jnote-release.jks -keyalg RSA -keysize 4096 -validity 10000 -alias jnote
   ```
2. Copy `android/key.properties.example` to `android/key.properties` and fill in the paths and passwords. The file is git-ignored.
3. Back up the `.jks` file and its password. Without them, no future version can install over the copies people already have.

## Version numbers

`pubspec.yaml` holds `version: MAJOR.MINOR.PATCH+BUILD`:
- **PATCH** for fixes (`1.0.1+2`), **MINOR** for new features (`1.1.0+3`), **MAJOR** for changes that break compatibility, such as the export format (`2.0.0+4`).
- **BUILD** goes up by 1 with every release. Android refuses an update whose number is not higher.

## Steps

1. Update `version:` in `pubspec.yaml`.
2. Add a section for the version at the top of `CHANGELOG.md`, and commit:
   `git commit -am "jNote <version>: <what changed>"`
3. Run `tool/build_release.sh`. It builds the last commit in a clean folder under `/tmp`, so no local paths end up in the app. You get the signed APK as `build/release/jnote-<version>.apk` and its SHA-256. The script stops if the APK isn't signed with the release key, or if it contains your home folder path.
4. Install the APK over the previous version on a phone and check that the notes are still there.
5. Tag and push:
   ```bash
   git tag -a v<version> -m "jNote <version>"
   git push && git push origin v<version>
   ```
6. On GitHub, open **Releases → Draft a new release**:
   - Choose the tag `v<version>` and title it `jNote <version>`.
   - Paste the CHANGELOG section and the SHA-256, and attach the APK.
   - Publish it as the latest release.

## Rules

- Always sign with the same key.
- Always publish the universal APK that the script builds. Split APKs (one per processor type) get different version codes, which would block updates between the two kinds.
- Release builds are obfuscated. Keep `build/symbols/<version>` if you want to read crash stack traces from that version later.
