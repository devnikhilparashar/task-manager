# AmbiantMemory desktop shell

This directory is the isolated Electron/React workspace for the privacy-first activity journal. It intentionally contains no capture, storage, native-helper, or export implementation yet.

## Local development

Requirements: Node.js 22+, npm, and macOS 13+.

```sh
npm install
npm test
npm run typecheck
npm run build
npm start
```

The renderer is treated as untrusted. It has no Node integration, no generic IPC primitive, no navigation, no popup permission, and no direct filesystem, shell, database, or native-helper access.
