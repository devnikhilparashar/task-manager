import assert from "node:assert/strict";
import test from "node:test";
import {
  ContractValidationError,
  IPC_CHANNELS,
  MAX_IPC_PAYLOAD_BYTES,
  parseIpcRequest,
  parseIpcResponse,
  parsePublicStatus,
} from "../packages/contracts/src/index.ts";

test("timeline request accepts only a bounded exact contract", () => {
  assert.deepEqual(parseIpcRequest(IPC_CHANNELS.listTimeline, {
    from: "2026-09-27T00:00:00Z",
    to: "2026-09-27T23:59:59Z",
    limit: 50,
  }), {
    from: "2026-09-27T00:00:00Z",
    to: "2026-09-27T23:59:59Z",
    limit: 50,
  });
  assert.throws(
    () => parseIpcRequest(IPC_CHANNELS.listTimeline, {
      from: "2026-09-27T00:00:00Z", to: "2026-09-27T23:59:59Z", limit: 50, sql: "SELECT *",
    }),
    ContractValidationError,
  );
  assert.throws(() => parseIpcRequest(IPC_CHANNELS.listTimeline, {
    from: "2026-09-27T00:00:00Z", to: "2026-09-27T23:59:59Z", limit: 101,
  }), ContractValidationError);
  assert.throws(() => parseIpcRequest(IPC_CHANNELS.listTimeline, {
    from: "2026-99-27T00:00:00Z", to: "2026-09-27T23:59:59Z", limit: 50,
  }), /valid calendar instant/);
});

test("export contract never accepts a renderer-selected path", () => {
  assert.throws(() => parseIpcRequest(IPC_CHANNELS.chooseAndExport, {
    format: "json",
    from: "2026-09-27T00:00:00Z",
    to: "2026-09-27T23:59:59Z",
    includeObservationText: false,
    path: "/tmp/exfiltrate.json",
  }), /unknown field: path/);
});

test("oversized payloads fail before field validation", () => {
  assert.throws(
    () => parseIpcRequest(IPC_CHANNELS.search, { text: "x".repeat(MAX_IPC_PAYLOAD_BYTES), limit: 10 }),
    /size limit/,
  );
});

test("status response rejects extra privileged state", () => {
  assert.throws(() => parsePublicStatus({
    mode: "stopped",
    desiredRecording: false,
    permissions: { accessibility: "denied", screenRecording: "denied" },
    databasePath: "/private/data.sqlite",
  }), /unknown field: databasePath/);
});

test("response pages reject oversized and unrecognized records", () => {
  assert.throws(() => parseIpcResponse(IPC_CHANNELS.listTimeline, {
    items: [{
      id: "block-1",
      startedAt: "2026-09-27T00:00:00Z",
      endedAt: "2026-09-27T00:05:00Z",
      applicationName: "Editor",
      label: "Work",
      confidence: 0.8,
      rawDatabaseRow: true,
    }],
  }), /unknown field: rawDatabaseRow/);
});
