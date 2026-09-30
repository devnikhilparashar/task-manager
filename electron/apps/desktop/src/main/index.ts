import { app, BrowserWindow, Menu, session, Tray } from "electron";
import { fileURLToPath, pathToFileURL } from "node:url";
import { dirname, join } from "node:path";
import { foundationServices, registerIpcHandlers } from "./ipc.js";
import { CONTENT_SECURITY_POLICY, secureWebPreferences } from "./security.js";

const currentDirectory = dirname(fileURLToPath(import.meta.url));
const preloadPath = join(currentDirectory, "../preload/index.js");
const rendererPath = join(currentDirectory, "../renderer/index.html");
const rendererUrl = pathToFileURL(rendererPath).href;

let mainWindow: BrowserWindow | null = null;
let tray: Tray | null = null;
let unregisterIpc: (() => void) | null = null;
let isQuitting = false;

if (!app.requestSingleInstanceLock()) app.quit();

function createWindow(): BrowserWindow {
  const window = new BrowserWindow({
    width: 920,
    height: 680,
    minWidth: 720,
    minHeight: 520,
    show: false,
    title: "AmbiantMemory",
    webPreferences: secureWebPreferences(preloadPath),
  });

  window.removeMenu();
  window.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  window.webContents.on("will-navigate", (event, url) => {
    if (url !== rendererUrl) event.preventDefault();
  });
  window.webContents.on("will-attach-webview", (event) => event.preventDefault());
  window.on("close", (event) => {
    if (!isQuitting) {
      event.preventDefault();
      window.hide();
    }
  });
  void window.loadFile(rendererPath);
  return window;
}

function createTray(window: BrowserWindow): Tray {
  const item = new Tray(join(currentDirectory, "../../resources/trayTemplate.svg"));
  item.setToolTip("AmbiantMemory");
  item.setContextMenu(Menu.buildFromTemplate([
    { label: "Open AmbiantMemory", click: () => window.show() },
    { type: "separator" },
    { label: "Quit", click: () => { isQuitting = true; app.quit(); } },
  ]));
  item.on("click", () => window.show());
  return item;
}

app.whenReady().then(() => {
  session.defaultSession.setPermissionRequestHandler((_contents, _permission, callback) => callback(false));
  session.defaultSession.setPermissionCheckHandler(() => false);
  session.defaultSession.on("will-download", (event) => event.preventDefault());
  session.defaultSession.webRequest.onHeadersReceived((details, callback) => {
    callback({
      responseHeaders: {
        ...details.responseHeaders,
        "Content-Security-Policy": [CONTENT_SECURITY_POLICY],
      },
    });
  });

  mainWindow = createWindow();
  unregisterIpc = registerIpcHandlers(() => mainWindow, rendererUrl, foundationServices());
  tray = createTray(mainWindow);
});

app.on("second-instance", () => mainWindow?.show());
app.on("window-all-closed", () => undefined);
app.on("before-quit", () => {
  isQuitting = true;
  unregisterIpc?.();
  unregisterIpc = null;
  tray?.destroy();
  tray = null;
});
