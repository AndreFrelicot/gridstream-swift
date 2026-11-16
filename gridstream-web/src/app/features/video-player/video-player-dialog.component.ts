import {
  Component,
  computed,
  input,
  output,
  inject,
  signal,
  OnInit,
  OnDestroy,
  ViewChild,
  ElementRef,
} from '@angular/core';
import { DurationPipe, FileSizePipe } from '../../shared/pipes/format';
import { VideoItem } from '../../core/models/video.model';
import { RatingService } from '../../core/services/rating.service';
import { VideoService } from '../../core/services/video.service';
import { AnnotationService } from '../../core/services/annotation.service';
import { AnnotationOverlayComponent } from './annotation-overlay.component';
import { AnnotationFrameBarComponent } from './annotation-frame-bar.component';
import { AnnotationEditor } from './annotation-editor';
import { FrameCaptureService } from '../../core/services/frame-capture.service';

@Component({
  selector: 'app-video-player-dialog',
  imports: [DurationPipe, FileSizePipe, AnnotationOverlayComponent, AnnotationFrameBarComponent],
  template: `
    <div
      role="dialog"
      aria-modal="true"
      tabindex="0"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/85 backdrop-blur-sm"
      (click)="onBackdropClick($event)"
      (keydown.escape)="onKeyEscape($event)"
      (keydown.space)="onKeySpace($event)"
      (keydown.arrowleft)="onKeyArrowLeft($event)"
      (keydown.arrowright)="onKeyArrowRight($event)"
    >
      <div
        class="relative mx-4 flex w-full max-w-5xl flex-col overflow-hidden rounded-2xl border border-border bg-card shadow-2xl"
      >
        <!-- Header -->
        <div class="flex items-center justify-between border-b border-border px-5 py-3">
          <h2 class="truncate text-sm font-semibold text-card-foreground">
            {{ video().filename }}
          </h2>
          <button
            (click)="closed.emit()"
            class="rounded-full p-1.5 text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
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

        <!-- Video -->
        <div #videoContainer class="relative bg-black group">
          <video
            #videoElement
            [src]="streamUrl()"
            autoplay
            class="aspect-video w-full"
            (play)="onVideoPlay()"
            (pause)="onVideoPause()"
            (timeupdate)="onTimeUpdate()"
            (loadedmetadata)="onMetadataLoaded()"
            (progress)="onBufferProgress()"
            (click)="togglePlay()"
          ></video>

          <!-- Annotation Overlay -->
          @if (
            annotationEditor.annotationMode() && annotationEditor.currentFrameStrokes().length > 0
          ) {
            <app-annotation-overlay
              [strokes]="annotationEditor.currentFrameStrokes()"
              [videoAspect]="videoAspect()"
            />
          }

          @if (annotationEditor.annotationMode() && annotationEditor.hasCurrentFrameText()) {
            <div class="pointer-events-none absolute inset-x-0 bottom-5 flex justify-center px-4">
              <div
                class="max-w-xl whitespace-pre-wrap rounded-xl border border-white/15 bg-black/70 px-4 py-2 text-center text-sm font-medium text-white shadow-xl backdrop-blur-sm"
              >
                {{ annotationEditor.currentFrameText() }}
              </div>
            </div>
          }

          @if (annotationEditor.textEditorOpen()) {
            <div class="pointer-events-none absolute inset-x-0 top-4 flex justify-center px-4">
              <div
                class="pointer-events-auto w-full max-w-xl rounded-xl border border-white/15 bg-black/80 p-4 text-white shadow-xl backdrop-blur-sm"
                role="group"
                aria-label="Text annotation editor"
                tabindex="-1"
                (click)="$event.stopPropagation()"
                (keydown)="$event.stopPropagation()"
              >
                <div class="mb-3 flex items-center justify-between gap-4">
                  <div>
                    <div class="text-xs font-semibold uppercase tracking-[0.2em] text-white/60">
                      Text annotation
                    </div>
                    <div class="text-xs text-white/70">
                      Frame {{ annotationEditor.currentFrameTime() | duration }}
                    </div>
                  </div>
                  @if (annotationEditor.textSaveError()) {
                    <div class="text-xs text-red-300">{{ annotationEditor.textSaveError() }}</div>
                  }
                </div>

                <textarea
                  class="min-h-24 w-full resize-y rounded-lg border border-white/15 bg-white/8 px-3 py-2 text-sm text-white outline-none transition focus:border-primary"
                  placeholder="Add a text annotation for the current frame"
                  aria-label="Text annotation for the current frame"
                  [value]="annotationEditor.textEditorDraft()"
                  (input)="annotationEditor.onTextDraftInput($any($event.target).value)"
                  (focus)="annotationEditor.isTextFocused = true"
                  (blur)="annotationEditor.isTextFocused = false"
                  (keydown.escape)="$any($event.target).blur()"
                ></textarea>

                <div class="mt-3 flex items-center justify-between gap-3">
                  <div class="text-xs text-white/60">
                    Saved frame text updates independently from drawing strokes.
                  </div>
                  <div class="flex items-center gap-2">
                    <button
                      (click)="annotationEditor.clearTextAnnotation(); $event.stopPropagation()"
                      class="rounded-full border border-white/15 px-3 py-1.5 text-xs font-medium text-white/80 transition hover:border-white/30 hover:text-white disabled:cursor-not-allowed disabled:opacity-50"
                      [disabled]="
                        annotationEditor.isSavingText() || !annotationEditor.canClearText()
                      "
                    >
                      Clear
                    </button>
                    <button
                      (click)="annotationEditor.saveTextAnnotation(); $event.stopPropagation()"
                      class="rounded-full bg-primary px-3 py-1.5 text-xs font-semibold text-white transition hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-50"
                      [disabled]="!annotationEditor.canSaveText()"
                    >
                      {{ annotationEditor.isSavingText() ? 'Saving...' : 'Save text' }}
                    </button>
                  </div>
                </div>
              </div>
            </div>
          }

          <!-- Custom Controls Overlay -->
          <div
            class="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/80 to-transparent pt-8 pb-2 px-4 opacity-0 group-hover:opacity-100 transition-opacity duration-200"
          >
            <!-- Scrub Preview Tooltip -->
            @if (scrubPreviewUrl() && scrubPreviewTime() !== null) {
              <div
                class="absolute bottom-14 -translate-x-1/2 pointer-events-none"
                [style.left.px]="scrubPreviewX()"
              >
                <div class="flex flex-col items-center">
                  <img
                    [src]="scrubPreviewUrl()"
                    alt="Video frame preview"
                    class="w-40 h-auto rounded-md border border-white/20 shadow-lg"
                  />
                  <div
                    class="text-center text-xs text-white mt-1 bg-black/70 px-1.5 py-0.5 rounded-md"
                  >
                    {{ scrubPreviewTime()! | duration }}
                  </div>
                </div>
              </div>
            }

            <!-- Progress Bar -->
            <div
              #progressBar
              class="relative h-1 bg-white/20 rounded-full cursor-pointer mb-2 hover:h-1.5 transition-all"
              (mousedown)="onProgressMouseDown($event)"
              (mousemove)="onProgressHover($event)"
              (mouseleave)="onProgressLeave()"
            >
              <div
                class="absolute h-full bg-white/30 rounded-full pointer-events-none"
                [style.width.%]="bufferedPercent()"
              ></div>
              <div
                class="absolute h-full bg-primary rounded-full pointer-events-none"
                [style.width.%]="playedPercent()"
              ></div>
            </div>

            <!-- Controls Row -->
            <div class="flex items-center gap-3 text-white text-sm">
              <!-- Play/Pause -->
              <button
                (click)="togglePlay(); $event.stopPropagation()"
                class="hover:text-primary transition-colors"
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

              <!-- Time Display -->
              <span class="tabular-nums text-xs select-none">
                {{ currentTime() | duration }} / {{ duration() | duration }}
              </span>

              <div class="flex-1"></div>

              <!-- Set as Thumbnail (only when paused) -->
              @if (!isPlaying()) {
                <button
                  (click)="setAsThumbnail(); $event.stopPropagation()"
                  class="hover:text-primary transition-colors"
                  title="Set current frame as thumbnail"
                >
                  @if (thumbnailButtonIcon() === 'check') {
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
                      class="text-green-400"
                    >
                      <polyline points="20 6 9 17 4 12" />
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
                      <rect x="3" y="3" width="18" height="18" rx="2" ry="2" />
                      <circle cx="8.5" cy="8.5" r="1.5" />
                      <polyline points="21 15 16 10 5 21" />
                    </svg>
                  }
                </button>

                <!-- Capture Frame -->
                <button
                  (click)="captureFrame(); $event.stopPropagation()"
                  class="hover:text-primary transition-colors"
                  title="Capture frame"
                >
                  @if (captureButtonIcon() === 'check') {
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
                      class="text-green-400"
                    >
                      <polyline points="20 6 9 17 4 12" />
                    </svg>
                  } @else if (captureButtonIcon() === 'error') {
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
                      class="text-red-400"
                    >
                      <line x1="18" y1="6" x2="6" y2="18" />
                      <line x1="6" y1="6" x2="18" y2="18" />
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
                      <path
                        d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"
                      />
                      <circle cx="12" cy="13" r="4" />
                    </svg>
                  }
                </button>
              }

              <!-- Annotations Toggle -->
              <button
                (click)="annotationEditor.toggleAnnotations(); $event.stopPropagation()"
                class="transition-colors"
                [class.text-primary]="annotationEditor.annotationMode()"
                [class.hover:text-primary]="!annotationEditor.annotationMode()"
                title="Toggle annotations"
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
                  <path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z" />
                </svg>
              </button>

              <!-- Text Annotation Editor Toggle -->
              <button
                (click)="annotationEditor.toggleTextEditor(); $event.stopPropagation()"
                class="transition-colors"
                [class.text-primary]="annotationEditor.textEditorOpen()"
                [class.hover:text-primary]="!annotationEditor.textEditorOpen()"
                title="Toggle text annotation editor"
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
                  <polyline points="4 7 4 4 20 4 20 7" />
                  <line x1="9" y1="20" x2="15" y2="20" />
                  <line x1="12" y1="4" x2="12" y2="20" />
                </svg>
              </button>

              <!-- Volume -->
              <button
                (click)="toggleMute(); $event.stopPropagation()"
                class="hover:text-primary transition-colors"
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

              <!-- Fullscreen -->
              <button
                (click)="toggleFullscreen(); $event.stopPropagation()"
                class="hover:text-primary transition-colors"
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

        <!-- Annotation Frame Bar -->
        @if (annotationEditor.annotationMode() && annotationEditor.annotationTimes().length > 0) {
          <app-annotation-frame-bar
            [annotationTimes]="annotationEditor.annotationTimes()"
            [currentTime]="currentTime()"
            [frameRate]="annotationEditor.frameRate()"
            [videoFileId]="video().fileId"
            [duration]="duration()"
            (seekToFrame)="onSeekToFrame($event)"
          />
        }

        <!-- Rating -->
        <div class="border-t border-border px-5 py-3">
          <div class="flex items-center gap-2">
            <span class="text-xs font-medium text-muted-foreground">Rate:</span>
            <div class="flex items-center gap-0.5">
              @for (r of [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]; track r) {
                <button
                  (click)="setRating(r)"
                  (mouseenter)="hoveredRating.set(r)"
                  (mouseleave)="hoveredRating.set(null)"
                  class="p-0.5 transition-transform hover:scale-110"
                  [attr.aria-label]="'Rate ' + r + ' out of 10'"
                  [title]="r + '/10'"
                >
                  <svg
                    class="w-5 h-5"
                    viewBox="0 0 24 24"
                    [attr.fill]="isHeartFilled(r) ? '#EF4444' : 'none'"
                    [attr.stroke]="isHeartFilled(r) ? '#EF4444' : '#F97316'"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    [style.opacity]="isHeartFilled(r) ? 1 : 0.5"
                  >
                    <path
                      d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"
                    />
                  </svg>
                </button>
              }
            </div>
            @if (hoveredRating() !== null) {
              <span class="text-xs text-muted-foreground">{{ hoveredRating() }}/10</span>
            }
          </div>
        </div>

        <!-- Footer -->
        <div
          class="flex items-center gap-3 border-t border-border px-5 py-2.5 text-xs text-muted-foreground"
        >
          <span class="font-medium">{{ video().width }}x{{ video().height }}</span>
          <span class="h-3 w-px bg-border"></span>
          <span>{{ video().codec.toUpperCase() }}</span>
          <span class="h-3 w-px bg-border"></span>
          <span>{{ video().fileSize | fileSize }}</span>
          @if (currentRating() > 0) {
            <span class="h-3 w-px bg-border"></span>
            <span>{{ currentRating() }}/10</span>
          }
        </div>
      </div>
    </div>
  `,
})
export class VideoPlayerDialogComponent implements OnInit, OnDestroy {
  video = input.required<VideoItem>();
  startTime = input(0);
  closed = output<void>();
  thumbnailUpdated = output<string>();
  ratingChanged = output<{ fileId: string; rating: number }>();

