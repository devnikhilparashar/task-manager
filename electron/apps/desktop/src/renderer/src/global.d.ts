import type { PublicDesktopAPI } from "@ambiant-memory/contracts";

declare global {
  interface Window {
    readonly activityJournal: PublicDesktopAPI;
  }
}

export {};
