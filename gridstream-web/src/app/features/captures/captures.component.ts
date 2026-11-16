import { Component, HostListener, OnInit, computed, inject, signal } from '@angular/core';
import { DurationPipe, FileSizePipe, RelativeTimePipe } from '../../shared/pipes/format';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { Subject, catchError, debounceTime, map, of, switchMap } from 'rxjs';
import { HttpErrorResponse } from '@angular/common/http';
import { FrameCaptureService } from '../../core/services/frame-capture.service';
import { FrameCaptureInfo } from '../../core/models/frame-capture.model';
import { VideoService } from '../../core/services/video.service';
import { VideoItem } from '../../core/models/video.model';
import { TagService } from '../../core/services/tag.service';
import { SourceDirectoryService } from '../../core/services/source-directory.service';
import { SimpleListService } from '../../core/services/simple-list.service';
import { TagInfo } from '../../core/models/tag.model';
import { SourceDirectoryInfo } from '../../core/models/source-directory.model';
import { SimpleListDTO } from '../../core/models/simple-list.model';
import { ConditionEditorComponent } from '../../shared/criteria/condition-editor.component';
import { LoadErrorComponent } from '../../shared/ui/load-error.component';
import {
  ConditionDraft,
  createCondition,
  serializeCriteria,
} from '../../shared/criteria/criteria';
import { VideoPlayerDialogComponent } from '../video-player/video-player-dialog.component';

@Component({
  selector: 'app-captures',
  imports: [DurationPipe, FileSizePipe, RelativeTimePipe, ConditionEditorComponent, LoadErrorComponent, VideoPlayerDialogComponent],
  template: `
    <div class="flex flex-col h-full bg-background text-foreground">
      <div class="flex items-center gap-2 px-4 py-2 border-b border-border">
        <h1 class="text-sm font-semibold">Frame Captures</h1>
        <div class="flex-1"></div>
        <button
          (click)="toggleFilters()"
          class="px-3 py-1 text-xs rounded-full transition-colors"
          [class]="
            filtersActive()
              ? 'bg-primary text-primary-foreground'
              : 'bg-secondary text-secondary-foreground hover:bg-secondary/80'
          "
        >
          {{ filtersActive() ? 'Filters Active' : 'Filters' }}
        </button>
        <span class="text-xs text-muted-foreground tabular-nums">
          {{ totalCaptures() }} captures
        </span>
      </div>

      <!-- Query Builder Filter Panel -->
      @if (showFilters()) {
        <div class="border-b border-border bg-card/50 p-4 space-y-4">
          <app-condition-editor
            [conditions]="conditions()"
            (conditionsChange)="onConditionsChange($event)"
            [tags]="availableTags()"
            [sources]="availableSources()"
            [simpleLists]="simpleLists()"
          />
          @if (hasActiveConditions()) {
            <button
              type="button"
              (click)="clearFilters()"
              class="px-3 py-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
            >
              Clear All
            </button>
          }
        </div>
      }

      <div class="flex-1 overflow-auto p-4">
        @if (actionError()) {
          <div
            class="mb-3 flex items-center justify-between gap-3 rounded-lg border border-destructive/40 bg-destructive/10 px-3 py-2 text-xs text-destructive"
            role="alert"
          >
            <span>{{ actionError() }}</span>
            <button
              type="button"
              (click)="actionError.set(null)"
              class="text-destructive/80 hover:text-destructive"
              aria-label="Dismiss error"
            >
              ×
            </button>
          </div>
        }
        @if (loading()) {
          <div class="flex items-center justify-center h-full">
            <div class="text-muted-foreground text-sm">Loading captures...</div>
          </div>
        } @else if (loadError()) {
          <app-load-error class="h-full" [message]="loadError()!" (retry)="loadCaptures()" />
        } @else if (captures().length === 0) {
          <div class="flex items-center justify-center h-full">
            <div class="text-muted-foreground text-sm">
              {{
                filtersActive() ? 'No captures match the current filters' : 'No frame captures yet'
              }}
            </div>
          </div>
        } @else {
          <div
            class="grid gap-3 grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6"
          >
            @for (capture of captures(); track capture.id) {
              <div
                class="group bg-card rounded-2xl overflow-hidden border border-border hover:border-primary transition"
              >
                <button (click)="openCapture(capture)" class="cursor-pointer w-full text-left">
                  <div class="relative aspect-video bg-black overflow-hidden">
                    <img
                      [src]="getImageUrl(capture)"
                      [alt]="capture.filename ?? 'Captured frame'"
                      class="w-full h-full object-cover group-hover:scale-105 transition"
                    />
                    <div
                      class="absolute inset-0 bg-black opacity-0 group-hover:opacity-20 transition"
                    ></div>
                  </div>
                  <div class="p-2 space-y-1">
                    <h3 class="font-semibold text-xs truncate" [title]="capture.filename ?? ''">
                      {{ capture.filename ?? 'Unknown' }}
                    </h3>
                    <div class="flex items-center justify-between text-xs text-muted-foreground">
                      <span>{{ capture.timestamp | duration }}</span>
                      <span>{{ capture.width }}x{{ capture.height }}</span>
                    </div>
                    <div class="flex items-center justify-between text-xs text-muted-foreground">
                      <span>{{ capture.fileSize | fileSize }}</span>
                      <span>{{ capture.createdAt | relativeTime }}</span>
                    </div>
                  </div>
                </button>
                <div class="px-2 pb-2">
                  <button
                    (click)="deleteCapture(capture, $event)"
                    class="w-full px-3 py-1 text-xs text-destructive hover:bg-destructive/10 rounded-full transition"
                  >
                    Delete
                  </button>
                </div>
              </div>
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

    @if (selectedCapture()) {
      <div
        class="fixed inset-0 z-50 bg-black/90 flex flex-col items-center justify-center"
        (click)="selectedCapture.set(null)"
        (keydown.escape)="selectedCapture.set(null)"
        tabindex="0"
      >
        <img
          [src]="getImageUrl(selectedCapture()!)"
          [alt]="selectedCapture()!.filename ?? 'Captured frame'"
          class="max-w-[95vw] max-h-[85vh] object-contain"
          (click)="$event.stopPropagation()"
          (keydown)="$event.stopPropagation()"
          tabindex="-1"
        />
        <div
          class="flex items-center gap-4 mt-3 px-4 py-2 bg-black/60 rounded-full text-xs text-white/80"
          (click)="$event.stopPropagation()"
          (keydown)="$event.stopPropagation()"
          tabindex="-1"
        >
          <span>{{ selectedCapture()!.filename ?? 'Unknown' }}</span>
          <span class="text-white/40">|</span>
          <span>{{ selectedCapture()!.timestamp | duration }}</span>
          <span class="text-white/40">|</span>
          <span>{{ selectedCapture()!.width }}x{{ selectedCapture()!.height }}</span>
          <span class="text-white/40">|</span>
          <button
            type="button"
            (click)="downloadCapture(selectedCapture()!)"
            class="text-primary hover:text-primary/80 transition-colors"
            [attr.aria-label]="'Download ' + captureDownloadName(selectedCapture()!)"
          >
            Download
          </button>
          <span class="text-white/40">|</span>
          <button
            (click)="openVideo(selectedCapture()!)"
            class="text-primary hover:text-primary/80 transition-colors"
          >
            Open in player
          </button>
        </div>
      </div>
    }

    @if (selectedVideo()) {
      <app-video-player-dialog
        [video]="selectedVideo()!"
        [startTime]="videoStartTime()"
        (closed)="selectedVideo.set(null)"
      />
    }
  `,
})
export class CapturesComponent implements OnInit {
  @HostListener('document:keydown.escape')
  onEscape() {
    if (this.selectedCapture()) {
      this.selectedCapture.set(null);
    }
  }

