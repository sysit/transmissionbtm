// transmissionbtm — Format utilities
// M0: skeleton. M3 expands with full formatting.

/**
 * Format download/upload speed to human-readable string.
 * @param bytesPerSecond Raw bytes/sec from native stat
 * @returns Formatted speed string (e.g. "1.2 MB/s", "512 KB/s", "0 B/s")
 */
export function formatSpeed(bytesPerSecond: number): string {
  if (bytesPerSecond === undefined || bytesPerSecond === null || bytesPerSecond < 0) {
    return '—'; // em dash
  }
  if (bytesPerSecond === 0) {
    return '0 B/s';
  }

  const units = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
  let value = bytesPerSecond;
  let unitIndex = 0;

  while (value >= 1000 && unitIndex < units.length - 1) {
    value /= 1000;
    unitIndex++;
  }

  return `${value.toFixed(unitIndex > 0 ? 1 : 0)} ${units[unitIndex]}`;
}

/**
 * Format file size to human-readable string.
 */
export function formatSize(bytes: number): string {
  if (bytes === undefined || bytes === null || bytes < 0) {
    return '—';
  }
  if (bytes === 0) {
    return '0 B';
  }

  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let value = bytes;
  let unitIndex = 0;

  while (value >= 1000 && unitIndex < units.length - 1) {
    value /= 1000;
    unitIndex++;
  }

  return `${value.toFixed(unitIndex > 0 ? 1 : 0)} ${units[unitIndex]}`;
}

/**
 * Format seconds to human-readable ETA string.
 * @param seconds Remaining seconds
 * @returns Formatted ETA (e.g. "2h 15m", "4m 12s", "—" for 0/infinity)
 */
export function formatETA(seconds: number): string {
  if (seconds === undefined || seconds === null || seconds <= 0 ||
    !isFinite(seconds)) {
    return '—';
  }

  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const secs = Math.floor(seconds % 60);

  if (hours > 0) {
    return `${hours}h ${minutes}m`;
  }
  if (minutes > 0) {
    return `${minutes}m ${secs}s`;
  }
  return `${secs}s`;
}

/**
 * Format progress value to a percentage string with one decimal place.
 * Handles both ratio (0.0–1.0) and percentage (0–100) inputs:
 *   - value <= 1.0 → treated as ratio, multiplied by 100
 *   - value > 1.0  → treated as direct percentage
 * @param value Progress value
 * @returns Formatted percentage string (e.g. "72.3%", "100%")
 */
export function formatPercentage(value: number): string {
  if (value === undefined || value === null || value < 0) {
    return '—';
  }
  if (value === 0) {
    return '0%';
  }
  // If value <= 1, treat as ratio (0.0–1.0), otherwise direct percentage
  const percent = value <= 1.0 ? value * 100 : value;
  // Show decimal only when meaningful (not a round integer)
  const rounded = Math.round(percent * 10) / 10;
  if (rounded === Math.floor(rounded)) {
    return `${Math.floor(rounded)}%`;
  }
  return `${rounded.toFixed(1)}%`;
}

/**
 * @deprecated Use formatPercentage instead.
 * Format progress ratio (0.0–1.0) to percentage string.
 */
export function formatProgress(ratio: number): string {
  return formatPercentage(ratio);
}

/**
 * Format a timestamp in milliseconds to an ISO-like date string.
 * @param ms Timestamp in milliseconds since epoch
 * @returns Formatted date string (e.g. "2026-06-28") or "—" for invalid input
 */
export function formatDate(ms: number): string {
  if (!ms || ms <= 0 || !isFinite(ms)) {
    return '—';
  }
  const date = new Date(ms);
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}
