import type { HistoryEntry } from "./types";

// crypto.randomUUID() is only exposed in a secure context (HTTPS or
// localhost) — this demo is served over plain HTTP from a NodePort IP,
// so it's unavailable there. These IDs are just React keys / localStorage
// identifiers, not security-sensitive, so a non-crypto fallback is fine.
function makeId(): string {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
}

export function loadHistory(key: string): HistoryEntry[] {
  try {
    const raw = window.localStorage.getItem(key);
    if (!raw) return [];
    return JSON.parse(raw) as HistoryEntry[];
  } catch {
    return [];
  }
}

export function appendHistory(
  key: string,
  entry: Omit<HistoryEntry, "id" | "timestamp">
): HistoryEntry[] {
  const next: HistoryEntry = {
    ...entry,
    id: makeId(),
    timestamp: new Date().toISOString(),
  };
  const items = [next, ...loadHistory(key)].slice(0, 100);
  try {
    window.localStorage.setItem(key, JSON.stringify(items));
  } catch {
    // non-fatal
  }
  return items;
}
