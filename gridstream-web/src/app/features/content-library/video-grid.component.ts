import { NgTemplateOutlet } from '@angular/common';
import { Component, computed, input, output } from '@angular/core';

import { VideoItem } from '../../core/models/video.model';
import { groupByLocalDay } from './history-groups';
import { ListBadge, VideoCardComponent } from './video-card.component';

export type ListBadgeIndex = Record<string, { smart: ListBadge[]; simple: ListBadge[] }>;

const NO_BADGES: ListBadge[] = [];

/** Card grid for the library, optionally grouped by local play day (history). */
@Component({
  selector: 'app-video-grid',
  imports: [NgTemplateOutlet, VideoCardComponent],
  template: `
    @if (dayGroups(); as groups) {
      @for (group of groups; track group.date) {
        <div
          class="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2 mt-4 pb-1 border-b border-border"
        >
          {{ group.label }}
        </div>
        <div
          class="grid gap-3 grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6 mb-4"
        >
          @for (video of group.videos; track video.id) {
            <ng-container *ngTemplateOutlet="card; context: { $implicit: video }" />
          }
        </div>
      }
    } @else {
      <div
        class="grid gap-3 grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6"
      >
        @for (video of videos(); track video.id) {
          <ng-container *ngTemplateOutlet="card; context: { $implicit: video }" />
        }
      </div>
    }

    <ng-template #card let-video>
      <app-video-card
        [video]="video"
        [smartBadges]="badges()[video.fileId]?.smart ?? noBadges"
        [simpleBadges]="badges()[video.fileId]?.simple ?? noBadges"
        (open)="open.emit(video)"
        (menuRequested)="menuRequested.emit({ event: $event, video })"
      />
    </ng-template>
  `,
  styles: [
    `
      :host {
        display: contents;
      }
    `,
  ],
})
export class VideoGridComponent {
  readonly videos = input.required<VideoItem[]>();
  readonly groupByDay = input(false);
  readonly badges = input<ListBadgeIndex>({});

  readonly open = output<VideoItem>();
  readonly menuRequested = output<{ event: MouseEvent; video: VideoItem }>();

  protected readonly noBadges = NO_BADGES;
  protected readonly dayGroups = computed(() =>
    this.groupByDay() ? groupByLocalDay(this.videos()) : null,
  );
}
