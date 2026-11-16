import { Injectable, inject } from '@angular/core';
import { Observable, catchError, from, map, mergeMap, of, switchMap, toArray } from 'rxjs';
import { ClipSequence } from '../models/clip-sequence.model';
import { TimeRangeInfo } from '../models/time-range.model';
import { VideoItem } from '../models/video.model';
import { buildClipSequence } from '../utils/clip-sequence-timeline';
import { TimeRangeService } from './time-range.service';
import { VideoQueryParams, VideoService } from './video.service';

interface ClipSequenceBuildOptions {
  title: string;
  sourceLabel: string;
}

@Injectable({ providedIn: 'root' })
export class ClipSequenceBuilderService {
  private readonly timeRangeService = inject(TimeRangeService);
  private readonly videoService = inject(VideoService);

  /**
   * Builds a sequence from the videos of a library view. One request with
   * `hasTimeRanges=true` (intersected with the view's filters) narrows the
   * view to the videos that have segments, so time ranges are only fetched
   * for those instead of once per video.
   */
  buildFromView(
    videos: VideoItem[],
    viewParams: VideoQueryParams,
    options: ClipSequenceBuildOptions,
  ): Observable<ClipSequence> {
    if (videos.length === 0) {
      return this.buildFromVideos([], options);
    }
    return this.videoService
      .getVideos({ ...viewParams, hasTimeRanges: 'true', offset: '0', limit: '10000' })
      .pipe(
        map((response) => new Set(response.videos.map((video) => video.fileId))),
        switchMap((withRanges) =>
          this.buildFromVideos(
            videos.filter((video) => withRanges.has(video.fileId)),
            options,
          ),
        ),
      );
  }

  buildFromVideos(videos: VideoItem[], options: ClipSequenceBuildOptions): Observable<ClipSequence> {
    if (videos.length === 0) {
      return of(
        buildClipSequence({
          title: options.title,
          sourceLabel: options.sourceLabel,
          videos,
          rangesByFileId: {},
        }),
      );
    }

    return from(videos).pipe(
      mergeMap(
        (video) =>
          this.timeRangeService.getTimeRanges(video.fileId).pipe(
            map((response) => [video.fileId, response.timeRanges] as const),
            catchError(() => of([video.fileId, [] as TimeRangeInfo[]] as const)),
          ),
        8,
      ),
      toArray(),
      map((entries) => {
        const rangesByFileId = entries.reduce<Record<string, TimeRangeInfo[]>>(
          (result, [fileId, ranges]) => {
            result[fileId] = ranges;
            return result;
          },
          {},
        );

        return buildClipSequence({
          title: options.title,
          sourceLabel: options.sourceLabel,
          videos,
          rangesByFileId,
        });
      }),
    );
  }
}
