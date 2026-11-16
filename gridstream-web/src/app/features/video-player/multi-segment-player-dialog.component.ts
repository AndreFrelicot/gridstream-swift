import {
  AfterViewInit,
  Component,
  ElementRef,
  OnDestroy,
  ViewChild,
  computed,
  inject,
  input,
  output,
  signal,
} from '@angular/core';
import { DurationPipe } from '../../shared/pipes/format';
import { VideoService } from '../../core/services/video.service';
import { ClipSequence } from '../../core/models/clip-sequence.model';
import { mapVirtualTimeToSegment } from '../../core/utils/clip-sequence-timeline';
import { MultiSegmentProgressBarComponent } from './multi-segment-progress-bar.component';

interface VideoSlotState {
  segmentIndex: number | null;
  ready: boolean;
  source: string;
  pendingSeekTime: number | null;
}

@Component({
  selector: 'app-multi-segment-player-dialog',
  imports: [DurationPipe, MultiSegmentProgressBarComponent],
  template: `
    <div
      role="dialog"
      aria-modal="true"
      tabindex="0"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/85 backdrop-blur-sm"
      (click)="onBackdropClick($event)"
      (keydown.escape)="closed.emit()"
      (keydown.space)="onKeySpace($event)"
      (keydown.arrowleft)="onKeyArrowLeft($event)"
      (keydown.arrowright)="onKeyArrowRight($event)"
    >
      <div
        class="relative mx-4 flex w-full max-w-6xl flex-col overflow-hidden rounded-2xl border border-border bg-card shadow-2xl"
      >
        <div class="flex items-center justify-between gap-4 border-b border-border px-5 py-3">
          <div class="min-w-0">
            <h2 class="truncate text-sm font-semibold text-card-foreground">
              {{ sequence().title }}
            </h2>
            <div class="truncate text-xs text-muted-foreground">
              {{ sequence().sourceLabel }} - {{ sequence().segments.length }} segments -
              {{ sequence().duration | duration }}
            </div>
          </div>
          <button
            (click)="closed.emit()"
            class="rounded-full p-1.5 text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
            aria-label="Close player"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="18"
              height="18"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <path d="M18 6 6 18" />
              <path d="m6 6 12 12" />
            </svg>
          </button>
        </div>

        <div #videoContainer class="group relative aspect-video bg-black">
          <video
            #primaryVideo
            preload="auto"
            playsinline
            class="absolute inset-0 h-full w-full bg-black object-contain transition-opacity duration-150"
            [class.opacity-100]="activeSlotIndex() === 0"
            [class.opacity-0]="activeSlotIndex() !== 0"
            [class.pointer-events-auto]="activeSlotIndex() === 0"
            [class.pointer-events-none]="activeSlotIndex() !== 0"
            (loadedmetadata)="onSlotLoadedMetadata(0)"
            (canplay)="onSlotCanPlay(0)"
            (timeupdate)="onSlotTimeUpdate(0)"
            (play)="onSlotPlay(0)"
            (pause)="onSlotPause(0)"
            (error)="onSlotError(0)"
            (click)="togglePlay()"
          ></video>
          <video
            #standbyVideo
            preload="auto"
            playsinline
            class="absolute inset-0 h-full w-full bg-black object-contain transition-opacity duration-150"
            [class.opacity-100]="activeSlotIndex() === 1"
            [class.opacity-0]="activeSlotIndex() !== 1"
            [class.pointer-events-auto]="activeSlotIndex() === 1"
            [class.pointer-events-none]="activeSlotIndex() !== 1"
            (loadedmetadata)="onSlotLoadedMetadata(1)"
            (canplay)="onSlotCanPlay(1)"
            (timeupdate)="onSlotTimeUpdate(1)"
            (play)="onSlotPlay(1)"
            (pause)="onSlotPause(1)"
            (error)="onSlotError(1)"
            (click)="togglePlay()"
          ></video>

          @if (isWaiting()) {
            <div class="pointer-events-none absolute inset-0 flex items-center justify-center">
              <div class="rounded-md bg-black/70 px-3 py-1.5 text-xs font-medium text-white">
                Loading segment...
              </div>
            </div>
          }

          @if (playbackError()) {
            <div class="absolute inset-x-4 top-4 rounded-lg border border-red-400/40 bg-red-950/80 px-3 py-2 text-sm text-red-100">
              {{ playbackError() }}
            </div>
          }

          <div
            class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/85 to-transparent px-4 pb-3 pt-20 opacity-0 transition-opacity duration-200 group-hover:opacity-100"
          >
            <app-multi-segment-progress-bar
              [sequence]="sequence()"
              [currentVirtualTime]="currentVirtualTime()"
              (seekRequested)="seekToVirtualTime($event)"
            />

            <div class="mt-2 flex items-center gap-3 text-sm text-white">
              <button
                (click)="togglePlay(); $event.stopPropagation()"
                class="transition-colors hover:text-primary"
                aria-label="Play or pause sequence"
              >
                @if (isPlaying()) {
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="20"
                    height="20"
                    viewBox="0 0 24 24"
                    fill="currentColor"
                  >
                    <rect x="6" y="4" width="4" height="16" />
                    <rect x="14" y="4" width="4" height="16" />
                  </svg>
                } @else {
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="20"
                    height="20"
                    viewBox="0 0 24 24"
                    fill="currentColor"
                  >
                    <polygon points="5,3 19,12 5,21" />
                  </svg>
                }
              </button>

              <span class="select-none tabular-nums text-xs">
                {{ currentVirtualTime() | duration }} / {{ sequence().duration | duration }}
              </span>

              <span class="min-w-0 flex-1 truncate text-xs text-white/70">
                {{ currentSegmentLabel() }}
              </span>

              <span class="select-none text-xs tabular-nums text-white/70">
                {{ currentSegmentIndex() + 1 }}/{{ sequence().segments.length }}
              </span>

              <button
                (click)="toggleMute(); $event.stopPropagation()"
                class="transition-colors hover:text-primary"
                aria-label="Toggle mute"
              >
                @if (isMuted()) {
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="18"
                    height="18"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" />
                    <line x1="23" y1="9" x2="17" y2="15" />
                    <line x1="17" y1="9" x2="23" y2="15" />
                  </svg>
                } @else {
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="18"
                    height="18"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" />
                    <path d="M19.07 4.93a10 10 0 0 1 0 14.14" />
                    <path d="M15.54 8.46a5 5 0 0 1 0 7.07" />
                  </svg>
                }
              </button>

              <button
                (click)="toggleFullscreen(); $event.stopPropagation()"
                class="transition-colors hover:text-primary"
                aria-label="Toggle fullscreen"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  width="18"
                  height="18"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                >
                  <polyline points="15 3 21 3 21 9" />
                  <polyline points="9 21 3 21 3 15" />
                  <line x1="21" y1="3" x2="14" y2="10" />
                  <line x1="3" y1="21" x2="10" y2="14" />
                </svg>
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  `,
})
export class MultiSegmentPlayerDialogComponent implements AfterViewInit, OnDestroy {
  sequence = input.required<ClipSequence>();
  closed = output<void>();

