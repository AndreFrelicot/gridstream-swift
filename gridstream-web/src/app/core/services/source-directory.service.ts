import { Injectable } from '@angular/core';
import { map, Observable } from 'rxjs';
import { SourceDirectoryInfo, SourceDirectoriesResponse } from '../models/source-directory.model';
import { ApiService, apiUrl } from './api.service';

@Injectable({ providedIn: 'root' })
export class SourceDirectoryService extends ApiService {
  getSourceDirectories(): Observable<SourceDirectoryInfo[]> {
    return this.http
      .get<SourceDirectoriesResponse>(apiUrl`source-directories`)
      .pipe(map((r) => r.directories));
  }
}
