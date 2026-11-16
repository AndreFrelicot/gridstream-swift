import { VideoItem } from '../../core/models/video.model';

export interface HistoryGroup {
  label: string;
  /** Local `YYYY-MM-DD`, or `unknown` for videos without a play date. */
  date: string;
  videos: VideoItem[];
}

/**
 * Groups played videos by the viewer's local calendar day (not the UTC day of
 * the timestamp), keeping the incoming order.
 */
export function groupByLocalDay(videos: VideoItem[], now = new Date()): HistoryGroup[] {
  const map = new Map<string, VideoItem[]>();
  for (const video of videos) {
    const dateKey = video.lastPlayedAt ? localDayKey(new Date(video.lastPlayedAt)) : 'unknown';
    if (!map.has(dateKey)) map.set(dateKey, []);
    map.get(dateKey)!.push(video);
  }

  const todayKey = localDayKey(now);
  const yesterdayKey = localDayKey(new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1));

  return [...map].map(([date, groupVideos]) => {
    let label: string;
    if (date === 'unknown') {
      label = 'Unknown';
    } else if (date === todayKey) {
      label = 'Today';
    } else if (date === yesterdayKey) {
      label = 'Yesterday';
    } else {
      const [y, m, d] = date.split('-').map(Number);
      label = new Date(y, m - 1, d).toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
      });
    }
    return { label, date, videos: groupVideos };
  });
}

/** `YYYY-MM-DD` of a date in the local time zone. */
export function localDayKey(date: Date): string {
  const month = (date.getMonth() + 1).toString().padStart(2, '0');
  const day = date.getDate().toString().padStart(2, '0');
  return `${date.getFullYear()}-${month}-${day}`;
}
