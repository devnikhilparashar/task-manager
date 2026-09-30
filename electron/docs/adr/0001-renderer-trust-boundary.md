# ADR 0001: Treat the renderer as untrusted

Status: accepted

## Context

The journal eventually displays sensitive local activity text. A renderer compromise must not become direct filesystem, database, shell, native-helper, or arbitrary IPC access.

## Decision

- Enable context isolation, Chromium sandboxing, and web security; disable Node integration and webviews.
- Package renderer content locally and require the exact application `file:` URL for IPC authorization.
- Default-deny navigation, popups, downloads, and Chromium permission requests.
- Apply a CSP with no network connection source, inline/evaluated script, object, form, base, or embedding permission.
- Expose a frozen, purpose-specific preload facade. Never expose generic `send`, `invoke`, channels, paths, SQL, shell commands, or native method names.
- Allowlist every IPC channel and validate exact fields, ranges, dates, enumerations, and serialized size in the main process.
- Let the main process own file-selection dialogs. The renderer never submits an export path.

## Consequences

New renderer capabilities require a typed contract, strict validator, authorized handler, and tests. Development uses the packaged local renderer build instead of a remote hot-reload server. Capture remains disabled until its separate process and privacy controls are implemented.