  @ViewChild('videoElement') videoRef!: ElementRef<HTMLVideoElement>;
  @ViewChild('progressBar') progressBarRef!: ElementRef<HTMLDivElement>;
  @ViewChild('videoContainer') videoContainerRef!: ElementRef<HTMLDivElement>;

  private readonly ratingService = inject(RatingService);
  private readonly videoService = inject(VideoService);
  private readonly annotationService = inject(AnnotationService);
  private readonly frameCaptureService = inject(FrameCaptureService);

  streamUrl = computed(() => this.videoService.streamUrl(this.video().fileId));

  /** Intrinsic aspect ratio of the video, used to place annotations on the letterboxed picture. */
  videoAspect = signal(16 / 9);

  // Rating state
  currentRating = signal<number>(0);
  hoveredRating = signal<number | null>(null);

  // Player state signals
  currentTime = signal(0);
  duration = signal(0);
  isPlaying = signal(false);
  isMuted = signal(false);
  bufferedPercent = signal(0);
  playedPercent = signal(0);
  readonly annotationEditor = new AnnotationEditor(
    this.annotationService,
    () => this.video().fileId,
    this.currentTime,
  );

  // Thumbnail button state
  thumbnailButtonIcon = signal<'default' | 'check'>('default');

  // Capture button state
  captureButtonIcon = signal<'default' | 'check' | 'error'>('default');

