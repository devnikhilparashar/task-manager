import {
  IPC_CHANNELS,
  type ActivityBlockDetail,
  type ActivityBlockView,
  type ClearScope,
  type ExportOptions,
  type IpcRequestByChannel,
  type IpcResponseByChannel,
  type Page,
  type PermissionKind,
  type PermissionState,
  type PublicSettings,
  type PublicStatus,
  type RequestChannel,
  type SearchHit,
  type SearchQuery,
  type SettingsPatch,
  type TimelineQuery,
} from "./types.ts";

export const MAX_IPC_PAYLOAD_BYTES = 256 * 1024;

export class ContractValidationError extends Error {
  readonly code = "INVALID_IPC_PAYLOAD";

  constructor(message: string) {
    super(message);
    this.name = "ContractValidationError";
  }
}

type JsonRecord = Record<string, unknown>;
type Parser<T> = (value: unknown) => T;

function fail(message: string): never {
  throw new ContractValidationError(message);
}

function record(value: unknown, name: string): JsonRecord {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return fail(`${name} must be an object`);
  }
  const prototype = Object.getPrototypeOf(value);
  if (prototype !== Object.prototype && prototype !== null) {
    return fail(`${name} must be a plain object`);
  }
  return value as JsonRecord;
}

function exactKeys(value: JsonRecord, allowed: readonly string[], name: string): void {
  const unexpected = Object.keys(value).filter((key) => !allowed.includes(key));
  if (unexpected.length > 0) fail(`${name} contains unknown field: ${unexpected[0]}`);
}

function string(value: unknown, name: string, maxLength = 512): string {
  if (typeof value !== "string" || value.length === 0 || value.length > maxLength) {
    return fail(`${name} must be a non-empty string of at most ${maxLength} characters`);
  }
  return value;
}

function oneOf<T extends string>(value: unknown, values: readonly T[], name: string): T {
  if (typeof value !== "string" || !values.includes(value as T)) {
    return fail(`${name} is not an allowed value`);
  }
  return value as T;
}

function isoInstant(value: unknown, name: string): string {
  const parsed = string(value, name, 40);
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$/.test(parsed)) {
    return fail(`${name} must be an RFC 3339 UTC instant`);
  }
  if (!Number.isFinite(Date.parse(parsed))) return fail(`${name} must be a valid calendar instant`);
  return parsed;
}

function optionalString(value: unknown, name: string, maxLength = 512): string | undefined {
  return value === undefined ? undefined : string(value, name, maxLength);
}

function boolean(value: unknown, name: string): boolean {
  if (typeof value !== "boolean") return fail(`${name} must be a boolean`);
  return value;
}

function finiteNumber(value: unknown, name: string, minimum: number, maximum: number): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < minimum || value > maximum) {
    return fail(`${name} must be a finite number between ${minimum} and ${maximum}`);
  }
  return value;
}

function pageLimit(value: unknown): number {
  if (!Number.isInteger(value) || (value as number) < 1 || (value as number) > 100) {
    return fail("limit must be an integer between 1 and 100");
  }
  return value as number;
}

function stringArray(value: unknown, name: string): string[] {
  if (!Array.isArray(value) || value.length > 200) return fail(`${name} must contain at most 200 entries`);
  return value.map((item, index) => string(item, `${name}[${index}]`, 512));
}

function assertRange(from: string, to: string): void {
  if (Date.parse(from) > Date.parse(to)) fail("from must not be after to");
}

export function assertPayloadSize(value: unknown): void {
  let encoded: string;
  try {
    encoded = JSON.stringify(value) ?? "";
  } catch {
    return fail("payload must be JSON serializable");
  }
  if (new TextEncoder().encode(encoded).byteLength > MAX_IPC_PAYLOAD_BYTES) {
    fail("payload exceeds the IPC size limit");
  }
}

export function parseTimelineQuery(value: unknown): TimelineQuery {
  const data = record(value, "timeline query");
  exactKeys(data, ["from", "to", "cursor", "limit"], "timeline query");
  const from = isoInstant(data.from, "from");
  const to = isoInstant(data.to, "to");
  assertRange(from, to);
  const cursor = optionalString(data.cursor, "cursor", 256);
  return { from, to, ...(cursor === undefined ? {} : { cursor }), limit: pageLimit(data.limit) };
}

export function parseSearchQuery(value: unknown): SearchQuery {
  const data = record(value, "search query");
  exactKeys(data, ["text", "cursor", "limit"], "search query");
  const cursor = optionalString(data.cursor, "cursor", 256);
  return {
    text: string(data.text, "text", 500),
    ...(cursor === undefined ? {} : { cursor }),
    limit: pageLimit(data.limit),
  };
}

