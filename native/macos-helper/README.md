# AmbiantMemory macOS Helper

This standalone Swift package is the native process boundary for the local
activity journal. It currently implements only the protocol foundation:

- bounded UTF-8 JSONL framing (4 MiB per line),
- protocol `1.0` negotiation through the mandatory first `hello` request,
- `getCapabilities`, `getPermissionState`, and `shutdown`,
- deterministic structured errors and an explicit method allowlist.

Accessibility traversal, permission prompts, event production, window capture,
and OCR are intentionally not implemented in this phase. Those protocol method
names are recognized but return `UNSUPPORTED_METHOD`.

Run the isolated test suite with:

```sh
swift test --package-path native/macos-helper
```

The executable writes protocol frames only to stdout. Diagnostics are written
to stderr and never include request content.
