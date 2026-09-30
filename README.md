# AmbiantMemory

A privacy-first local macOS activity journal. The production implementation is being built as an Electron/React/TypeScript desktop app with a small, isolated Swift helper and local SQLite storage.

The repository also contains the original in-process SwiftUI proof of concept. It remains as behavioral reference while functionality moves behind the production process and trust boundaries. Do not extend its capture or database architecture as the production path.

See [PRIVACY_FIRST_ACTIVITY_JOURNAL_DESIGN.md](PRIVACY_FIRST_ACTIVITY_JOURNAL_DESIGN.md) for the decision-complete HLD and LLD.

## Production implementation

- `electron/` — secure Electron main/preload/renderer foundation and shared IPC contracts.
- `native/macos-helper/` — standalone Swift JSONL helper protocol foundation.
- `Sources/AmbiantMemory/` — legacy SwiftUI proof of concept, retained temporarily for reference.

### Electron foundation

```sh
cd electron
npm install
npm run typecheck
npm run build
npm test
```

The foundation deliberately keeps capture disabled. Unimplemented privileged operations fail closed.

### Native helper foundation

```sh
swift test --package-path native/macos-helper
```

The helper currently implements protocol negotiation, capabilities, permission-state inspection, and shutdown. Accessibility traversal, permission prompts, events, screenshots, and OCR are later milestones.

## Legacy proof of concept

## Build and run

Full Xcode is recommended so the SDK, signing, and privacy permission workflow are available.

```sh
swift test
chmod +x scripts/build-app.sh
scripts/build-app.sh
open '.build/AmbiantMemory.app'
```

Grant Accessibility and Screen Recording access from the app's Settings window. Screen Recording permission changes can require relaunching the app.

For repeated development builds, use a stable signing identity so macOS keeps the Accessibility grant:

```sh
AMBIANT_MEMORY_SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" scripts/build-app.sh
```

With the default ad-hoc signature, rebuilds can invalidate the existing Accessibility entry. Remove the old entry from **System Settings → Privacy & Security → Accessibility**, rebuild, then add and enable the newly built app again.

The SQLite database lives at `~/Library/Application Support/AmbiantMemory/journal.sqlite3`. JSON and CSV exports contain only derived text and activity metadata.

## Privacy boundaries

- No keyboard, mouse, clipboard, audio, or action logging.
- No screenshots written to disk.
- Secure accessibility fields are skipped.
- Apps and window-title patterns can be excluded.
- Capture stops while paused or while the user session is inactive.

Accessibility and OCR can still expose sensitive text that an application paints outside a correctly marked secure field. Use exclusions or pause capture around sensitive work.
