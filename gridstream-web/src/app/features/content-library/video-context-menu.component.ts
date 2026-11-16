import { Component, inject, input, output, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { SimpleListDTO } from '../../core/models/simple-list.model';
import { TAG_COLORS, TagInfo } from '../../core/models/tag.model';
import { TagSummary, VideoItem } from '../../core/models/video.model';
import { RatingService } from '../../core/services/rating.service';
import { SimpleListService } from '../../core/services/simple-list.service';
import { TagService } from '../../core/services/tag.service';

export interface VideoContextMenuState {
  x: number;
  y: number;
  /** Open submenus to the left / upward so they stay inside the viewport. */
  flipX: boolean;
  flipY: boolean;
  video: VideoItem;
}

/**
 * Right-click menu of a library card: tag, add to a simple list, rate.
 * Performs the API calls itself and reports what changed to the library.
 */
@Component({
  selector: 'app-video-context-menu',
  imports: [FormsModule],
  template: `
    <div
      class="fixed inset-0 z-40"
      (click)="closed.emit()"
      (keydown.escape)="closed.emit()"
      tabindex="-1"
      role="button"
      aria-label="Close menu"
    ></div>
    <div
      class="fixed z-50 bg-popover border border-border rounded-xl shadow-2xl py-1 min-w-[160px]"
      [style.left.px]="menu().x"
      [style.top.px]="menu().y"
    >
      <!-- Tag -->
      <div class="relative" (mouseenter)="submenu.set('tag')">
        <div
          class="px-4 py-2 hover:bg-accent cursor-pointer text-sm flex items-center justify-between"
        >
          Tag
          <span class="text-muted-foreground ml-4 text-xs">&#9654;</span>
        </div>
        @if (submenu() === 'tag') {
          <div
            class="absolute bg-popover border border-border rounded-xl shadow-2xl py-1 min-w-[180px] max-h-[300px] overflow-auto"
            [class.left-full]="!menu().flipX"
            [class.right-full]="menu().flipX"
            [class.top-0]="!menu().flipY"
            [class.bottom-0]="menu().flipY"
          >
            @for (tag of tags(); track tag.id) {
              <button
                (click)="toggleVideoTag(menu().video, tag.id)"
                class="w-full px-4 py-2 hover:bg-accent cursor-pointer text-sm flex items-center gap-2 text-left"
              >
                <span
                  class="w-3 h-3 rounded-full flex-shrink-0"
                  [style.background-color]="tag.color"
                ></span>
                <span class="flex-grow">{{ tag.name }}</span>
                @if (videoHasTag(menu().video, tag.id)) {
                  <span class="text-primary font-semibold">&#10003;</span>
                }
              </button>
            }
            @if (tags().length === 0) {
              <div class="px-4 py-2 text-sm text-muted-foreground">No tags available</div>
            }
            <div class="border-t border-border my-1"></div>
            @if (!showCreateTagInput()) {
              <button
                (click)="showCreateTagInput.set(true); $event.stopPropagation()"
                class="w-full px-4 py-2 hover:bg-accent cursor-pointer text-sm text-left text-primary"
              >
                + Create Tag...
              </button>
            } @else {
              <div
                class="px-3 py-2 space-y-2"
                (click)="$event.stopPropagation()"
                (keydown)="$event.stopPropagation()"
                tabindex="-1"
                role="group"
              >
                <input
                  type="text"
                  placeholder="Tag name..."
                  [ngModel]="newTagName()"
                  (ngModelChange)="newTagName.set($event)"
                  (keydown.enter)="createTagAndApply(menu().video)"
                  class="w-full px-2 py-1 bg-background text-foreground border border-border rounded-lg text-sm focus:outline-none focus:ring-1 focus:ring-primary"
                />
                <div class="flex gap-1 flex-wrap">
                  @for (color of tagColors; track color) {
                    <button
                      (click)="newTagColor.set(color)"
                      [style.background-color]="color"
                      [class.ring-2]="newTagColor() === color"
                      [class.ring-offset-1]="newTagColor() === color"
                      class="w-5 h-5 rounded-full transition hover:opacity-80"
                      [attr.aria-label]="'Select color ' + color"
                    ></button>
                  }
                </div>
                <div class="flex gap-2">
                  <button
                    (click)="createTagAndApply(menu().video)"
                    [disabled]="!newTagName().trim()"
                    class="px-3 py-1 bg-primary text-primary-foreground rounded-full text-sm disabled:opacity-50"
                  >
                    Create
                  </button>
                  <button
                    (click)="showCreateTagInput.set(false); newTagName.set('')"
                    class="px-3 py-1 bg-secondary text-secondary-foreground rounded-full text-sm"
                  >
                    Cancel
                  </button>
                </div>
              </div>
            }
          </div>
        }
      </div>

      <!-- Add to List -->
      <div class="relative" (mouseenter)="submenu.set('list')">
        <div
          class="px-4 py-2 hover:bg-accent cursor-pointer text-sm flex items-center justify-between"
        >
          Add to List
          <span class="text-muted-foreground ml-4 text-xs">&#9654;</span>
        </div>
        @if (submenu() === 'list') {
          <div
            class="absolute bg-popover border border-border rounded-xl shadow-2xl py-1 min-w-[180px] max-h-[300px] overflow-auto"
            [class.left-full]="!menu().flipX"
            [class.right-full]="menu().flipX"
            [class.top-0]="!menu().flipY"
            [class.bottom-0]="menu().flipY"
          >
            @for (list of simpleLists(); track list.id) {
              <button
                (click)="addVideoToSimpleList(menu().video, list.id)"
                class="w-full px-4 py-2 hover:bg-accent cursor-pointer text-sm text-left"
              >
                {{ list.name }}
              </button>
            }
            @if (simpleLists().length > 0) {
              <div class="border-t border-border my-1"></div>
            }
            @if (!showNewListInput()) {
              <button
                (click)="showNewListInput.set(true); $event.stopPropagation()"
                class="w-full px-4 py-2 hover:bg-accent cursor-pointer text-sm text-left text-primary"
              >
                + New List...
              </button>
            } @else {
              <div
                class="px-3 py-2 flex gap-2"
                (click)="$event.stopPropagation()"
                (keydown)="$event.stopPropagation()"
                tabindex="-1"
                role="group"
              >
                <input
                  type="text"
                  placeholder="List name..."
                  [ngModel]="newListName()"
                  (ngModelChange)="newListName.set($event)"
                  (keydown.enter)="createListAndAddVideo(menu().video)"
                  class="px-2 py-1 bg-background text-foreground border border-border rounded-lg text-sm flex-grow focus:outline-none focus:ring-1 focus:ring-primary"
                />
                <button
                  (click)="createListAndAddVideo(menu().video)"
                  [disabled]="!newListName().trim()"
                  class="px-3 py-1 bg-primary text-primary-foreground rounded-full text-sm whitespace-nowrap disabled:opacity-50"
                >
                  Save
                </button>
              </div>
            }
          </div>
        }
      </div>

      <!-- Rate -->
      <div class="relative" (mouseenter)="submenu.set('rate')">
        <div
          class="px-4 py-2 hover:bg-accent cursor-pointer text-sm flex items-center justify-between"
        >
          Rate
          <span class="text-muted-foreground ml-4 text-xs">&#9654;</span>
        </div>
        @if (submenu() === 'rate') {
          <div
            class="absolute bg-popover border border-border rounded-xl shadow-2xl p-2"
            [class.left-full]="!menu().flipX"
            [class.right-full]="menu().flipX"
            [class.top-0]="!menu().flipY"
            [class.bottom-0]="menu().flipY"
          >
            <div class="flex items-center gap-0.5">
              @for (r of heartValues; track r) {
                <button
                  (click)="rateVideo(menu().video, r)"
                  (mouseenter)="hoveredRating.set(r)"
                  (mouseleave)="hoveredRating.set(null)"
                  class="p-0.5 transition-transform hover:scale-110"
                  [title]="r + '/10'"
                >
                  <svg
                    class="w-5 h-5"
                    viewBox="0 0 24 24"
                    [attr.fill]="isHeartFilled(r, menu().video.rating) ? '#EF4444' : 'none'"
                    [attr.stroke]="isHeartFilled(r, menu().video.rating) ? '#EF4444' : '#F97316'"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    [style.opacity]="isHeartFilled(r, menu().video.rating) ? 1 : 0.5"
                  >
                    <path
                      d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"
                    />
                  </svg>
                </button>
              }
            </div>
            @if (hoveredRating() !== null) {
              <div class="text-center text-xs text-muted-foreground mt-1">
                {{ hoveredRating() }}/10
              </div>
            }
          </div>
        }
      </div>
    </div>
  `,
})
export class VideoContextMenuComponent {
  private readonly tagService = inject(TagService);
  private readonly simpleListService = inject(SimpleListService);
  private readonly ratingService = inject(RatingService);

  readonly menu = input.required<VideoContextMenuState>();
  readonly tags = input<TagInfo[]>([]);
  readonly simpleLists = input<SimpleListDTO[]>([]);

  readonly closed = output<void>();
  /** A video's tags or rating changed on the server. */
  readonly videoPatched = output<{ videoId: string; changes: Partial<VideoItem> }>();
  readonly tagCreated = output<TagInfo>();
  /** Simple list contents changed on the server. */
  readonly listsChanged = output<void>();

  readonly submenu = signal<'tag' | 'list' | 'rate' | null>(null);
  readonly newListName = signal('');
  readonly showNewListInput = signal(false);
  readonly heartValues = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  readonly hoveredRating = signal<number | null>(null);
  readonly showCreateTagInput = signal(false);
  readonly newTagName = signal('');
  readonly newTagColor = signal('#3B82F6');
  readonly tagColors = TAG_COLORS;

  videoHasTag(video: VideoItem, tagId: string): boolean {
    return video.tags?.some((t) => t.id === tagId) ?? false;
  }

  isHeartFilled(index: number, currentRating: number): boolean {
    const effective = this.hoveredRating() ?? currentRating;
    return index <= effective;
  }

  toggleVideoTag(video: VideoItem, tagId: string) {
    const currentTagIds = video.tags?.map((t) => t.id) ?? [];
    if (currentTagIds.includes(tagId)) {
      this.detachTag(video, tagId);
    } else {
      this.attachTag(video, tagId, this.tags());
    }
  }

  createTagAndApply(video: VideoItem) {
    const name = this.newTagName().trim();
    if (!name) return;

    this.tagService.createTag({ name, color: this.newTagColor(), ratingEnabled: false }).subscribe({
      next: (newTag: TagInfo) => {
        this.tagCreated.emit(newTag);
        this.attachTag(video, newTag.id, [...this.tags(), newTag]);
      },
      error: (err) => console.error('Failed to create tag:', err),
    });
  }

  addVideoToSimpleList(video: VideoItem, listId: string) {
    this.simpleListService.addVideos(listId, [video.fileId]).subscribe({
      next: () => this.listsChanged.emit(),
      error: (err) => console.error('Failed to add video to list:', err),
    });
  }

  createListAndAddVideo(video: VideoItem) {
    const name = this.newListName().trim();
    if (!name) return;

    this.simpleListService.createSimpleList(name).subscribe({
      next: (created) => {
        this.simpleListService.addVideos(created.id, [video.fileId]).subscribe({
          next: () => this.listsChanged.emit(),
          error: (err) => console.error('Failed to add video to new list:', err),
        });
      },
      error: (err) => console.error('Failed to create list:', err),
    });
  }

  rateVideo(video: VideoItem, rating: number) {
    const finalRating = video.rating === rating ? 0 : rating;
    this.ratingService.setRating(video.fileId, finalRating).subscribe({
      next: () => this.videoPatched.emit({ videoId: video.id, changes: { rating: finalRating } }),
      error: (err) => console.error('Failed to set rating:', err),
    });
  }

  private attachTag(video: VideoItem, tagId: string, knownTags: TagInfo[]) {
    this.tagService.attachTagToVideo(video.fileId, tagId).subscribe({
      next: () => {
        const tag = knownTags.find((t) => t.id === tagId);
        if (!tag || video.tags?.some((t) => t.id === tagId)) return;
        const summary: TagSummary = {
          id: tag.id,
          name: tag.name,
          color: tag.color,
          ratingEnabled: tag.ratingEnabled,
        };
        this.videoPatched.emit({
          videoId: video.id,
          changes: { tags: [...(video.tags ?? []), summary] },
        });
      },
      error: (err) => console.error('Failed to attach tag to video:', err),
    });
  }

  private detachTag(video: VideoItem, tagId: string) {
    this.tagService.detachTagFromVideo(video.fileId, tagId).subscribe({
      next: () => {
        const tags = (video.tags ?? []).filter((t) => t.id !== tagId);
        this.videoPatched.emit({ videoId: video.id, changes: { tags } });
      },
      error: (err) => console.error('Failed to detach tag from video:', err),
    });
  }
}
