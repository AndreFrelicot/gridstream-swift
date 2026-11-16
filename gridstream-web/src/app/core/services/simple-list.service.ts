import { Injectable } from '@angular/core';
import { map, Observable } from 'rxjs';
import { SimpleListDTO } from '../models/simple-list.model';
import { ApiService, apiUrl } from './api.service';

interface SimpleListsResponse {
  simpleLists: SimpleListDTO[];
}

@Injectable({ providedIn: 'root' })
export class SimpleListService extends ApiService {
  getSimpleLists(): Observable<SimpleListDTO[]> {
    return this.http
      .get<SimpleListsResponse>(apiUrl`simple-lists`)
      .pipe(map((r) => r.simpleLists));
  }

  createSimpleList(name: string): Observable<SimpleListDTO> {
    return this.http.post<SimpleListDTO>(apiUrl`simple-lists`, { name });
  }

  updateSimpleList(id: string, name: string, sortOrder?: string): Observable<SimpleListDTO> {
    const body: Record<string, string> = { name };
    if (sortOrder) body['sortOrder'] = sortOrder;
    return this.http.put<SimpleListDTO>(apiUrl`simple-lists/${id}`, body);
  }

  deleteSimpleList(id: string): Observable<void> {
    return this.http.delete<void>(apiUrl`simple-lists/${id}`);
  }

  addVideos(listId: string, videoIds: string[]): Observable<void> {
    return this.http.post<void>(apiUrl`simple-lists/${listId}/videos`, { videoIds });
  }
}
