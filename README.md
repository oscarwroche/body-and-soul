# Body and Soul

A native SwiftUI app for transcribing music by ear into treble-clef notation. It runs on macOS 14 or later. The app uses Apple frameworks for the editor and playback, and Sparkle for user-initiated updates.

Visit the [Body and Soul homepage](https://oscarwroche.github.io/body-and-soul/) for screenshots, a download, and installation steps.

Build and test with Xcode 26 installed:

```sh
./Scripts/build-app.sh
swift test
```

Open `dist/Body and Soul.app` to start with a blank score. Use **Open Project…** or **Recent Projects** to resume a project, or drag one recording from Finder onto the editor. **Import Audio…** opens the file picker. Once loaded, click the waveform to seek, then press ⌥A or ⌥B to set a marker at the playhead. You can also drag across an open part of the waveform to set and activate both markers at once. Grab the A or B handle and release it at the new position to adjust that end of the loop. Slow the recording to 50–100% using the speed slider. Use the magnifiers to zoom around the playhead and the slider below the zoomed waveform to pan. Click the zoom level to show the whole recording. Save with ⌘S and open saved `.alto` files through Finder or the File menu. Each project stores its notation and audio controls in JSON and references the original recording on disk. If macOS cannot locate the source, use **Relink Audio**.

| Shortcut | Action |
| --- | --- |
| ⌘I | Import or relink audio |
| Space | Play or pause |
| ⌥A / ⌥B | Set a loop marker at the playhead |
| ⌥L | Toggle the selected loop |
| A–G | Write or edit a note in the nearest octave |
| ↑ / ↓ | Move by one staff step |
| ← / → | Select the previous or next event |
| Home / End | Jump to the first event or the entry cursor |
| Return | Insert a note at the cursor |
| 1–6 | Set duration from whole to thirty-second |
| . | Toggle dotted duration |
| R | Insert a rest or toggle the selected event between note and rest |
| [ / ] / backslash | Set flat, sharp, or natural |
| Delete | Delete the selected event or the last event |

Click past the last note to add a note at that height, even with a note selected. Click a note’s column to select it, then click a line or space inside its blue highlight to change pitch. Press **End** to advance to the entry cursor for keyboard entry. Use **Insert** or Return to add an event before the selection. The score uses treble clef, with a C key signature and 4/4 by default. Use **Key** to choose a signature for the written part. Unmarked notes follow the signature, and accidentals override it. You can also select 3/4, 5/4, or 6/8. Eighth notes and shorter notes are beamed by beat. Durations that cross barlines are split automatically and pitched fragments are tied together. The score stores the pitches you enter, and only the source recording plays back.

Use **Instrument (optional)** to label the part, for example **B♭ clarinet**. The label is saved with the project and printed under the PDF title. Older projects open with the field blank.

Scroll vertically through the wrapped score and click any note to edit it. Use **Score Zoom** to make the notation larger or smaller. The transport stays above the score while you scroll. The score and recording are independent, so you can replay or slow down any passage without moving the score selection.

Use **Clear Score…** to remove every note and rest while keeping the recording and project settings. Press ⌘Z to restore the score after clearing it. Use **Export PDF…** to save a printable copy of the notation. The PDF heading uses the recording filename without its extension. A project with no recording uses the project name. Longer scores wrap across staff lines and pages. Open the PDF in Preview to print it. Save the .alto project as well if you want to keep editing.

The test suite renders the production audio graph offline and exercises waveform generation, speed and pitch, repeated loop boundaries, seek, and project restoration.

## Builds and releases

Open the release disk image and drag **Body and Soul** into the **Applications** shortcut. Use **Body and Soul → Check for Updates…** to install a newer GitHub build. Save any open project before clicking **Install and Relaunch**. Sparkle preserves the path of the app it updates, so an update over an older installation may keep its original filename in Finder.

In GitHub, open **Actions → Build Body and Soul → Run workflow**. Leave **Existing version tag to build** blank to build the selected branch, or enter a tag such as `v1.3.8` to build that exact version. The workflow runs the release test suite, builds an Apple Silicon app, and uploads a ZIP and disk image. The artifacts include SHA-256 checksums and a build record with the source commit and toolchain. It also checks pushes to `main` and pull requests. To build a disk image locally, run `./Scripts/package-dmg.sh` after `./Scripts/build-app.sh`.

For a release:

1. Update `CFBundleShortVersionString` in `Scripts/Info.plist` using version numbers in the form `major.minor.patch`. Increase the integer `CFBundleVersion` on every release. Commit and push the changes.
2. Tag the release commit with the matching version and push the tag. Keep published tags and their assets fixed. Use a new version for corrections.

   ```sh
   git tag -a v1.3.8 -m "Body and Soul 1.3.8"
   git push origin v1.3.8
   gh workflow run build-macos.yml --ref main -f release_tag=v1.3.8
   ```

3. Verify the disk image with `shasum -a 256 -c <filename>.dmg.sha256`. Open the app from Finder and smoke-test blank launch, Finder drag-and-drop and the audio picker, playback and looping, note editing, save and reopen, and PDF export. Test a separate copy alongside the existing app in Applications. Test the update from the last version in a disposable folder.
4. Create a GitHub Release for the existing tag. Attach the tested disk image, the update ZIP of the same bundle, their checksums, and `BUILD.txt`. Use the prerelease designation for ad hoc builds.
5. Generate the signed appcast with `./Scripts/make-appcast.sh path/to/update.zip path/to/Sparkle/bin/sign_update Updates/appcast.xml`. The signing key stays in the release Mac's login Keychain under the Sparkle account `com.altotranscription.updates`. Use the signing tool from the [pinned Sparkle release](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.1). Verify that the GitHub ZIP is available, then commit and push `Updates/appcast.xml`. Existing apps read this file when the user checks for updates.
6. After verifying the public DMG download, update the homepage download URL in `docs/index.html` and check that its requirements and first-launch steps still match the release. GitHub Pages publishes from `main` in the `docs` folder.

### Developer ID builds

GitHub Actions produces ad hoc test builds. For public Mac downloads, build and notarize on a Mac with a **Developer ID Application** signing identity in its login Keychain. The signing identity includes both the certificate and its private key. [Apple’s Developer ID guide](https://developer.apple.com/developer-id/)

Store credentials for notarization once. Run the following in Terminal with your Apple Account and Developer Team ID. Enter an [app-specific password](https://support.apple.com/en-us/102654) at the secure prompt.

```sh
xcrun notarytool store-credentials body-and-soul-notary --apple-id 'you@example.com' --team-id 'YOUR_TEAM_ID'
```

From a clean checkout of the release tag, run the release script with the certificate name from `security find-identity -v -p codesigning`:

```sh
./Scripts/notarize-release.sh 'Developer ID Application: Your Name (YOUR_TEAM_ID)'
```

The script signs the app and its Sparkle helpers, submits the app and disk image to Apple, and verifies the attached notarization tickets. It writes the verified disk image, Sparkle update ZIP, checksums, and build record to `dist/notarized/`. Download and test the actual installer and the in-app upgrade before publishing. Sign the final stapled app ZIP with `make-appcast.sh` as described above.
