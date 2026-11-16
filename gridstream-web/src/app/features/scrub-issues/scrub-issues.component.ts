import { Component, HostListener, OnInit, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { ScrubIssueService } from '../../core/services/scrub-issue.service';
import { BlockedVideo } from '../../core/models/scrub-issue.model';
import { VideoItem } from '../../core/models/video.model';
import { VideoPlayerDialogComponent } from '../video-player/video-player-dialog.component';
import { LoadErrorComponent } from '../../shared/ui/load-error.component';

@Component({
  selector: 'app-scrub-issues',
  imports: [DatePipe, LoadErrorComponent, VideoPlayerDialogComponent],
  template: `
    <div class="p-6 max-w-5xl mx-auto">
      <div class="flex items-center justify-between mb-4">
        <div>
          <h1 class="text-xl font-semibold">Scrub Issues</h1>
          <p class="text-sm text-muted-foreground">
            Videos that repeatedly failed scrub-frame generation and were removed from the indexing
            pool.
          </p>
        </div>
        <button
          (click)="loadBlocked()"
          class="px-3 py-1.5 text-sm rounded-full border border-border hover:bg-muted transition"
        >
          Refresh
        </button>
      </div>

      @if (retryError()) {
        <div class="mb-3 text-sm text-destructive" role="alert">{{ retryError() }}</div>
      }
      @if (loading()) {
        <div class="text-sm text-muted-foreground py-8 text-center">Loading…</div>
      } @else if (loadError()) {
        <app-load-error [message]="loadError()!" (retry)="loadBlocked()" />
      } @else if (blocked().length === 0) {
        <div class="text-center py-16 text-muted-foreground">No blocked videos 🎉</div>
      } @else {
        <div class="space-y-3">
          @for (item of blocked(); track item.video.fileId) {
            <div class="bg-card rounded-2xl border border-border p-4">
              <div class="flex items-start justify-between gap-4">
                <div class="min-w-0 flex-1">
                  <div class="font-medium truncate">{{ item.video.filename }}</div>
                  <div class="mt-1 text-xs font-mono text-muted-foreground break-all select-all">
                    {{ item.path }}
                  </div>
                  <div class="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground">
                    <span>Attempts: {{ item.attemptCount }}</span>
                    <span>Frames: {{ item.frameCount }} / {{ item.expectedFrames }}</span>
                    <span>Last attempt: {{ item.lastAttemptAt ? (item.lastAttemptAt * 1000 | date: 'medium') : '—' }}</span>
                  </div>
                  @if (item.lastError) {
                    <div
                      class="mt-2 text-sm text-destructive bg-destructive/10 rounded-lg px-2 py-1 break-words"
                    >
                      {{ item.lastError }}
                    </div>
                  }
                </div>
                <div class="flex flex-col gap-2 shrink-0">
                  <button
                    (click)="inspect(item)"
                    class="px-3 py-1.5 text-sm rounded-full bg-primary text-primary-foreground hover:opacity-90 transition"
                  >
                    Inspect
                  </button>
                  <button
                    (click)="retry(item)"
                    class="px-3 py-1.5 text-sm rounded-full border border-border hover:bg-muted transition"
                  >
                    Retry
                  </button>
                </div>
              </div>
            </div>
          }
        </div>
      }
    </div>

    @if (selected()) {
      <app-video-player-dialog [video]="selected()!" (closed)="selected.set(null)" />
    }
  `,
})
export class ScrubIssuesComponent implements OnInit {
  @HostListener('document:keydown.escape')
  onEscape() {
    if (this.selected()) {
      this.selected.set(null);
    }
  }

  private scrubIssueService = inject(ScrubIssueService);

  blocked = signal<BlockedVideo[]>([]);
  loading = signal(false);
  loadError = signal<string | null>(null);
  retryError = signal<string | null>(null);
  selected = signal<VideoItem | null>(null);

  ngOnInit() {
    this.loadBlocked();
  }

  loadBlocked() {
    this.loading.set(true);
    this.loadError.set(null);
    this.scrubIssueService.getBlocked().subscribe({
      next: (blocked) => {
        this.blocked.set(blocked);
        this.loading.set(false);
      },
      error: (err: unknown) => {
        console.error('Failed to load scrub issues:', err);
        this.blocked.set([]);
        this.loadError.set('Could not load scrub issues.');
        this.loading.set(false);
      },
    });
  }

  inspect(item: BlockedVideo) {
    this.selected.set(item.video);
  }

  retry(item: BlockedVideo) {
    this.retryError.set(null);
    this.scrubIssueService.reset(item.video.fileId).subscribe({
      next: () => this.loadBlocked(),
      error: (err: unknown) => {
        console.error('Failed to reset scrub state:', err);
        this.retryError.set(`Could not retry ${item.video.filename}.`);
      },
    });
  }
}
