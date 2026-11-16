import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { DurationPipe, RelativeTimePipe } from '../../shared/pipes/format';
import { VideoService } from '../../core/services/video.service';
import { VideoItem } from '../../core/models/video.model';
import { VideoPlayerDialogComponent } from '../video-player/video-player-dialog.component';
import { LoadErrorComponent } from '../../shared/ui/load-error.component';

@Component({
  selector: 'app-history',
  imports: [DurationPipe, RelativeTimePipe, LoadErrorComponent, VideoPlayerDialogComponent],
  template: `
    <div class="flex flex-col h-full bg-background text-foreground">
      <div class="flex items-center gap-2 px-4 py-2 border-b border-border">
        <h1 class="text-sm font-semibold">Watch History</h1>
        <div class="flex-1"></div>
        <span class="text-xs text-muted-foreground tabular-nums">
          {{ total() }} videos
        </span>
      </div>

      <div class="flex-1 overflow-auto p-4">
        @if (loading()) {
          <div class="flex items-center justify-center h-full">
            <div class="text-muted-foreground text-sm">Loading history...</div>
          </div>
        } @else if (loadError()) {
          <app-load-error class="h-full" [message]="loadError()!" (retry)="loadVideos()" />
        } @else if (videos().length === 0) {
          <div class="flex items-center justify-center h-full">
            <div class="text-muted-foreground text-sm">No watch history yet</div>
          </div>
        } @else {
          <div
            class="grid gap-3 grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6"
          >
            @for (video of videos(); track video.id) {
              <button
                (click)="playVideo(video)"
                class="cursor-pointer group flex min-w-0 flex-col text-left"
              >
                <div
                  class="relative aspect-video bg-card overflow-hidden rounded-xl ring-1 ring-white/5 transition group-hover:ring-2 group-hover:ring-primary"
                >
                  <img
                    [src]="getThumbnail(video)"
                    [alt]="video.filename"
                    class="w-full h-full object-cover group-hover:scale-105 transition"
                  />
                  @if (video.rating > 0) {
                    <span
                      class="absolute right-1.5 top-1.5 inline-flex items-center gap-1 rounded-full bg-black/55 px-1.5 py-0.5 text-[11px] font-semibold leading-none text-white backdrop-blur-sm"
                      [title]="'Rating ' + video.rating + '/10'"
                    >
                      <svg class="w-3 h-3 text-destructive" viewBox="0 0 24 24" fill="currentColor">
                        <path
                          d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"
                        />
                      </svg>
                      {{ video.rating }}
                    </span>
                  }
                  <span
                    class="absolute bottom-1.5 right-1.5 rounded-md bg-black/60 px-1.5 py-0.5 text-[10px] font-medium leading-none tabular-nums text-white"
                  >
                    {{ video.duration | duration }}
                  </span>
                </div>
                <div class="px-0.5 pt-2 pb-1 space-y-1">
                  <h3 class="font-medium text-[13px] leading-snug line-clamp-2" [title]="video.filename">
                    {{ video.filename }}
                  </h3>
                  <div class="flex items-center justify-between text-xs text-muted-foreground">
                    <span>{{ video.playCount }} plays</span>
                    <span>{{ video.lastPlayedAt | relativeTime }}</span>
                  </div>
                </div>
              </button>
            }
          </div>
        }
      </div>

      <div class="flex items-center justify-center gap-2 px-4 py-2 border-t border-border">
        <button
          [disabled]="currentPage() === 1"
          (click)="previousPage()"
          class="px-3 py-1 text-xs bg-secondary text-secondary-foreground rounded-full disabled:opacity-50 disabled:cursor-not-allowed hover:bg-secondary/80"
        >
          Previous
        </button>
        <span class="text-xs text-muted-foreground tabular-nums">
          Page {{ currentPage() }} / {{ totalPages() }}
        </span>
        <button
          [disabled]="currentPage() >= totalPages()"
          (click)="nextPage()"
          class="px-3 py-1 text-xs bg-secondary text-secondary-foreground rounded-full disabled:opacity-50 disabled:cursor-not-allowed hover:bg-secondary/80"
        >
          Next
        </button>
      </div>
    </div>

    @if (selectedVideo()) {
      <app-video-player-dialog
        [video]="selectedVideo()!"
        (closed)="selectedVideo.set(null)"
        (thumbnailUpdated)="onThumbnailUpdated($event)"
        (ratingChanged)="onRatingChanged($event)"
      />
    }
  `,
})
export class HistoryComponent implements OnInit {
  private videoService = inject(VideoService);

  videos = signal<VideoItem[]>([]);
  loading = signal(false);
  loadError = signal<string | null>(null);
  selectedVideo = signal<VideoItem | null>(null);
  total = signal(0);
  currentPage = signal(1);
  readonly pageSize = 50;
  totalPages = computed(() => Math.max(1, Math.ceil(this.total() / this.pageSize)));

  ngOnInit() {
    this.loadVideos();
  }

  loadVideos() {
    this.loading.set(true);
    this.loadError.set(null);
    const offset = (this.currentPage() - 1) * this.pageSize;
    const params = {
      played: 'true',
      sort: 'last_played_desc',
      limit: this.pageSize.toString(),
      offset: offset.toString(),
    };

    this.videoService.getVideos(params).subscribe({
      next: (response) => {
        this.videos.set(response.videos);
        this.total.set(response.total);
        this.loading.set(false);
      },
      error: (err: unknown) => {
        console.error('Failed to load history:', err);
        this.videos.set([]);
        this.loadError.set('Could not load watch history.');
        this.loading.set(false);
      },
    });
  }

  playVideo(video: VideoItem) {
    this.selectedVideo.set(video);
  }

  previousPage() {
    if (this.currentPage() > 1) {
      this.currentPage.update((p) => p - 1);
      this.loadVideos();
    }
  }

  nextPage() {
    if (this.currentPage() < this.totalPages()) {
      this.currentPage.update((p) => p + 1);
      this.loadVideos();
    }
  }

  onThumbnailUpdated(fileId: string): void {
    const version = Date.now();
    this.videos.update((vids) =>
      vids.map((v) =>
        v.fileId === fileId
          ? { ...v, thumbnailUrl: this.videoService.thumbnailUrl(v, version) }
          : v,
      ),
    );
  }

  onRatingChanged(event: { fileId: string; rating: number }): void {
    this.videos.update((vids) =>
      vids.map((v) => (v.fileId === event.fileId ? { ...v, rating: event.rating } : v)),
    );
  }

  getThumbnail(video: VideoItem): string {
    return this.videoService.thumbnailUrl(video);
  }
}
