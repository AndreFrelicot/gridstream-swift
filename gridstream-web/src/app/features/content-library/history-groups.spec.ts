import { VideoItem } from '../../core/models/video.model';
import { groupByLocalDay, localDayKey } from './history-groups';

function video(id: string, lastPlayedAt?: Date): VideoItem {
  return { id, fileId: id, lastPlayedAt: lastPlayedAt?.toISOString() } as unknown as VideoItem;
}

describe('groupByLocalDay', () => {
  const now = new Date(2026, 10, 3, 15, 0);

  it('labels today, yesterday and older local days in incoming order', () => {
    const groups = groupByLocalDay(
      [
        video('a', new Date(2026, 10, 3, 9, 0)),
        video('b', new Date(2026, 10, 3, 0, 5)),
        video('c', new Date(2026, 10, 2, 23, 55)),
        video('d', new Date(2026, 9, 28, 12, 0)),
        video('e'),
      ],
      now,
    );

    expect(groups.map((g) => [g.label, g.videos.map((v) => v.id)])).toEqual([
      ['Today', ['a', 'b']],
      ['Yesterday', ['c']],
      ['Oct 28, 2026', ['d']],
      ['Unknown', ['e']],
    ]);
  });

  it('keys a play just after local midnight to the local day', () => {
    // 00:05 local is still the previous day in UTC for zones east of Greenwich.
    const justAfterMidnight = new Date(2026, 10, 3, 0, 5);
    expect(localDayKey(justAfterMidnight)).toBe('2026-11-03');
    expect(groupByLocalDay([video('a', justAfterMidnight)], now)[0].label).toBe('Today');
  });

  it('returns no groups for no videos', () => {
    expect(groupByLocalDay([], now)).toEqual([]);
  });
});
