import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService, apiUrl } from './api.service';
import {
  AnnotationInfo,
  AnnotationListResponse,
  UpsertAnnotationRequest,
} from '../models/annotation.model';

@Injectable({ providedIn: 'root' })
export class AnnotationService extends ApiService {
  getAnnotations(fileId: string): Observable<AnnotationListResponse> {
    return this.http.get<AnnotationListResponse>(apiUrl`videos/${fileId}/annotations`);
  }

  upsertAnnotation(fileId: string, payload: UpsertAnnotationRequest): Observable<AnnotationInfo> {
    return this.http.put<AnnotationInfo>(apiUrl`videos/${fileId}/annotations`, payload);
  }

  deleteAnnotation(fileId: string, annotationId: string): Observable<void> {
    return this.http.delete<void>(apiUrl`videos/${fileId}/annotations/${annotationId}`);
  }
}
