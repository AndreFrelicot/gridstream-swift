import { Component, inject, input, output, signal } from '@angular/core';
import { VideoService } from '../../core/services/video.service';

@Component({
  selector: 'app-annotation-frame-bar',
  template: `
    <div class="border-t border-border px-5 py-3">
      <!-- Header row -->
      <div class="flex items-center gap-3">
        <!-- Frame stepper -->
        <div class="flex items-center gap-2">
          <button
            (click)="stepBackward()"
            class="flex items-center justify-center w-6 h-6 rounded-full bg-white/10 text-muted-foreground hover:text-foreground hover:bg-white/20 transition-colors"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="12"
              height="12"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2.5"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <polyline points="15 18 9 12 15 6" />
            </svg>
          </button>
          <span class="text-xs tabular-nums text-muted-foreground select-none">
            Frame {{ formatTimeWithFrames(currentTime()) }}
          </span>
          <button
            (click)="stepForward()"
            class="flex items-center justify-center w-6 h-6 rounded-full bg-white/10 text-muted-foreground hover:text-foreground hover:bg-white/20 transition-colors"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="12"
              height="12"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2.5"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <polyline points="9 18 15 12 9 6" />
            </svg>
          </button>
        </div>

        <div class="flex-1"></div>

        <!-- Frames toggle with count -->
        <button
          (click)="isExpanded.set(!isExpanded())"
          class="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors"
        >
          <span>Frames</span>
          @if (!isExpanded()) {
            <span
              class="rounded-full bg-primary px-1.5 py-0.5 text-[10px] font-bold leading-none text-white"
            >
              {{ annotationTimes().length }}
            </span>
          }
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="12"
            height="12"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
            [class.rotate-90]="isExpanded()"
            class="transition-transform"
          >
            <polyline points="9 18 15 12 9 6" />
          </svg>
        </button>
      </div>

      <!-- Expandable frame list -->
      @if (isExpanded()) {
        <div class="mt-3 overflow-x-auto">
          <div class="flex gap-2.5">
            @for (time of annotationTimes(); track time) {
              <button
                (click)="seekToFrame.emit(time)"
                class="flex flex-col items-center gap-1 rounded-lg p-1.5 transition-colors flex-shrink-0"
                [class.bg-accent]="isActiveFrame(time)"
              >
                <div
                  class="w-20 h-[50px] rounded-md overflow-hidden border-2"
                  [class.border-primary]="isActiveFrame(time)"
                  [class.border-transparent]="!isActiveFrame(time)"
                >
                  <img
                    [src]="getFrameUrl(time)"
                    alt="Frame at {{ formatTimeWithFrames(time) }}"
                    class="w-full h-full object-cover"
                    loading="lazy"
                  />
                </div>
                <span
                  class="text-[10px] tabular-nums"
                  [class.text-foreground]="isActiveFrame(time)"
                  [class.text-muted-foreground]="!isActiveFrame(time)"
                >
                  {{ formatTimeWithFrames(time) }}
                </span>
              </button>
            }
          </div>
        </div>
      }
    </div>
  `,
})
export class AnnotationFrameBarComponent {
  private readonly videoService = inject(VideoService);

  annotationTimes = input.required<number[]>();
  currentTime = input.required<number>();
  frameRate = input.required<number>();
  videoFileId = input.required<string>();
  duration = input.required<number>();

  seekToFrame = output<number>();

  isExpanded = signal(true);

  stepBackward(): void {
    const fr = this.frameRate();
    if (fr <= 0) return;
    const time = Math.max(0, this.currentTime() - 1.0 / fr);
    this.seekToFrame.emit(time);
  }

  stepForward(): void {
    const fr = this.frameRate();
    if (fr <= 0) return;
    const time = Math.min(this.duration(), this.currentTime() + 1.0 / fr);
    this.seekToFrame.emit(time);
  }

  isActiveFrame(frameTime: number): boolean {
    const fr = this.frameRate();
    if (fr <= 0) return false;
    const frameDuration = 1.0 / fr;
    return Math.abs(this.currentTime() - frameTime) < frameDuration * 0.5;
  }

  getFrameUrl(time: number): string {
    return this.videoService.scrubFrameUrl(this.videoFileId(), time);
  }

  formatTimeWithFrames(timeInSeconds: number): string {
    if (!isFinite(timeInSeconds) || timeInSeconds < 0) return '0:00:00';
    const totalSeconds = Math.floor(timeInSeconds);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    const frame = Math.floor((timeInSeconds - totalSeconds) * this.frameRate());
    return `${minutes}:${seconds.toString().padStart(2, '0')}:${frame.toString().padStart(2, '0')}`;
  }
}