  private captureService = inject(FrameCaptureService);
  private videoService = inject(VideoService);
  private tagService = inject(TagService);
  private sourceDirectoryService = inject(SourceDirectoryService);
  private simpleListService = inject(SimpleListService);

  captures = signal<FrameCaptureInfo[]>([]);
  totalCaptures = signal(0);
  loading = signal(false);
  loadError = signal<string | null>(null);
  actionError = signal<string | null>(null);
  selectedCapture = signal<FrameCaptureInfo | null>(null);
  selectedVideo = signal<VideoItem | null>(null);
  videoStartTime = signal(0);
  currentPage = signal(1);
  readonly pageSize = 50;
  totalPages = computed(() => Math.max(1, Math.ceil(this.totalCaptures() / this.pageSize)));

  // Filter state
  showFilters = signal(false);
  conditions = signal<ConditionDraft[]>([]);
  private readonly criteria = computed(() => serializeCriteria(this.conditions()));
  hasActiveConditions = computed(() => this.criteria() !== null);
  availableTags = signal<TagInfo[]>([]);
  availableSources = signal<SourceDirectoryInfo[]>([]);
  simpleLists = signal<SimpleListDTO[]>([]);

  private readonly captureRequests = new Subject<Record<string, string>>();
  private readonly filterChanges = new Subject<void>();

  constructor() {
    this.captureRequests
      .pipe(
        switchMap((params) =>
          this.captureService.getAllCaptures(params).pipe(
            map((response) => ({ response, error: null })),
            catchError((error: unknown) => of({ response: null, error })),
          ),
        ),
        takeUntilDestroyed(),
      )
      .subscribe(({ response, error }) => {
        this.loading.set(false);
        if (response) {
          this.captures.set(response.captures);
          this.totalCaptures.set(response.total);
        } else {
          console.error('Failed to load captures:', error);
          this.captures.set([]);
          this.loadError.set('Could not load captures.');
        }
      });

    this.filterChanges.pipe(debounceTime(500), takeUntilDestroyed()).subscribe(() => {
      this.currentPage.set(1);
      this.loadCaptures();
    });
  }

