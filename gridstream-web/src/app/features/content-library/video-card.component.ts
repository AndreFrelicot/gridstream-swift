import { Component, DestroyRef, computed, inject, input, output, signal } from '@angular/core';

import { VideoItem } from '../../core/models/video.model';
import { VideoService } from '../../core/services/video.service';
import { DurationPipe } from '../../shared/pipes/format';

export interface ListBadge {
  id: string;
  name: string;
}

/** Library card with hover scrub preview, tags and list badges. */
@Component({
  selector: 'app-video-card',
  imports: [DurationPipe],
  template: `
    <button
      (click)="open.emit()"
      (contextmenu)="menuRequested.emit($event)"
      class="cursor-pointer group flex min-w-0 flex-col text-left"
    >
      <div
        class="relative aspect-video bg-card overflow-hidden rounded-xl ring-1 ring-white/5 transition group-hover:ring-2 group-hover:ring-primary"
        (mouseenter)="onScrubEnter()"
        (mousemove)="onScrubMove($event)"
        (mouseleave)="onScrubLeave()"
      >
        <img
          [src]="imageUrl()"
          alt="{{ video().filename }}"
          [class.group-hover:scale-105]="!scrub()"
          [class.transition]="!scrub()"
          class="w-full h-full object-cover"
        />
        @if (video().rating > 0) {
          <span
            class="absolute right-1.5 top-1.5 inline-flex items-center gap-1 rounded-full bg-black/55 px-1.5 py-0.5 text-[11px] font-semibold leading-none text-white backdrop-blur-sm"
            [title]="'Rating ' + video().rating + '/10'"
          >
            <svg class="w-3 h-3 text-destructive" viewBox="0 0 24 24" fill="currentColor">
              <path
                d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"
              />
            </svg>
            {{ video().rating }}
          </span>
        }
        <span
          class="absolute bottom-1.5 right-1.5 rounded-md bg-black/60 px-1.5 py-0.5 text-[10px] font-medium leading-none tabular-nums text-white"
        >
          {{ video().duration | duration }}
        </span>
        @if (scrub(); as s) {
          <div class="absolute bottom-0 left-0 h-0.5 bg-primary" [style.width.%]="s.percent"></div>
        }
      </div>
      <div class="px-0.5 pt-2 pb-1 space-y-1">
        <h3 class="font-medium text-[13px] leading-snug line-clamp-2" [title]="video().filename">
          {{ video().filename }}
        </h3>
        <div class="flex items-center justify-between gap-2 text-xs text-muted-foreground">
          @if (video().sourceDirectoryName) {
            <span class="truncate" [title]="video().sourceDirectoryName">
              {{ video().sourceDirectoryName }}
            </span>
          }
          <span class="ml-auto shrink-0">{{ video().playCount }} plays</span>
        </div>
        @if (video().tags?.length) {
          <div class="flex flex-wrap gap-1">
            @for (tag of video().tags; track tag.id) {
              <span
                class="px-2 py-0.5 rounded-full text-[10px] font-medium leading-none text-white"
                [style.background-color]="tag.color"
              >
                {{ tag.name }}
              </span>
            }
          </div>
        }
        @if (smartBadges().length || simpleBadges().length) {
          <div class="flex flex-wrap gap-1">
            @for (badge of smartBadges(); track badge.id) {
              <span
                class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] leading-none bg-primary/15 text-primary"
                [title]="'Smart List: ' + badge.name"
              >
                <svg class="w-2.5 h-2.5 flex-shrink-0" viewBox="0 0 24 24" fill="currentColor">
                  <polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3" />
                </svg>
                <span class="truncate max-w-[80px]">{{ badge.name }}</span>
              </span>
            }
            @for (badge of simpleBadges(); track badge.id) {
              <span
                class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] leading-none bg-secondary text-secondary-foreground"
                [title]="'List: ' + badge.name"
              >
                <svg
                  class="w-2.5 h-2.5 flex-shrink-0"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2.5"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                >
                  <line x1="8" y1="6" x2="21" y2="6" />
                  <line x1="8" y1="12" x2="21" y2="12" />
                  <line x1="8" y1="18" x2="21" y2="18" />
                  <line x1="3" y1="6" x2="3.01" y2="6" />
                  <line x1="3" y1="12" x2="3.01" y2="12" />
                  <line x1="3" y1="18" x2="3.01" y2="18" />
                </svg>
                <span class="truncate max-w-[80px]">{{ badge.name }}</span>
              </span>
            }
          </div>
        }
      </div>
    </button>
  `,
  styles: [
    `
      :host {
        display: contents;
      }
    `,
  ],
})
export class VideoCardComponent {
  private readonly videoService = inject(VideoService);

  readonly video = input.required<VideoItem>();
  readonly smartBadges = input<ListBadge[]>([]);
  readonly simpleBadges = input<ListBadge[]>([]);

  readonly open = output<void>();
  readonly menuRequested = output<MouseEvent>();

  /** Hover scrub position; the frame URL is set after the pointer settles. */
  readonly scrub = signal<{ percent: number; frameUrl: string | null } | null>(null);
  readonly imageUrl = computed(
    () => this.scrub()?.frameUrl ?? this.videoService.thumbnailUrl(this.video()),
  );

  private frameTimer: ReturnType<typeof setTimeout> | null = null;

  constructor() {
    inject(DestroyRef).onDestroy(() => this.clearFrameTimer());
  }

  onScrubEnter(): void {
    this.scrub.set({ percent: 0, frameUrl: null });
  }

  onScrubMove(event: MouseEvent): void {
    const rect = (event.currentTarget as HTMLElement).getBoundingClientRect();
    const x = Math.max(0, Math.min(event.clientX - rect.left, rect.width));
    const percent = (x / rect.width) * 100;
    const video = this.video();
    const time = Math.floor((percent / 100) * video.duration);

    this.scrub.set({ percent, frameUrl: this.scrub()?.frameUrl ?? null });

    this.clearFrameTimer();
    this.frameTimer = setTimeout(() => {
      const current = this.scrub();
      if (current) {
        this.scrub.set({
          ...current,
          frameUrl: this.videoService.scrubFrameUrl(video.fileId, time),
        });
      }
    }, 100);
  }

  onScrubLeave(): void {
    this.scrub.set(null);
    this.clearFrameTimer();
  }

  private clearFrameTimer(): void {
    if (this.frameTimer) {
      clearTimeout(this.frameTimer);
      this.frameTimer = null;
    }
  }
}