  // Scrub preview signals
  scrubPreviewUrl = signal<string | null>(null);
  scrubPreviewTime = signal<number | null>(null);
  scrubPreviewX = signal(0);

  // Scrub preview internals
  private scrubDebounceTimer: ReturnType<typeof setTimeout> | null = null;
  private readonly iconResetTimers = new Set<ReturnType<typeof setTimeout>>();
  private isDragging = false;
  private boundOnMouseMove = this.onDocumentMouseMove.bind(this);
  private boundOnMouseUp = this.onDocumentMouseUp.bind(this);

  ngOnInit(): void {
    this.currentRating.set(this.video().rating || 0);
    const { width, height } = this.video();
    if (width > 0 && height > 0) this.videoAspect.set(width / height);
    this.annotationEditor.loadAnnotations();
  }

  ngOnDestroy(): void {
    this.annotationEditor.destroy();
    if (this.scrubDebounceTimer) {
      clearTimeout(this.scrubDebounceTimer);
    }
    this.iconResetTimers.forEach((timer) => clearTimeout(timer));
    document.removeEventListener('mousemove', this.boundOnMouseMove);
    document.removeEventListener('mouseup', this.boundOnMouseUp);
  }

  // --- Player controls ---

  togglePlay(): void {
    const video = this.videoRef?.nativeElement;
    if (!video) return;
    if (video.paused) {
      video.play();
    } else {
      video.pause();
    }
  }