  @ViewChild('primaryVideo') primaryVideoRef!: ElementRef<HTMLVideoElement>;
  @ViewChild('standbyVideo') standbyVideoRef!: ElementRef<HTMLVideoElement>;
  @ViewChild('videoContainer') videoContainerRef!: ElementRef<HTMLDivElement>;

  currentVirtualTime = signal(0);
  currentSegmentIndex = signal(0);
  activeSlotIndex = signal<0 | 1>(0);
  isPlaying = signal(false);
  isMuted = signal(false);
  isWaiting = signal(false);
  playbackError = signal('');
  slots = signal<VideoSlotState[]>([
    { segmentIndex: null, ready: false, source: '', pendingSeekTime: null },
    { segmentIndex: null, ready: false, source: '', pendingSeekTime: null },
  ]);

  currentSegmentLabel = computed(() => {
    const segment = this.sequence().segments[this.currentSegmentIndex()];
    return segment ? segment.label || segment.video.filename : 'No segment';
  });

  private readonly videoService = inject(VideoService);
  private shouldPlayWhenReady = true;
  private isSwitchingSegment = false;

  ngAfterViewInit(): void {
    if (this.sequence().segments.length === 0) {
      this.playbackError.set('No playable selections');
      return;
    }

    this.loadSegmentIntoSlot(0, 0, this.sequence().segments[0].startTime);
    this.preloadNextSegment(0);
  }

  ngOnDestroy(): void {
    this.pauseAllSlots();
    this.clearSlotElement(0);
    this.clearSlotElement(1);
  }

  togglePlay(): void {
    if (this.currentVirtualTime() >= this.sequence().duration && this.sequence().duration > 0) {
      this.seekToVirtualTime(0);
      this.shouldPlayWhenReady = true;
      return;
    }

    const activeVideo = this.getActiveVideo();
    if (!activeVideo) return;

    if (activeVideo.paused) {
      this.playActiveSlot();
    } else {
      activeVideo.pause();
      this.isPlaying.set(false);
      this.shouldPlayWhenReady = false;
    }
  }

