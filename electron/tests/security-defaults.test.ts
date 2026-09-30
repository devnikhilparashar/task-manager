import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  CONTENT_SECURITY_POLICY,
  isTrustedRendererUrl,
  secureWebPreferences,
} from "../apps/desktop/src/main/security.ts";

test("renderer starts with Electron privilege boundaries enabled", () => {
  const preferences = secureWebPreferences("/app/preload.js");
  assert.equal(preferences.nodeIntegration, false);
  assert.equal(preferences.contextIsolation, true);
  assert.equal(preferences.sandbox, true);
  assert.equal(preferences.webSecurity, true);
  assert.equal(preferences.webviewTag, false);
  assert.equal(Object.isFrozen(preferences), true);
});

test("CSP denies network, plugins, forms, and embedding", () => {
  assert.match(CONTENT_SECURITY_POLICY, /connect-src 'none'/);
  assert.match(CONTENT_SECURITY_POLICY, /object-src 'none'/);
  assert.match(CONTENT_SECURITY_POLICY, /form-action 'none'/);
  assert.match(CONTENT_SECURITY_POLICY, /frame-ancestors 'none'/);
  assert.doesNotMatch(CONTENT_SECURITY_POLICY, /unsafe-(?:inline|eval)/);
  assert.doesNotMatch(CONTENT_SECURITY_POLICY, /https?:/);
});

test("only the exact packaged file URL is a trusted renderer", () => {
  const expected = "file:///Applications/Activity%20Journal.app/renderer/index.html";
  assert.equal(isTrustedRendererUrl(expected, expected), true);
  assert.equal(isTrustedRendererUrl("https://example.com/", expected), false);
  assert.equal(isTrustedRendererUrl("file:///tmp/index.html", expected), false);
  assert.equal(isTrustedRendererUrl("not a url", expected), false);
});

test("preload exposes no generic IPC or Node primitive", () => {
  const preload = readFileSync(new URL("../apps/desktop/src/preload/index.ts", import.meta.url), "utf8");
  assert.doesNotMatch(preload, /exposeInMainWorld\([^,]+,\s*ipcRenderer/);
  assert.doesNotMatch(preload, /\b(?:send|sendSync|postMessage)\s*:/);
  assert.doesNotMatch(preload, /(?:node:fs|node:child_process|node:process|shell)/);
  assert.match(preload, /Object\.freeze/);
});
