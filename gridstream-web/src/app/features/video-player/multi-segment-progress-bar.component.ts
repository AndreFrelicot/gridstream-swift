import {
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
import { DurationPipe, formatDuration } from '../../shared/pipes/format';
import { VideoService } from '../../core/services/video.service';
import { ClipSequence, ClipSequenceSegment } from '../../core/models/clip-sequence.model';
import { mapVirtualTimeToSegment } from '../../core/utils/clip-sequence-timeline';

@Component({
  selector: 'app-multi-segment-progress-bar',
  imports: [DurationPipe],
  template: `
    <div class="relative pb-20">
      @if (previewUrl() && previewSegment()) {
        <div
          class="pointer-events-none absolute bottom-8 z-10 -translate-x-1/2"
          [style.left.px]="previewX()"
        >
          <div class="flex flex-col items-center">
            <img
              [src]="previewUrl()"
              alt="Segment frame preview"
              class="h-auto w-40 rounded-md border border-white/20 bg-black shadow-lg"
            />
            <div class="mt-1 max-w-56 rounded-md bg-black/75 px-2 py-1 text-center text-xs text-white">
              <div class="truncate font-medium">
                {{ previewSegment()!.label || previewSegment()!.video.filename }}
              </div>
              <div class="tabular-nums text-white/70">
                {{ previewVirtualTime() | duration }} virtual -
                {{ previewSourceTime() | duration }} source
              </div>
            </div>
          </div>
        </div>
      }

      <div
        #bar
        class="relative h-3 cursor-pointer overflow-hidden rounded-full bg-white/15 transition-[height] hover:h-4"
        (mousedown)="onMouseDown($event)"
        (mousemove)="onMouseMove($event)"
        (mouseleave)="onMouseLeave()"
      >
        @for (segment of sequence().segments; track segment.id) {
          <div
            class="absolute top-0 h-full border-r border-black/35"
            [style.left.%]="segmentLeftPercent(segment)"
            [style.width.%]="segmentWidthPercent(segment)"
            [style.background-color]="segment.color"
            [title]="segmentTitle(segment)"
          ></div>
        }
        <div
          class="absolute inset-y-0 left-0 bg-white/35"
          [style.width.%]="playedPercent()"
        ></div>
        <div
          class="absolute inset-y-0 w-0.5 bg-white shadow"
          [style.left.%]="playedPercent()"
        ></div>
      </div>

      <div class="mt-1 flex items-center justify-between text-[11px] text-white/70">
        <span class="tabular-nums">{{ currentVirtualTime() | duration }}</span>
        <span class="truncate px-3 text-center">
          {{ currentSegmentLabel() }}
        </span>
        <span class="tabular-nums">{{ sequence().duration | duration }}</span>
      </div>
    </div>
  `,
})
export class MultiSegmentProgressBarComponent implements OnDestroy {
  private readonly videoService = inject(VideoService);

  sequence = input.required<ClipSequence>();
  currentVirtualTime = input.required<number>();
  seekRequested = output<number>();

  @ViewChild('bar') barRef!: ElementRef<HTMLDivElement>;

  previewUrl = signal<string | null>(null);
  previewX = signal(0);
  previewVirtualTime = signal(0);
  previewSourceTime = signal(0);
  previewSegment = signal<ClipSequenceSegment | null>(null);

  playedPercent = computed(() => {
    const duration = this.sequence().duration;
    return duration > 0 ? (this.currentVirtualTime() / duration) * 100 : 0;
  });

  currentSegmentLabel = computed(() => {
    const position = mapVirtualTimeToSegment(this.sequence(), this.currentVirtualTime());
    if (!position) return 'No segments';
    return position.segment.label || position.segment.video.filename;
  });

  private scrubDebounceTimer: ReturnType<typeof setTimeout> | null = null;
  private isDragging = false;
  private boundOnDocumentMouseMove = this.onDocumentMouseMove.bind(this);
  private boundOnDocumentMouseUp = this.onDocumentMouseUp.bind(this);

  ngOnDestroy(): void {
    this.clearPreviewTimer();
    document.removeEventListener('mousemove', this.boundOnDocumentMouseMove);
    document.removeEventListener('mouseup', this.boundOnDocumentMouseUp);
  }

  onMouseDown(event: MouseEvent): void {
    event.preventDefault();
    this.isDragging = true;
    this.seekFromMouseEvent(event);
    document.addEventListener('mousemove', this.boundOnDocumentMouseMove);
    document.addEventListener('mouseup', this.boundOnDocumentMouseUp);
  }

  onMouseMove(event: MouseEvent): void {
    this.updatePreview(event);
  }

  onMouseLeave(): void {
    if (this.isDragging) return;
    this.clearPreview();
  }

  segmentLeftPercent(segment: ClipSequenceSegment): number {
    return this.sequence().duration > 0 ? (segment.virtualStart / this.sequence().duration) * 100 : 0;
  }

  segmentWidthPercent(segment: ClipSequenceSegment): number {
    return this.sequence().duration > 0 ? (segment.duration / this.sequence().duration) * 100 : 0;
  }

  segmentTitle(segment: ClipSequenceSegment): string {
    const label = segment.label || segment.video.filename;
    return `${label} - ${formatDuration(segment.duration)}`;
  }

  private onDocumentMouseMove(event: MouseEvent): void {
    if (this.isDragging) {
      this.seekFromMouseEvent(event);
      this.updatePreview(event);
    }
  }

  private onDocumentMouseUp(): void {
    this.isDragging = false;
    document.removeEventListener('mousemove', this.boundOnDocumentMouseMove);
    document.removeEventListener('mouseup', this.boundOnDocumentMouseUp);
  }

  private seekFromMouseEvent(event: MouseEvent): void {
    const virtualTime = this.virtualTimeFromMouseEvent(event);
    if (virtualTime === null) return;
    this.seekRequested.emit(virtualTime);
  }

  private updatePreview(event: MouseEvent): void {
    const bar = this.barRef?.nativeElement;
    const virtualTime = this.virtualTimeFromMouseEvent(event);
    if (!bar || virtualTime === null) return;

    const rect = bar.getBoundingClientRect();
    const x = Math.max(0, Math.min(event.clientX - rect.left, rect.width));
    const thumbHalfWidth = Math.min(80, rect.width / 2);
    const minX = thumbHalfWidth;
    const maxX = Math.max(thumbHalfWidth, rect.width - thumbHalfWidth);
    this.previewX.set(Math.max(minX, Math.min(x, maxX)));

    const position = mapVirtualTimeToSegment(this.sequence(), virtualTime);
    if (!position) {
      this.clearPreview();
      return;
    }

    this.previewVirtualTime.set(position.virtualTime);
    this.previewSourceTime.set(position.sourceTime);
    this.previewSegment.set(position.segment);

    this.clearPreviewTimer();
    this.scrubDebounceTimer = setTimeout(() => {
      this.previewUrl.set(
        this.videoService.scrubFrameUrl(position.segment.videoFileId, position.sourceTime),
      );
    }, 50);
  }

  private virtualTimeFromMouseEvent(event: MouseEvent): number | null {
    const bar = this.barRef?.nativeElement;
    const duration = this.sequence().duration;
    if (!bar || duration <= 0) return null;

    const rect = bar.getBoundingClientRect();
    const x = Math.max(0, Math.min(event.clientX - rect.left, rect.width));
    return (x / rect.width) * duration;
  }

  private clearPreview(): void {
    this.clearPreviewTimer();
    this.previewUrl.set(null);
    this.previewSegment.set(null);
  }

  private clearPreviewTimer(): void {
    if (this.scrubDebounceTimer) {
      clearTimeout(this.scrubDebounceTimer);
      this.scrubDebounceTimer = null;
    }
  }
}
