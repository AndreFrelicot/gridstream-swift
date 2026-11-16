import { Pipe, PipeTransform } from '@angular/core';

/** `m:ss`, or `h:mm:ss` from one hour. Invalid or negative input renders as `0:00`. */
export function formatDuration(seconds: number | null | undefined): string {
  const safe = typeof seconds === 'number' && Number.isFinite(seconds) ? Math.max(0, seconds) : 0;
  const h = Math.floor(safe / 3600);
  const m = Math.floor((safe % 3600) / 60);
  const s = Math.floor(safe % 60).toString().padStart(2, '0');
  return h > 0 ? `${h}:${m.toString().padStart(2, '0')}:${s}` : `${m}:${s}`;
}

/** Binary units with one decimal: `512 B`, `1.5 KB`, `12.3 MB`, `1.2 GB`. */
export function formatFileSize(bytes: number | null | undefined): string {
  if (typeof bytes !== 'number' || !Number.isFinite(bytes) || bytes < 0) return '—';
  if (bytes < 1024) return `${bytes} B`;
  const units = ['KB', 'MB', 'GB', 'TB'];
  let value = bytes / 1024;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return `${value.toFixed(1)} ${units[unit]}`;
}

/** `Just now`, `5m ago`, `3h ago`, `12d ago`, then the local date. */
export function formatRelativeTime(
  date: string | number | Date | null | undefined,
  now: number = Date.now(),
): string {
  if (date === null || date === undefined || date === '') return '—';
  const time = new Date(date).getTime();
  if (Number.isNaN(time)) return '—';
  const minutes = Math.floor((now - time) / 60000);
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `${days}d ago`;
  return new Date(time).toLocaleDateString();
}

@Pipe({ name: 'duration' })
export class DurationPipe implements PipeTransform {
  transform(seconds: number | null | undefined): string {
    return formatDuration(seconds);
  }
}

@Pipe({ name: 'fileSize' })
export class FileSizePipe implements PipeTransform {
  transform(bytes: number | null | undefined): string {
    return formatFileSize(bytes);
  }
}

/** Pure: the label is computed when the item renders and is not refreshed while it stays on screen. */
@Pipe({ name: 'relativeTime' })
export class RelativeTimePipe implements PipeTransform {
  transform(date: string | number | Date | null | undefined): string {
    return formatRelativeTime(date);
  }
}