export function parseSettingsPatch(value: unknown): SettingsPatch {
  const data = record(value, "settings patch");
  exactKeys(data, ["retentionDays", "urlDetail", "excludedBundleIds", "excludedTitleGlobs"], "settings patch");
  const patch: SettingsPatch = {};
  if ("retentionDays" in data) {
    if (![7, 30, 90, null].includes(data.retentionDays as 7 | 30 | 90 | null)) fail("invalid retentionDays");
    patch.retentionDays = data.retentionDays as 7 | 30 | 90 | null;
  }
  if ("urlDetail" in data) patch.urlDetail = oneOf(data.urlDetail, ["originAndPath", "full", "none"], "urlDetail");
  if ("excludedBundleIds" in data) patch.excludedBundleIds = stringArray(data.excludedBundleIds, "excludedBundleIds");
  if ("excludedTitleGlobs" in data) patch.excludedTitleGlobs = stringArray(data.excludedTitleGlobs, "excludedTitleGlobs");
  return patch;
}

export function parseExportOptions(value: unknown): ExportOptions {
  const data = record(value, "export options");
  exactKeys(data, ["format", "from", "to", "includeObservationText"], "export options");
  const from = isoInstant(data.from, "from");
  const to = isoInstant(data.to, "to");
  assertRange(from, to);
  return {
    format: oneOf(data.format, ["json", "csv"], "format"),
    from,
    to,
    includeObservationText: boolean(data.includeObservationText, "includeObservationText"),
  };
}

export function parseClearScope(value: unknown): ClearScope {
  const data = record(value, "clear scope");
  exactKeys(data, ["kind", "from", "to"], "clear scope");
  const kind = oneOf(data.kind, ["all", "range"], "kind");
  if (kind === "all") {
    if (data.from !== undefined || data.to !== undefined) fail("all clear scope cannot include a range");
    return { kind };
  }
  const from = isoInstant(data.from, "from");
  const to = isoInstant(data.to, "to");
  assertRange(from, to);
  return { kind, from, to };
}

const requestParsers: { [Channel in RequestChannel]: Parser<IpcRequestByChannel[Channel]> } = {
  [IPC_CHANNELS.status]: (value) => (value === undefined ? undefined : fail("status takes no payload")),
  [IPC_CHANNELS.setRecording]: (value) => oneOf(value, ["resume", "pause", "pause15m"], "recording command"),
  [IPC_CHANNELS.listTimeline]: parseTimelineQuery,
  [IPC_CHANNELS.search]: parseSearchQuery,
  [IPC_CHANNELS.getBlock]: (value) => string(value, "block id", 128),
  [IPC_CHANNELS.updateSettings]: parseSettingsPatch,
  [IPC_CHANNELS.requestPermission]: (value) => oneOf(value, ["accessibility", "screenRecording"], "permission kind") as PermissionKind,
  [IPC_CHANNELS.chooseAndExport]: parseExportOptions,
  [IPC_CHANNELS.clearHistory]: (value) => {
    const data = record(value, "clear history request");
    exactKeys(data, ["scope", "confirmationToken"], "clear history request");
    return { scope: parseClearScope(data.scope), confirmationToken: string(data.confirmationToken, "confirmationToken", 256) };
  },
};

export function parseIpcRequest<Channel extends RequestChannel>(channel: Channel, value: unknown): IpcRequestByChannel[Channel] {
  assertPayloadSize(value);
  const parser = requestParsers[channel] as Parser<IpcRequestByChannel[Channel]> | undefined;
  if (parser === undefined) return fail("unknown IPC channel");
  return parser(value);
}

export function parsePublicStatus(value: unknown): PublicStatus {
  const data = record(value, "public status");
  exactKeys(data, ["mode", "desiredRecording", "pausedUntil", "permissions", "lastCaptureAt"], "public status");
  const permissions = record(data.permissions, "permissions");
  exactKeys(permissions, ["accessibility", "screenRecording"], "permissions");
  const pausedUntil = data.pausedUntil === undefined ? undefined : isoInstant(data.pausedUntil, "pausedUntil");
  const lastCaptureAt = data.lastCaptureAt === undefined ? undefined : isoInstant(data.lastCaptureAt, "lastCaptureAt");
  return {
    mode: oneOf(data.mode, ["stopped", "recording", "paused", "degraded"], "mode"),
    desiredRecording: boolean(data.desiredRecording, "desiredRecording"),
    ...(pausedUntil === undefined ? {} : { pausedUntil }),
    permissions: {
      accessibility: oneOf(permissions.accessibility, ["notDetermined", "denied", "granted", "restricted"], "accessibility"),
      screenRecording: oneOf(permissions.screenRecording, ["notDetermined", "denied", "granted", "restricted"], "screenRecording"),
    },
    ...(lastCaptureAt === undefined ? {} : { lastCaptureAt }),
  };
}

