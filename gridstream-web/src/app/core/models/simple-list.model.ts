export interface SimpleListDTO {
  id: string;
  name: string;
  videoIds: string[];
  videoCount: number;
  sortOrder: string;
  createdAt: string;
  updatedAt: string;
}

/** Canonical simple list sort orders (snake_case, contracts/decisions.md §3). */
export const SIMPLE_LIST_SORT_ORDERS = [
  { value: 'filename', label: 'Filename (A-Z)' },
  { value: 'filename_desc', label: 'Filename (Z-A)' },
  { value: 'file_size', label: 'File Size (Small to Large)' },
  { value: 'file_size_desc', label: 'File Size (Large to Small)' },
  { value: 'play_count', label: 'Play Count (Low to High)' },
  { value: 'play_count_desc', label: 'Play Count (High to Low)' },
  { value: 'play_time', label: 'Play Time (Low to High)' },
  { value: 'play_time_desc', label: 'Play Time (High to Low)' },
  { value: 'date_added', label: 'Date Added (Newest)' },
  { value: 'date_added_desc', label: 'Date Added (Oldest)' },
] as const;

export type SimpleListSortOrder = (typeof SIMPLE_LIST_SORT_ORDERS)[number]['value'];

/** Maps legacy camelCase values (`filenameDesc`) to the canonical snake_case form. */
export function normalizeSortOrder(value: string | null | undefined): SimpleListSortOrder {
  const snake = (value ?? '').replace(/[A-Z]/g, (c) => `_${c.toLowerCase()}`);
  return SIMPLE_LIST_SORT_ORDERS.find((o) => o.value === snake)?.value ?? 'filename';
}
