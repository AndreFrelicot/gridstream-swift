import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService, apiUrl } from './api.service';
import { BlockedVideo } from '../models/scrub-issue.model';

@Injectable({ providedIn: 'root' })
export class ScrubIssueService extends ApiService {
  getBlocked(): Observable<BlockedVideo[]> {
    return this.http.get<BlockedVideo[]>(apiUrl`scrub/blocked`);
  }

  reset(fileId: string): Observable<unknown> {
    return this.http.post(apiUrl`videos/${fileId}/scrub/reset`, {});
  }
}
