export const IPC_CHANNELS = {
  status: "journal:status",
  setRecording: "journal:set-recording",
  listTimeline: "journal:list-timeline",
  search: "journal:search",
  getBlock: "journal:get-block",
  updateSettings: "journal:update-settings",
  requestPermission: "journal:request-permission",
  chooseAndExport: "journal:choose-and-export",
  clearHistory: "journal:clear-history",
  statusChanged: "journal:status-changed",
} as const;

export type RequestChannel = Exclude<
  (typeof IPC_CHANNELS)[keyof typeof IPC_CHANNELS],
  typeof IPC_CHANNELS.statusChanged
>;

export type RecordingCommand = "resume" | "pause" | "pause15m";
export type PermissionKind = "accessibility" | "screenRecording";
export type PermissionState = "notDetermined" | "denied" | "granted" | "restricted";

export interface PublicStatus {
  mode: "stopped" | "recording" | "paused" | "degraded";
  desiredRecording: boolean;
  pausedUntil?: string;
  permissions: Record<PermissionKind, PermissionState>;
  lastCaptureAt?: string;
}

export interface TimelineQuery {
  from: string;
  to: string;
  cursor?: string;
  limit: number;
}

export interface SearchQuery {
  text: string;
  cursor?: string;
  limit: number;
}

export interface Page<T> {
  items: T[];
  nextCursor?: string;
}

export interface ActivityBlockView {
  id: string;
  startedAt: string;
  endedAt: string;
  applicationName: string;
  label: string;
  confidence: number;
}

export interface SearchHit extends ActivityBlockView {
  excerpt: string;
}

export interface ActivityBlockDetail extends ActivityBlockView {
  title?: string;
  url?: string;
  text: string;
}

export interface PublicSettings {
  retentionDays: 7 | 30 | 90 | null;
  urlDetail: "originAndPath" | "full" | "none";
  excludedBundleIds: string[];
  excludedTitleGlobs: string[];
}

export type SettingsPatch = Partial<PublicSettings>;

export interface ExportOptions {
  format: "json" | "csv";
  from: string;
  to: string;
  includeObservationText: boolean;
}

export interface ExportResult {
  outcome: "completed" | "cancelled";
  blockCount: number;
}

export interface ClearScope {
  kind: "all" | "range";
  from?: string;
  to?: string;
}

export interface PublicDesktopAPI {
  status(): Promise<PublicStatus>;
  setRecording(command: RecordingCommand): Promise<PublicStatus>;
  listTimeline(query: TimelineQuery): Promise<Page<ActivityBlockView>>;
  search(query: SearchQuery): Promise<Page<SearchHit>>;
  getBlock(id: string): Promise<ActivityBlockDetail>;
  updateSettings(patch: SettingsPatch): Promise<PublicSettings>;
  requestPermission(kind: PermissionKind): Promise<PermissionState>;
  chooseAndExport(options: ExportOptions): Promise<ExportResult>;
  clearHistory(scope: ClearScope, confirmationToken: string): Promise<void>;
  subscribeStatus(listener: (status: PublicStatus) => void): () => void;
}

export interface IpcRequestByChannel {
  [IPC_CHANNELS.status]: undefined;
  [IPC_CHANNELS.setRecording]: RecordingCommand;
  [IPC_CHANNELS.listTimeline]: TimelineQuery;
  [IPC_CHANNELS.search]: SearchQuery;
  [IPC_CHANNELS.getBlock]: string;
  [IPC_CHANNELS.updateSettings]: SettingsPatch;
  [IPC_CHANNELS.requestPermission]: PermissionKind;
  [IPC_CHANNELS.chooseAndExport]: ExportOptions;
  [IPC_CHANNELS.clearHistory]: { scope: ClearScope; confirmationToken: string };
}

export interface IpcResponseByChannel {
  [IPC_CHANNELS.status]: PublicStatus;
  [IPC_CHANNELS.setRecording]: PublicStatus;
  [IPC_CHANNELS.listTimeline]: Page<ActivityBlockView>;
  [IPC_CHANNELS.search]: Page<SearchHit>;
  [IPC_CHANNELS.getBlock]: ActivityBlockDetail;
  [IPC_CHANNELS.updateSettings]: PublicSettings;
  [IPC_CHANNELS.requestPermission]: PermissionState;
  [IPC_CHANNELS.chooseAndExport]: ExportResult;
  [IPC_CHANNELS.clearHistory]: undefined;
}
