import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';
import { PaginatedVideosResponse, SetThumbnailResponse, VideoItem } from '../models/video.model';
import { ApiService, apiUrl } from './api.service';

/** Query parameters accepted by `GET /videos`; all values are sent as strings. */
export type VideoQueryParams = Record<string, string>;

@Injectable({ providedIn: 'root' })
export class VideoService extends ApiService {
  getVideos(params: VideoQueryParams): Observable<PaginatedVideosResponse> {
    return this.http.get<PaginatedVideosResponse>(apiUrl`videos`, { params });
  }

  /** Single video by its stable fileId; 404 when the video no longer exists. */
  getVideoByFileId(fileId: string): Observable<VideoItem> {
    return this.http.get<VideoItem>(apiUrl`videos/by-file-id/${fileId}`);
  }

  setThumbnail(fileId: string, time: number): Observable<SetThumbnailResponse> {
    return this.http.put<SetThumbnailResponse>(apiUrl`videos/${fileId}/thumbnail`, { time });
  }

  // Media URLs. The web app relies on the same-origin session cookie for media
  // requests, so these stay plain (no token query item).

  streamUrl(fileId: string): string {
    return apiUrl`videos/${fileId}/stream`;
  }

  /**
   * Thumbnail for a video. Prefers the server-provided, versioned `thumbnailUrl`;
   * `version` forces a fresh URL after the thumbnail was changed locally.
   */
  thumbnailUrl(video: Pick<VideoItem, 'fileId' | 'thumbnailUrl'>, version?: number): string {
    if (version !== undefined) {
      return `${apiUrl`videos/${video.fileId}/thumbnail`}?v=${version}`;
    }
    return video.thumbnailUrl || apiUrl`videos/${video.fileId}/thumbnail`;
  }

  scrubFrameUrl(fileId: string, time: number): string {
    return `${apiUrl`videos/${fileId}/scrub/frame`}?time=${encodeURIComponent(time)}`;
  }

  captureImageUrl(captureId: string): string {
    return apiUrl`captures/${captureId}/image`;
  }
}
