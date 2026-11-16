import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';
import { TimeRangeListResponse } from '../models/time-range.model';
import { ApiService, apiUrl } from './api.service';

@Injectable({ providedIn: 'root' })
export class TimeRangeService extends ApiService {
  getTimeRanges(fileId: string): Observable<TimeRangeListResponse> {
    return this.http.get<TimeRangeListResponse>(apiUrl`videos/${fileId}/time-ranges`);
  }
}