  toggleMute(): void {
    const nextMuted = !this.isMuted();
    this.isMuted.set(nextMuted);
    for (const video of this.getVideoElements()) {
      video.muted = nextMuted;
    }
  }

  toggleFullscreen(): void {
    const container = this.videoContainerRef?.nativeElement;
    if (!container) return;

    if (document.fullscreenElement) {
      document.exitFullscreen();
    } else {
      container.requestFullscreen();
    }
  }

  seekToVirtualTime(virtualTime: number): void {
    const position = mapVirtualTimeToSegment(this.sequence(), virtualTime);
    if (!position) return;

    const wasPlaying = this.isPlaying();
    const activeSlot = this.activeSlotIndex();
    const activeVideo = this.getVideoForSlot(activeSlot);
    const activeState = this.slots()[activeSlot];

    this.playbackError.set('');
    this.currentVirtualTime.set(position.virtualTime);
    this.currentSegmentIndex.set(position.segmentIndex);
    this.shouldPlayWhenReady = wasPlaying;

    if (activeVideo && activeState.segmentIndex === position.segmentIndex) {
      activeVideo.currentTime = position.sourceTime;
      if (wasPlaying) {
        this.playActiveSlot();
      }
      this.preloadNextSegment(position.segmentIndex);
      return;
    }

    this.loadSegmentIntoSlot(activeSlot, position.segmentIndex, position.sourceTime);
    this.preloadNextSegment(position.segmentIndex);
  }

  onSlotLoadedMetadata(slotIndex: 0 | 1): void {
    const video = this.getVideoForSlot(slotIndex);
    const slot = this.slots()[slotIndex];
    if (!video || slot.pendingSeekTime === null) return;

    try {
      video.currentTime = slot.pendingSeekTime;
      this.updateSlot(slotIndex, { pendingSeekTime: null });
    } catch {
      this.playbackError.set('Could not seek to segment start');
    }
  }

  onSlotCanPlay(slotIndex: 0 | 1): void {
    this.updateSlot(slotIndex, { ready: true });

    if (slotIndex === this.activeSlotIndex()) {
      this.isWaiting.set(false);
      if (this.shouldPlayWhenReady) {
        this.playActiveSlot();
      }
    }
  }

  onSlotTimeUpdate(slotIndex: 0 | 1): void {
    if (slotIndex !== this.activeSlotIndex() || this.isSwitchingSegment) return;

    const video = this.getVideoForSlot(slotIndex);
    const slot = this.slots()[slotIndex];
    if (!video || slot.segmentIndex === null) return;

    const segment = this.sequence().segments[slot.segmentIndex];
    if (!segment) return;

    const endThreshold = segment.endTime - Math.min(0.04, segment.duration / 2);
    if (video.currentTime >= endThreshold) {
      this.switchToSegment(slot.segmentIndex + 1);
      return;
    }

    const nextVirtualTime = segment.virtualStart + (video.currentTime - segment.startTime);
    this.currentVirtualTime.set(Math.max(segment.virtualStart, nextVirtualTime));
    this.currentSegmentIndex.set(slot.segmentIndex);
  }

  onSlotPlay(slotIndex: 0 | 1): void {
    if (slotIndex === this.activeSlotIndex()) {
      this.isPlaying.set(true);
    } else {
      this.getVideoForSlot(slotIndex)?.pause();
    }
  }

  onSlotPause(slotIndex: 0 | 1): void {
    if (slotIndex === this.activeSlotIndex() && !this.isSwitchingSegment) {
      this.isPlaying.set(false);
    }
  }

  onSlotError(slotIndex: 0 | 1): void {
    if (slotIndex === this.activeSlotIndex()) {
      this.playbackError.set('Could not load this segment');
      this.isWaiting.set(false);
      this.isPlaying.set(false);
    }
    this.updateSlot(slotIndex, { ready: false });
  }

  onKeySpace(event: Event): void {
    event.preventDefault();
    this.togglePlay();
  }

  onKeyArrowLeft(event: Event): void {
    event.preventDefault();
    this.seekBy(-5);
  }

  onKeyArrowRight(event: Event): void {
    event.preventDefault();
    this.seekBy(5);
  }

  onBackdropClick(event: MouseEvent): void {
    if (event.target === event.currentTarget) {
      this.closed.emit();
    }
  }

