/**
 * Timezone utilities for IST (Asia/Kolkata) timezone
 * All API responses use ISO-8601 with +05:30 offset
 */

const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;

export function unixToIST(unixSec: number): string {
  const date = new Date(unixSec * 1000);
  const istMs = date.getTime() + IST_OFFSET_MS;
  const istDate = new Date(istMs);

  const year = istDate.getUTCFullYear();
  const month = String(istDate.getUTCMonth() + 1).padStart(2, "0");
  const day = String(istDate.getUTCDate()).padStart(2, "0");
  const hour = String(istDate.getUTCHours()).padStart(2, "0");
  const minute = String(istDate.getUTCMinutes()).padStart(2, "0");
  const second = String(istDate.getUTCSeconds()).padStart(2, "0");

  return `${year}-${month}-${day}T${hour}:${minute}:${second}+05:30`;
}

export function msToIST(ms: number): string {
  return unixToIST(Math.floor(ms / 1000));
}

export function istToDate(istString: string): Date {
  return new Date(istString);
}

export function getISTDate(unixSec: number): string {
  const date = new Date(unixSec * 1000);
  const istMs = date.getTime() + IST_OFFSET_MS;
  const istDate = new Date(istMs);

  const year = istDate.getUTCFullYear();
  const month = String(istDate.getUTCMonth() + 1).padStart(2, "0");
  const day = String(istDate.getUTCDate()).padStart(2, "0");

  return `${year}-${month}-${day}`;
}

export function parseDateRange(from: string, to: string): {startMs: number; endMs: number} {
  const startDate = new Date(from + "T00:00:00+05:30");
  const endDate = new Date(to + "T23:59:59+05:30");

  return {
    startMs: startDate.getTime(),
    endMs: endDate.getTime(),
  };
}

export function validateDateRange(from: string, to: string): boolean {
  const {startMs, endMs} = parseDateRange(from, to);
  const daysDiff = (endMs - startMs) / (1000 * 60 * 60 * 24);
  return daysDiff >= 0 && daysDiff <= 31;
}

export function getCurrentISTDate(): string {
  return getISTDate(Math.floor(Date.now() / 1000));
}