  ngOnInit() {
    this.loadCaptures();
    this.loadFilterData();
  }

  private loadFilterData() {
    this.tagService.getTags().subscribe((tags) => this.availableTags.set(tags));
    this.sourceDirectoryService
      .getSourceDirectories()
      .subscribe((sources) => this.availableSources.set(sources));
    this.simpleListService.getSimpleLists().subscribe((lists) => this.simpleLists.set(lists));
  }

  filtersActive(): boolean {
    return this.hasActiveConditions();
  }

  toggleFilters() {
    if (this.showFilters()) {
      this.showFilters.set(false);
    } else {
      this.showFilters.set(true);
      if (this.conditions().length === 0) {
        this.conditions.set([createCondition()]);
      }
    }
  }

  clearFilters() {
    this.conditions.set([createCondition()]);
    this.currentPage.set(1);
    this.loadCaptures();
  }

  onConditionsChange(conditions: ConditionDraft[]) {
    const previous = this.criteria();
    this.conditions.set(conditions);
    // Only refetch when the effective (complete) criteria changed.
    if (this.criteria() !== previous) {
      this.onFilterChange();
    }
  }

  onFilterChange() {
    this.filterChanges.next();
  }

  loadCaptures() {
    this.loading.set(true);
    this.loadError.set(null);
    const offset = (this.currentPage() - 1) * this.pageSize;
    const params: Record<string, string> = {
      limit: this.pageSize.toString(),
      offset: offset.toString(),
    };

    const criteria = this.criteria();
    if (criteria) {
      params['criteria'] = criteria;
    }

    this.captureRequests.next(params);
  }

  openCapture(capture: FrameCaptureInfo) {
    this.selectedCapture.set(capture);
  }

  downloadCapture(capture: FrameCaptureInfo) {
    const a = document.createElement('a');
    a.href = this.getImageUrl(capture);
    a.download = captureDownloadName(capture);
    a.click();
  }

  openVideo(capture: FrameCaptureInfo) {
    this.selectedCapture.set(null);
    this.videoStartTime.set(capture.timestamp);
    this.actionError.set(null);
    this.videoService.getVideoByFileId(capture.fileId).subscribe({
      next: (video) => this.selectedVideo.set(video),
      error: (err: unknown) => {
        console.error('Failed to open capture video:', err);
        this.actionError.set(
          err instanceof HttpErrorResponse && err.status === 404
            ? 'The source video is no longer in the library.'
            : 'Could not open the source video.',
        );
      },
    });
  }

  deleteCapture(capture: FrameCaptureInfo, event: Event) {
    event.stopPropagation();
    if (!confirm('Delete this capture?')) return;

    this.actionError.set(null);
    this.captureService.deleteCapture(capture.id).subscribe({
      next: () => {
        const wasLastPage = this.currentPage() >= this.totalPages();
        this.captures.update((caps) => caps.filter((c) => c.id !== capture.id));
        this.totalCaptures.update((total) => Math.max(0, total - 1));
        if (this.captures().length === 0 && this.currentPage() > 1) {
          // The page became empty: step back.
          this.currentPage.update((p) => p - 1);
          this.loadCaptures();
        } else if (!wasLastPage) {
          // Pull the first capture of the next page into this one.
          this.loadCaptures();
        }
      },
      error: (err: unknown) => {
        console.error('Failed to delete capture:', err);
        this.actionError.set('Could not delete the capture.');
      },
    });
  }

  previousPage() {
    if (this.currentPage() > 1) {
      this.currentPage.update((p) => p - 1);
      this.loadCaptures();
    }
  }

  nextPage() {
    if (this.currentPage() < this.totalPages()) {
      this.currentPage.update((p) => p + 1);
      this.loadCaptures();
    }
  }

  protected readonly captureDownloadName = captureDownloadName;

  getImageUrl(capture: FrameCaptureInfo): string {
    return this.videoService.captureImageUrl(capture.id);
  }


}

/** `clip_1m05s.jpg` for a capture of clip.mp4 at 65 s. */
export function captureDownloadName(capture: Pick<FrameCaptureInfo, 'filename' | 'timestamp'>) {
  const base = (capture.filename ?? 'capture').replace(/\.[^./\\]+$/, '') || 'capture';
  const total = Math.max(0, Math.floor(capture.timestamp));
  const minutes = Math.floor(total / 60);
  const seconds = (total % 60).toString().padStart(2, '0');
  return `${base}_${minutes}m${seconds}s.jpg`;
}