  private switchToSegment(nextSegmentIndex: number): void {
    const nextSegment = this.sequence().segments[nextSegmentIndex];
    if (!nextSegment) {
      this.finishSequence();
      return;
    }

    const wasPlaying = this.isPlaying();
    const nextSlot = this.inactiveSlotIndex();

    this.isSwitchingSegment = true;
    this.getActiveVideo()?.pause();
    this.activeSlotIndex.set(nextSlot);
    this.currentSegmentIndex.set(nextSegmentIndex);
    this.currentVirtualTime.set(nextSegment.virtualStart);
    this.isWaiting.set(!this.slots()[nextSlot].ready);
    this.shouldPlayWhenReady = wasPlaying;

    if (this.slots()[nextSlot].segmentIndex !== nextSegmentIndex) {
      this.loadSegmentIntoSlot(nextSlot, nextSegmentIndex, nextSegment.startTime);
    } else if (wasPlaying) {
      this.playActiveSlot();
    }

    this.preloadNextSegment(nextSegmentIndex);
    this.isSwitchingSegment = false;
  }

  private finishSequence(): void {
    this.pauseAllSlots();
    this.currentVirtualTime.set(this.sequence().duration);
    this.isPlaying.set(false);
    this.shouldPlayWhenReady = false;
  }

  private seekBy(deltaSeconds: number): void {
    const duration = this.sequence().duration;
    const nextTime = Math.min(Math.max(this.currentVirtualTime() + deltaSeconds, 0), duration);
    this.seekToVirtualTime(nextTime);
  }

  private loadSegmentIntoSlot(slotIndex: 0 | 1, segmentIndex: number, seekTime: number): void {
    const segment = this.sequence().segments[segmentIndex];
    const video = this.getVideoForSlot(slotIndex);
    if (!segment || !video) return;

    const source = this.videoService.streamUrl(segment.videoFileId);
    this.updateSlot(slotIndex, {
      segmentIndex,
      ready: false,
      source,
      pendingSeekTime: seekTime,
    });

    if (slotIndex === this.activeSlotIndex()) {
      this.isWaiting.set(true);
    }
    video.pause();
    video.muted = this.isMuted();
    video.src = source;
    video.load();
  }

  private preloadNextSegment(currentSegmentIndex: number): void {
    const nextSegmentIndex = currentSegmentIndex + 1;
    const nextSegment = this.sequence().segments[nextSegmentIndex];
    const standbySlot = this.inactiveSlotIndex();

    if (!nextSegment) {
      this.clearSlot(standbySlot);
      return;
    }

    if (this.slots()[standbySlot].segmentIndex === nextSegmentIndex) return;
    this.loadSegmentIntoSlot(standbySlot, nextSegmentIndex, nextSegment.startTime);
  }

  private playActiveSlot(): void {
    const activeVideo = this.getActiveVideo();
    if (!activeVideo) return;

    this.pauseInactiveSlot();
    this.shouldPlayWhenReady = true;
    activeVideo
      .play()
      .then(() => {
        this.isPlaying.set(true);
        this.playbackError.set('');
      })
      .catch(() => {
        this.isPlaying.set(false);
        this.shouldPlayWhenReady = false;
      });
  }

  private pauseInactiveSlot(): void {
    this.getVideoForSlot(this.inactiveSlotIndex())?.pause();
  }

  private pauseAllSlots(): void {
    for (const video of this.getVideoElements()) {
      video.pause();
    }
  }

  private clearSlot(slotIndex: 0 | 1): void {
    this.updateSlot(slotIndex, {
      segmentIndex: null,
      ready: false,
      source: '',
      pendingSeekTime: null,
    });
    this.clearSlotElement(slotIndex);
  }

  private clearSlotElement(slotIndex: 0 | 1): void {
    const video = this.getVideoForSlot(slotIndex);
    if (!video) return;
    video.pause();
    video.removeAttribute('src');
    video.load();
  }

  private updateSlot(slotIndex: 0 | 1, patch: Partial<VideoSlotState>): void {
    this.slots.update((slots) =>
      slots.map((slot, index) => (index === slotIndex ? { ...slot, ...patch } : slot)),
    );
  }

  private inactiveSlotIndex(): 0 | 1 {
    return this.activeSlotIndex() === 0 ? 1 : 0;
  }

  private getActiveVideo(): HTMLVideoElement | null {
    return this.getVideoForSlot(this.activeSlotIndex());
  }

  private getVideoForSlot(slotIndex: 0 | 1): HTMLVideoElement | null {
    if (slotIndex === 0) return this.primaryVideoRef?.nativeElement ?? null;
    return this.standbyVideoRef?.nativeElement ?? null;
  }

  private getVideoElements(): HTMLVideoElement[] {
    return [this.primaryVideoRef?.nativeElement, this.standbyVideoRef?.nativeElement].filter(
      (video): video is HTMLVideoElement => !!video,
    );
  }
}