function parseActivityBlock(value: unknown, name = "activity block"): ActivityBlockView {
  const data = record(value, name);
  exactKeys(data, ["id", "startedAt", "endedAt", "applicationName", "label", "confidence"], name);
  const startedAt = isoInstant(data.startedAt, `${name}.startedAt`);
  const endedAt = isoInstant(data.endedAt, `${name}.endedAt`);
  assertRange(startedAt, endedAt);
  return {
    id: string(data.id, `${name}.id`, 128),
    startedAt,
    endedAt,
    applicationName: string(data.applicationName, `${name}.applicationName`, 256),
    label: string(data.label, `${name}.label`, 1024),
    confidence: finiteNumber(data.confidence, `${name}.confidence`, 0, 1),
  };
}

function parseSearchHit(value: unknown): SearchHit {
  const data = record(value, "search hit");
  exactKeys(data, ["id", "startedAt", "endedAt", "applicationName", "label", "confidence", "excerpt"], "search hit");
  const base = parseActivityBlock({
    id: data.id,
    startedAt: data.startedAt,
    endedAt: data.endedAt,
    applicationName: data.applicationName,
    label: data.label,
    confidence: data.confidence,
  }, "search hit");
  return { ...base, excerpt: string(data.excerpt, "search hit.excerpt", 4096) };
}

function parseBlockDetail(value: unknown): ActivityBlockDetail {
  const data = record(value, "block detail");
  exactKeys(data, ["id", "startedAt", "endedAt", "applicationName", "label", "confidence", "title", "url", "text"], "block detail");
  const base = parseActivityBlock({
    id: data.id,
    startedAt: data.startedAt,
    endedAt: data.endedAt,
    applicationName: data.applicationName,
    label: data.label,
    confidence: data.confidence,
  }, "block detail");
  const title = optionalString(data.title, "block detail.title", 2048);
  const url = optionalString(data.url, "block detail.url", 4096);
  return {
    ...base,
    ...(title === undefined ? {} : { title }),
    ...(url === undefined ? {} : { url }),
    text: typeof data.text === "string" && data.text.length <= 256_000
      ? data.text
      : fail("block detail.text must be a string of at most 256000 characters"),
  };
}

function parsePage<T>(value: unknown, itemParser: Parser<T>, name: string): Page<T> {
  const data = record(value, name);
  exactKeys(data, ["items", "nextCursor"], name);
  if (!Array.isArray(data.items) || data.items.length > 100) fail(`${name}.items must contain at most 100 entries`);
  const nextCursor = optionalString(data.nextCursor, `${name}.nextCursor`, 256);
  return {
    items: data.items.map(itemParser),
    ...(nextCursor === undefined ? {} : { nextCursor }),
  };
}

function parsePublicSettings(value: unknown): PublicSettings {
  const data = record(value, "public settings");
  exactKeys(data, ["retentionDays", "urlDetail", "excludedBundleIds", "excludedTitleGlobs"], "public settings");
  if (![7, 30, 90, null].includes(data.retentionDays as 7 | 30 | 90 | null)) fail("invalid retentionDays");
  return {
    retentionDays: data.retentionDays as 7 | 30 | 90 | null,
    urlDetail: oneOf(data.urlDetail, ["originAndPath", "full", "none"], "urlDetail"),
    excludedBundleIds: stringArray(data.excludedBundleIds, "excludedBundleIds"),
    excludedTitleGlobs: stringArray(data.excludedTitleGlobs, "excludedTitleGlobs"),
  };
}

const permissionStates = ["notDetermined", "denied", "granted", "restricted"] as const;

const responseParsers: { [Channel in RequestChannel]: Parser<IpcResponseByChannel[Channel]> } = {
  [IPC_CHANNELS.status]: parsePublicStatus,
  [IPC_CHANNELS.setRecording]: parsePublicStatus,
  [IPC_CHANNELS.listTimeline]: (value) => parsePage(value, parseActivityBlock, "timeline page"),
  [IPC_CHANNELS.search]: (value) => parsePage(value, parseSearchHit, "search page"),
  [IPC_CHANNELS.getBlock]: parseBlockDetail,
  [IPC_CHANNELS.updateSettings]: parsePublicSettings,
  [IPC_CHANNELS.requestPermission]: (value) => oneOf(value, permissionStates, "permission state") as PermissionState,
  [IPC_CHANNELS.chooseAndExport]: (value) => {
    const data = record(value, "export result");
    exactKeys(data, ["outcome", "blockCount"], "export result");
    return {
      outcome: oneOf(data.outcome, ["completed", "cancelled"], "export outcome"),
      blockCount: Number.isSafeInteger(data.blockCount) && (data.blockCount as number) >= 0
        ? data.blockCount as number
        : fail("blockCount must be a non-negative safe integer"),
    };
  },
  [IPC_CHANNELS.clearHistory]: (value) => value === undefined ? undefined : fail("clear history must return no payload"),
};

export function parseIpcResponse<Channel extends RequestChannel>(channel: Channel, value: unknown): IpcResponseByChannel[Channel] {
  assertPayloadSize(value);
  const parser = responseParsers[channel] as Parser<IpcResponseByChannel[Channel]> | undefined;
  if (parser === undefined) return fail("unknown IPC channel");
  return parser(value);
}
