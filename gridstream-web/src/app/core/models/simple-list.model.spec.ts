import { SIMPLE_LIST_SORT_ORDERS, normalizeSortOrder } from './simple-list.model';

describe('simple list sort order', () => {
  it('uses canonical snake_case values', () => {
    expect(SIMPLE_LIST_SORT_ORDERS.map((o) => o.value)).toEqual([
      'filename',
      'filename_desc',
      'file_size',
      'file_size_desc',
      'play_count',
      'play_count_desc',
      'play_time',
      'play_time_desc',
      'date_added',
      'date_added_desc',
    ]);
  });

  it('maps legacy camelCase values and unknown values', () => {
    expect(normalizeSortOrder('filenameDesc')).toBe('filename_desc');
    expect(normalizeSortOrder('playTimeDesc')).toBe('play_time_desc');
    expect(normalizeSortOrder('date_added')).toBe('date_added');
    expect(normalizeSortOrder('bogus')).toBe('filename');
    expect(normalizeSortOrder(undefined)).toBe('filename');
  });
});
