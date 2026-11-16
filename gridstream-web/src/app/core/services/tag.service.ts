import { Injectable } from '@angular/core';
import { map, Observable } from 'rxjs';
import { TagInfo, TagListResponse, CreateTagRequest, UpdateTagRequest } from '../models/tag.model';
import { ApiService, apiUrl } from './api.service';

@Injectable({ providedIn: 'root' })
export class TagService extends ApiService {
  getTags(): Observable<TagInfo[]> {
    return this.http.get<TagListResponse>(apiUrl`tags`).pipe(map((r) => r.tags));
  }

  createTag(request: CreateTagRequest): Observable<TagInfo> {
    return this.http.post<TagInfo>(apiUrl`tags`, request);
  }

  updateTag(id: string, request: UpdateTagRequest): Observable<TagInfo> {
    return this.http.put<TagInfo>(apiUrl`tags/${id}`, request);
  }

  deleteTag(id: string): Observable<void> {
    return this.http.delete<void>(apiUrl`tags/${id}`);
  }

  /** Attaches one tag without touching the video's other tags. */
  attachTagToVideo(fileId: string, tagId: string): Observable<void> {
    return this.http
      .post<unknown>(apiUrl`videos/${fileId}/tags/${tagId}`, {})
      .pipe(map(() => undefined));
  }

  /** Detaches one tag without touching the video's other tags. */
  detachTagFromVideo(fileId: string, tagId: string): Observable<void> {
    return this.http.delete<void>(apiUrl`videos/${fileId}/tags/${tagId}`);
  }
}