  toggleMute(): void {
    const video = this.videoRef?.nativeElement;
    if (!video) return;
    video.muted = !video.muted;
    this.isMuted.set(video.muted);
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

  // --- Video event handlers ---

  onTimeUpdate(): void {
    const video = this.videoRef?.nativeElement;
    if (!video || this.isDragging) return;
    this.currentTime.set(video.currentTime);
    this.playedPercent.set(this.duration() > 0 ? (video.currentTime / this.duration()) * 100 : 0);
    this.annotationEditor.updateCurrentFrameAnnotationState();
  }

  onMetadataLoaded(): void {
    const video = this.videoRef?.nativeElement;
    if (!video) return;
    this.duration.set(video.duration);
    if (video.videoWidth > 0 && video.videoHeight > 0) {
      this.videoAspect.set(video.videoWidth / video.videoHeight);
    }

    // Seek to startTime if provided (e.g. opening from a capture)
    const st = this.startTime();
    if (st > 0) {
      video.currentTime = st;
      video.pause();
      this.currentTime.set(st);
      this.isPlaying.set(false);
      this.playedPercent.set(video.duration > 0 ? (st / video.duration) * 100 : 0);
      this.annotationEditor.updateCurrentFrameAnnotationState();
    }
  }

  onBufferProgress(): void {
    const video = this.videoRef?.nativeElement;
    if (!video || video.buffered.length === 0) return;
    const bufferedEnd = video.buffered.end(video.buffered.length - 1);
    this.bufferedPercent.set(this.duration() > 0 ? (bufferedEnd / this.duration()) * 100 : 0);
  }

  // --- Progress bar interaction ---

  onProgressMouseDown(event: MouseEvent): void {
    event.preventDefault();
    this.isDragging = true;
    this.seekToPosition(event);
    document.addEventListener('mousemove', this.boundOnMouseMove);
    document.addEventListener('mouseup', this.boundOnMouseUp);
  }

  private onDocumentMouseMove(event: MouseEvent): void {
    if (this.isDragging) {
      this.seekToPosition(event);
    }
  }

  private onDocumentMouseUp(): void {
    this.isDragging = false;
    document.removeEventListener('mousemove', this.boundOnMouseMove);
    document.removeEventListener('mouseup', this.boundOnMouseUp);
  }

  private seekToPosition(event: MouseEvent): void {
    const bar = this.progressBarRef?.nativeElement;
    const video = this.videoRef?.nativeElement;
    if (!bar || !video) return;

    const rect = bar.getBoundingClientRect();
    const x = Math.max(0, Math.min(event.clientX - rect.left, rect.width));
    const percent = x / rect.width;
    const time = percent * this.duration();

    video.currentTime = time;
    this.currentTime.set(time);
    this.playedPercent.set(percent * 100);
    this.annotationEditor.updateCurrentFrameAnnotationState();
  }

  // --- Scrub preview on hover ---

  onProgressHover(event: MouseEvent): void {
    if (this.isDragging) return;
    const bar = this.progressBarRef?.nativeElement;
    if (!bar || this.duration() === 0) return;

    const rect = bar.getBoundingClientRect();
    const x = Math.max(0, Math.min(event.clientX - rect.left, rect.width));
    const percent = x / rect.width;
    const time = Math.floor(percent * this.duration());

    // Clamp preview X to keep thumbnail within bar bounds
    const thumbHalfWidth = 80; // half of w-40 (160px)
    const clampedX = Math.max(thumbHalfWidth, Math.min(x, rect.width - thumbHalfWidth));
    this.scrubPreviewX.set(clampedX);
    this.scrubPreviewTime.set(time);

    // Debounce the frame request
    if (this.scrubDebounceTimer) {
      clearTimeout(this.scrubDebounceTimer);
    }
    this.scrubDebounceTimer = setTimeout(() => {
      this.loadScrubFrame(time);
    }, 50);
  }

  onProgressLeave(): void {
    if (this.isDragging) return;
    this.scrubPreviewUrl.set(null);
    this.scrubPreviewTime.set(null);
    if (this.scrubDebounceTimer) {
      clearTimeout(this.scrubDebounceTimer);
      this.scrubDebounceTimer = null;
    }
  }

  private loadScrubFrame(time: number): void {
    const url = this.videoService.scrubFrameUrl(this.video().fileId, time);
    this.scrubPreviewUrl.set(url);
  }

  // --- Keyboard shortcuts ---

  onKeyEscape(event: Event): void {
    if (isEditableTarget(event)) return;
    this.closed.emit();
  }

  onKeySpace(event: Event): void {
    if (isEditableTarget(event)) return;
    event.preventDefault();
    this.togglePlay();
  }

  onKeyArrowLeft(event: Event): void {
    if (isEditableTarget(event)) return;
    event.preventDefault();
    const video = this.videoRef?.nativeElement;
    if (!video) return;
    video.currentTime = Math.max(0, video.currentTime - 5);
  }

  onKeyArrowRight(event: Event): void {
    if (isEditableTarget(event)) return;
    event.preventDefault();
    const video = this.videoRef?.nativeElement;
    if (!video) return;
    video.currentTime = Math.min(this.duration(), video.currentTime + 5);
  }

  // --- Time formatting ---

  // --- Rating ---

  setRating(rating: number): void {
    const finalRating = this.currentRating() === rating ? 0 : rating;
    this.currentRating.set(finalRating);
    this.ratingService.setRating(this.video().fileId, finalRating).subscribe({
      next: () => this.ratingChanged.emit({ fileId: this.video().fileId, rating: finalRating }),
    });
  }

  isHeartFilled(index: number): boolean {
    const effective = this.hoveredRating() ?? this.currentRating();
    return index <= effective;
  }

  // --- Set as Thumbnail ---

  /** Restores a confirmation icon after 2 s; cancelled if the dialog closes first. */
  private resetIconLater(reset: () => void): void {
    const timer = setTimeout(() => {
      this.iconResetTimers.delete(timer);
      reset();
    }, 2000);
    this.iconResetTimers.add(timer);
  }

  setAsThumbnail(): void {
    if (this.thumbnailButtonIcon() === 'check') return;
    this.videoService.setThumbnail(this.video().fileId, this.currentTime()).subscribe({
      next: () => {
        this.thumbnailButtonIcon.set('check');
        this.thumbnailUpdated.emit(this.video().fileId);
        this.resetIconLater(() => this.thumbnailButtonIcon.set('default'));
      },
      error: (err) => console.error('Failed to set thumbnail:', err),
    });
  }

  captureFrame(): void {
    if (this.captureButtonIcon() !== 'default') return;
    this.frameCaptureService.createCapture(this.video().fileId, this.currentTime()).subscribe({
      next: () => {
        this.captureButtonIcon.set('check');
        this.resetIconLater(() => this.captureButtonIcon.set('default'));
      },
      error: (err) => {
        console.error('Failed to capture frame:', err);
        this.captureButtonIcon.set('error');
        this.resetIconLater(() => this.captureButtonIcon.set('default'));
      },
    });
  }

  // --- Annotation helpers ---

  onSeekToFrame(time: number): void {
    const video = this.videoRef?.nativeElement;
    if (!video) return;
    video.pause();
    video.currentTime = time;
    this.currentTime.set(time);
    this.playedPercent.set(this.duration() > 0 ? (time / this.duration()) * 100 : 0);
    this.annotationEditor.updateCurrentFrameAnnotationState();
  }

  // --- Playback tracking ---

  onVideoPlay(): void {
    this.isPlaying.set(true);
  }

  onVideoPause(): void {
    this.isPlaying.set(false);
  }

  onBackdropClick(event: MouseEvent): void {
    if (event.target === event.currentTarget) {
      this.closed.emit();
    }
  }
}

/** Keyboard shortcuts must not hijack typing in form fields. */
function isEditableTarget(event: Event): boolean {
  const target = event.target as HTMLElement | null;
  if (!target) return false;
  return (
    target.isContentEditable ||
    target instanceof HTMLInputElement ||
    target instanceof HTMLTextAreaElement ||
    target instanceof HTMLSelectElement
  );
}
