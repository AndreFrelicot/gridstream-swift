import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService, apiUrl } from './api.service';

@Injectable({ providedIn: 'root' })
export class RatingService extends ApiService {
  setRating(videoId: string, rating: number): Observable<{ rating: number }> {
    return this.http.put<{ rating: number }>(apiUrl`videos/${videoId}/rating`, {
      rating,
    });
  }
}
