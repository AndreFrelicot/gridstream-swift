export interface TagSummary {
  id: string;
  name: string;
  color: string;
  ratingEnabled: boolean;
  rating?: number;
}

export interface VideoItem {
  id: string;
  fileId: string;
  filename: string;
  relativePath: string;
  sourceDirectoryId: string;
  duration: number;
  width: number;
  height: number;
  codec: string;
  fileSize: number;
  lastModified: string;
  rating: number;
  playCount: number;
  totalViewTime: number;
  lastPlayedAt?: string;
  annotationCount: number;
  tags?: TagSummary[];
  thumbnailUrl?: string;
  sourceDirectoryName?: string;
}

export interface PaginatedVideosResponse {
  videos: VideoItem[];
  total: number;
  limit: number;
  offset: number;
}

export interface SetThumbnailResponse {
  updatedAt: number;
}
