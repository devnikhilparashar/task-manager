import { ipcMain, type BrowserWindow, type IpcMainInvokeEvent } from "electron";
import {
  IPC_CHANNELS,
  parseIpcRequest,
  parseIpcResponse,
  type IpcRequestByChannel,
  type IpcResponseByChannel,
  type PublicStatus,
  type RequestChannel,
} from "@ambiant-memory/contracts";
import { isTrustedRendererUrl } from "./security.js";

const initialStatus: PublicStatus = {
  mode: "stopped",
  desiredRecording: false,
  permissions: { accessibility: "notDetermined", screenRecording: "notDetermined" },
};

export interface DesktopServices {
  invoke<Channel extends RequestChannel>(
    channel: Channel,
    request: IpcRequestByChannel[Channel],
  ): Promise<IpcResponseByChannel[Channel]>;
}

export function foundationServices(): DesktopServices {
  return {
    async invoke(channel) {
      if (channel === IPC_CHANNELS.status) return initialStatus as IpcResponseByChannel[typeof channel];
      throw new Error("This operation is not available in the foundation build");
    },
  };
}

export function registerIpcHandlers(
  getWindow: () => BrowserWindow | null,
  rendererUrl: string,
  services: DesktopServices,
): () => void {
  const channels = Object.values(IPC_CHANNELS).filter(
    (channel): channel is RequestChannel => channel !== IPC_CHANNELS.statusChanged,
  );

  for (const channel of channels) {
    ipcMain.handle(channel, async (event: IpcMainInvokeEvent, payload: unknown) => {
      const window = getWindow();
      if (
        window === null ||
        window.isDestroyed() ||
        event.sender.isDestroyed() ||
        event.sender.id !== window.webContents.id ||
        event.senderFrame !== window.webContents.mainFrame ||
        !isTrustedRendererUrl(event.senderFrame.url, rendererUrl)
      ) {
        throw new Error("Unauthorized IPC sender");
      }
      const request = parseIpcRequest(channel, payload);
      const response = await services.invoke(channel, request);
      return parseIpcResponse(channel, response);
    });
  }

  return () => {
    for (const channel of channels) ipcMain.removeHandler(channel);
  };
}
