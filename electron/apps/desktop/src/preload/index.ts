import { contextBridge, ipcRenderer } from "electron";
import {
  IPC_CHANNELS,
  parseIpcResponse,
  type ClearScope,
  type ExportOptions,
  type PermissionKind,
  type PublicDesktopAPI,
  type PublicStatus,
  type RecordingCommand,
  type SearchQuery,
  type SettingsPatch,
  type TimelineQuery,
} from "@ambiant-memory/contracts";

const api: PublicDesktopAPI = Object.freeze({
  status: async () => parseIpcResponse(IPC_CHANNELS.status, await ipcRenderer.invoke(IPC_CHANNELS.status)),
  setRecording: async (command: RecordingCommand) => parseIpcResponse(IPC_CHANNELS.setRecording, await ipcRenderer.invoke(IPC_CHANNELS.setRecording, command)),
  listTimeline: async (query: TimelineQuery) => parseIpcResponse(IPC_CHANNELS.listTimeline, await ipcRenderer.invoke(IPC_CHANNELS.listTimeline, query)),
  search: async (query: SearchQuery) => parseIpcResponse(IPC_CHANNELS.search, await ipcRenderer.invoke(IPC_CHANNELS.search, query)),
  getBlock: async (id: string) => parseIpcResponse(IPC_CHANNELS.getBlock, await ipcRenderer.invoke(IPC_CHANNELS.getBlock, id)),
  updateSettings: async (patch: SettingsPatch) => parseIpcResponse(IPC_CHANNELS.updateSettings, await ipcRenderer.invoke(IPC_CHANNELS.updateSettings, patch)),
  requestPermission: async (kind: PermissionKind) => parseIpcResponse(IPC_CHANNELS.requestPermission, await ipcRenderer.invoke(IPC_CHANNELS.requestPermission, kind)),
  chooseAndExport: async (options: ExportOptions) => parseIpcResponse(IPC_CHANNELS.chooseAndExport, await ipcRenderer.invoke(IPC_CHANNELS.chooseAndExport, options)),
  clearHistory: async (scope: ClearScope, confirmationToken: string) => parseIpcResponse(
    IPC_CHANNELS.clearHistory,
    await ipcRenderer.invoke(IPC_CHANNELS.clearHistory, { scope, confirmationToken }),
  ),
  subscribeStatus(listener: (status: PublicStatus) => void) {
    const wrapped = (_event: Electron.IpcRendererEvent, value: unknown): void => {
      listener(parseIpcResponse(IPC_CHANNELS.status, value));
    };
    ipcRenderer.on(IPC_CHANNELS.statusChanged, wrapped);
    return () => ipcRenderer.removeListener(IPC_CHANNELS.statusChanged, wrapped);
  },
});

contextBridge.exposeInMainWorld("activityJournal", api);

declare global {
  interface Window {
    readonly activityJournal: PublicDesktopAPI;
  }
}
