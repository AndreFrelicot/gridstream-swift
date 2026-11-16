import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService, apiUrl } from './api.service';
import { FrameCaptureListResponse } from '../models/frame-capture.model';

@Injectable({ providedIn: 'root' })
export class FrameCaptureService extends ApiService {
  getAllCaptures(params: Record<string, string>): Observable<FrameCaptureListResponse> {
    return this.http.get<FrameCaptureListResponse>(apiUrl`captures`, { params });
  }

  createCapture(fileId: string, timestamp: number): Observable<unknown> {
    return this.http.post(apiUrl`videos/${fileId}/captures`, { timestamp });
  }

  deleteCapture(captureId: string): Observable<void> {
    return this.http.delete<void>(apiUrl`captures/${captureId}`);
  }
}
