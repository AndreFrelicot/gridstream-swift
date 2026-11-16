import { Injectable } from '@angular/core';
import { map, Observable } from 'rxjs';
import { SmartListDTO } from '../models/smart-list.model';
import { ApiService, apiUrl } from './api.service';

interface SmartListsResponse {
  smartLists: SmartListDTO[];
}

interface SmartListMembershipsResponse {
  memberships: Record<string, string[]>;
}

@Injectable({ providedIn: 'root' })
export class SmartListService extends ApiService {
  getSmartLists(): Observable<SmartListDTO[]> {
    return this.http
      .get<SmartListsResponse>(apiUrl`smart-lists`)
      .pipe(map((r) => r.smartLists));
  }

  getSmartListMemberships(): Observable<Record<string, string[]>> {
    return this.http
      .get<SmartListMembershipsResponse>(apiUrl`smart-lists/memberships`)
      .pipe(map((r) => r.memberships));
  }

  createSmartList(name: string, criteriaJSON: string): Observable<SmartListDTO> {
    return this.http.post<SmartListDTO>(apiUrl`smart-lists`, {
      name,
      criteria: criteriaJSON,
    });
  }

  updateSmartList(id: string, name: string, criteriaJSON: string): Observable<SmartListDTO> {
    return this.http.put<SmartListDTO>(apiUrl`smart-lists/${id}`, {
      name,
      criteria: criteriaJSON,
    });
  }

  deleteSmartList(id: string): Observable<void> {
    return this.http.delete<void>(apiUrl`smart-lists/${id}`);
  }
}
