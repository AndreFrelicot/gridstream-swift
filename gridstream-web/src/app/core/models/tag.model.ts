export interface TagInfo {
  id: string;
  name: string;
  color: string;
  description?: string;
  ratingEnabled: boolean;
  createdAt?: string;
}

export interface TagListResponse {
  tags: TagInfo[];
}

export interface CreateTagRequest {
  name: string;
  color: string;
  description?: string;
  ratingEnabled: boolean;
}

export interface UpdateTagRequest {
  name?: string;
  color?: string;
  description?: string;
  ratingEnabled?: boolean;
}

export const TAG_COLORS = [
  '#EF4444',
  '#F97316',
  '#F59E0B',
  '#22C55E',
  '#10B981',
  '#06B6D4',
  '#3B82F6',
  '#8B5CF6',
  '#A855F7',
  '#EC4899',
];
