import { Component, DestroyRef, OnInit, signal, computed, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute } from '@angular/router';
import { catchError, debounceTime, distinctUntilChanged, map, of, Subject, switchMap } from 'rxjs';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';

import { VideoQueryParams, VideoService } from '../../core/services/video.service';
import { TagService } from '../../core/services/tag.service';
import { SourceDirectoryService } from '../../core/services/source-directory.service';
import { SmartListService } from '../../core/services/smart-list.service';
import { SimpleListService } from '../../core/services/simple-list.service';
import { VideoItem } from '../../core/models/video.model';
import { TagInfo } from '../../core/models/tag.model';
import { SourceDirectoryInfo } from '../../core/models/source-directory.model';
import { SmartListDTO } from '../../core/models/smart-list.model';
import { SimpleListDTO } from '../../core/models/simple-list.model';
import { ClipSequence } from '../../core/models/clip-sequence.model';
import { ClipSequenceBuilderService } from '../../core/services/clip-sequence-builder.service';
import { VideoPlayerDialogComponent } from '../video-player/video-player-dialog.component';
import { MultiSegmentPlayerDialogComponent } from '../video-player/multi-segment-player-dialog.component';
import { LoadErrorComponent } from '../../shared/ui/load-error.component';
import { ListBadgeIndex, VideoGridComponent } from './video-grid.component';
import { LibraryFiltersPanelComponent } from './library-filters-panel.component';
import { VideoContextMenuComponent, VideoContextMenuState } from './video-context-menu.component';
import {
  ConditionDraft,
  createCondition,
  describeCondition,
  parseCriteria,
  serializeCriteria,
} from '../../shared/criteria/criteria';

@Component({
  selector: 'app-content-library',
  imports: [
    FormsModule,
    VideoPlayerDialogComponent,
    MultiSegmentPlayerDialogComponent,
    LibraryFiltersPanelComponent,
    VideoContextMenuComponent,
    LoadErrorComponent,
    VideoGridComponent,
  ],
  template: `
    <div class="flex flex-col h-full bg-background text-foreground">
      <!-- Compact Header Bar -->
      <div class="flex items-center gap-2 px-4 py-2 border-b border-border">
        <input
          type="text"
          placeholder="Search..."
          [ngModel]="searchInput()"
          (ngModelChange)="onSearchChange($event)"
          class="px-2.5 py-1.5 bg-card text-foreground border border-border rounded-lg text-xs focus:outline-none focus:ring-1 focus:ring-primary w-48"
        />
        <select
          [ngModel]="selectedListValue()"
          (ngModelChange)="onListSelectionChange($event)"
          class="px-2 py-1.5 bg-card text-foreground border border-border rounded-lg text-xs focus:outline-none focus:ring-1 focus:ring-primary"
        >
          <option value="">All Videos</option>
          <option value="history">History</option>
          @if (smartLists().length > 0) {
            <optgroup label="Smart Lists">
              @for (list of smartLists(); track list.id) {
                <option [value]="'smart:' + list.id">{{ list.name }}</option>
              }
            </optgroup>
          }
          @if (simpleLists().length > 0) {
            <optgroup label="Simple Lists">
              @for (list of simpleLists(); track list.id) {
                <option [value]="'simple:' + list.id">{{ list.name }}</option>
              }
            </optgroup>
          }
        </select>
        <select
          [ngModel]="selectedSort()"
          (ngModelChange)="onSortChange($event)"
          class="px-2 py-1.5 bg-card text-foreground border border-border rounded-lg text-xs focus:outline-none focus:ring-1 focus:ring-primary"
        >
          <option value="filename_asc">Name (A-Z)</option>
          <option value="filename_desc">Name (Z-A)</option>
          <option value="rating_asc">Rating (Low-High)</option>
          <option value="rating_desc">Rating (High-Low)</option>
          <option value="play_count_asc">Plays (Low-High)</option>
          <option value="play_count_desc">Plays (High-Low)</option>
          <option value="last_played_desc">Last Played (Newest)</option>
          <option value="last_played_asc">Last Played (Oldest)</option>
        </select>

        <!-- Active Condition Chips (inline) -->
        @for (chip of conditionChips(); track chip.id) {
          <div
            class="flex items-center gap-1 px-2 py-0.5 bg-accent text-accent-foreground rounded-full text-xs"
          >
            <span>{{ chip.label }}</span>
            <button
              (click)="removeConditionById(chip.id)"
              class="hover:text-destructive transition font-bold leading-none"
              aria-label="Remove condition"
            >
              ×
            </button>
          </div>
        }

        <div class="flex-1"></div>

        @if (clipSequenceError()) {
          <span class="max-w-56 truncate text-xs text-destructive" [title]="clipSequenceError()">
            {{ clipSequenceError() }}
          </span>
        }
        <span class="text-xs text-muted-foreground tabular-nums"> {{ total() }} videos </span>
        <button
          (click)="playCurrentSelections()"
          [disabled]="isLoading() || isBuildingClipSequence() || videos().length === 0"
          class="inline-flex items-center gap-1.5 rounded-full bg-secondary px-3 py-1.5 text-xs font-medium text-secondary-foreground transition hover:bg-secondary/80 disabled:cursor-not-allowed disabled:opacity-50"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="14"
            height="14"
            viewBox="0 0 24 24"
            fill="currentColor"
            class="shrink-0"
          >
            <polygon points="5,3 19,12 5,21" />
          </svg>
          {{ isBuildingClipSequence() ? 'Loading...' : 'Play selections' }}
        </button>
        <button
          (click)="showQueryBuilder.set(!showQueryBuilder())"
          class="px-3 py-1.5 rounded-full text-xs font-medium transition-colors"
          [class]="
            showQueryBuilder()
              ? 'bg-primary text-primary-foreground'
              : 'bg-secondary text-secondary-foreground hover:bg-secondary/80'
          "
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="14"
            height="14"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
            class="inline-block -mt-px"
          >
            <polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3" />
          </svg>
          @if (conditions().length > 0) {
            <span class="ml-1">({{ conditions().length }})</span>
          }
        </button>
      </div>

      <!-- Main Body: Grid + Filter Sidebar -->
      <div class="flex flex-1 min-h-0">
        <!-- Video Grid -->
        <div class="flex-1 overflow-auto p-4">
          @if (isLoading()) {
            <div class="flex items-center justify-center h-full">
              <div class="text-muted-foreground text-sm">Loading videos...</div>
            </div>
          } @else if (loadError()) {
            <app-load-error class="h-full" [message]="loadError()!" (retry)="loadVideos()" />
          } @else if (videos().length === 0) {
            <div class="flex items-center justify-center h-full">
              <div class="text-muted-foreground text-sm">No videos found</div>
            </div>
          } @else {
            <app-video-grid
              [videos]="videos()"
              [groupByDay]="historyMode()"
              [badges]="listBadges()"
              (open)="selectVideo($event)"
              (menuRequested)="onVideoContextMenu($event.event, $event.video)"
            />
          }
        </div>

        <!-- Right Filter Sidebar -->
        @if (showQueryBuilder()) {
          <app-library-filters-panel
            [conditions]="conditions()"
            [criteria]="criteria()"
            [tags]="availableTags()"
            [sources]="sourceDirectories()"
            [simpleLists]="simpleLists()"
            [smartLists]="smartLists()"
            (conditionsChange)="onConditionsChange($event)"
            (closed)="showQueryBuilder.set(false)"
            (saved)="onSmartListSaved($event)"
          />
        }
      </div>

      <!-- Compact Pagination Footer -->
      <div class="px-4 py-1.5 border-t border-border flex items-center justify-between">
        <span class="text-xs text-muted-foreground">
          {{ videos().length > 0 ? offset() + 1 : 0 }}-{{
            Math.min(offset() + limit(), total())
          }}
          of {{ total() }}
        </span>
        <div class="flex items-center gap-1.5">
          <button
            (click)="previousPage()"
            [disabled]="offset() === 0"
            class="px-3 py-1 bg-secondary text-secondary-foreground rounded-full text-xs hover:bg-opacity-80 disabled:opacity-50 disabled:cursor-not-allowed transition"
          >
            Prev
          </button>
          <span class="text-xs text-muted-foreground tabular-nums">
            {{ currentPage() + 1 }}/{{ totalPages() }}
          </span>
          <button
            (click)="nextPage()"
            [disabled]="offset() + limit() >= total()"
            class="px-3 py-1 bg-secondary text-secondary-foreground rounded-full text-xs hover:bg-opacity-80 disabled:opacity-50 disabled:cursor-not-allowed transition"
          >
            Next
          </button>
        </div>
      </div>
    </div>

    <!-- Context Menu -->
    @if (contextMenu(); as menu) {
      <app-video-context-menu
        [menu]="menu"
        [tags]="availableTags()"
        [simpleLists]="simpleLists()"
        (closed)="closeContextMenu()"
        (videoPatched)="onVideoPatched($event)"
        (tagCreated)="onTagCreated($event)"
        (listsChanged)="onListsChanged()"
      />
    }

    <!-- Video Player Dialog -->
    @if (selectedVideo()) {
      <app-video-player-dialog
        [video]="selectedVideo()!"
        (closed)="selectedVideo.set(null)"
        (thumbnailUpdated)="onThumbnailUpdated($event)"
        (ratingChanged)="onRatingChanged($event)"
      />
    }

    @if (selectedClipSequence()) {
      <app-multi-segment-player-dialog
        [sequence]="selectedClipSequence()!"
        (closed)="selectedClipSequence.set(null)"
      />
    }
  `,
  styles: [
    `
      :host {
        display: contents;
      }
    `,
  ],
})
export class ContentLibraryComponent implements OnInit {
  private videoService = inject(VideoService);
  private tagService = inject(TagService);
  private sourceDirectoryService = inject(SourceDirectoryService);
  private smartListService = inject(SmartListService);
  private simpleListService = inject(SimpleListService);
  private clipSequenceBuilder = inject(ClipSequenceBuilderService);
  private route = inject(ActivatedRoute);
  private destroyRef = inject(DestroyRef);

  // Search state
  searchInput = signal('');
  private searchSubject = new Subject<string>();

  // Query builder state
  conditions = signal<ConditionDraft[]>([]);
  /** Serialized complete conditions; null when nothing filters. */
  protected readonly criteria = computed(() => serializeCriteria(this.conditions()));
  showQueryBuilder = signal(false);

  // Sort / pagination
  selectedSort = signal('filename_asc');
  offset = signal(0);
  limit = signal(1000);

  // Video grid state
  videos = signal<VideoItem[]>([]);
  total = signal(0);
  isLoading = signal(false);
  loadError = signal<string | null>(null);
  selectedVideo = signal<VideoItem | null>(null);
  selectedClipSequence = signal<ClipSequence | null>(null);
  isBuildingClipSequence = signal(false);
  clipSequenceError = signal('');

  // Reference data
  availableTags = signal<TagInfo[]>([]);
  sourceDirectories = signal<SourceDirectoryInfo[]>([]);

  // List selector state
  smartLists = signal<SmartListDTO[]>([]);
  simpleLists = signal<SimpleListDTO[]>([]);
  // fileId -> smart list IDs the video currently matches (server-evaluated)
  smartListMemberships = signal<Record<string, string[]>>({});
  selectedSmartListId = signal<string | null>(null);
  selectedSimpleListId = signal<string | null>(null);
  historyMode = signal(false);
  private smartListsLoaded = false;
  private pendingListParam: string | null = null;

  // Context menu state
  contextMenu = signal<VideoContextMenuState | null>(null);

  // Video loads go through switchMap so a slow response never overwrites a newer view.
  private readonly videoRequests = new Subject<VideoQueryParams>();
  private readonly conditionChanges = new Subject<void>();

  // Computed signals
  currentPage = computed(() => Math.floor(this.offset() / this.limit()));
  totalPages = computed(() => Math.ceil(this.total() / this.limit()));

  selectedListValue = computed(() => {
    if (this.historyMode()) return 'history';
    if (this.selectedSmartListId()) return `smart:${this.selectedSmartListId()}`;
    if (this.selectedSimpleListId()) return `simple:${this.selectedSimpleListId()}`;
    return '';
  });

  hasValidConditions = computed(() => this.criteria() !== null);

  // fileId -> { smart, simple } list badges, derived from loaded lists + memberships
  listBadges = computed(() => {
    const result: ListBadgeIndex = {};
    const ensure = (fileId: string) => (result[fileId] ??= { smart: [], simple: [] });

    for (const list of this.simpleLists()) {
      for (const fileId of list.videoIds) {
        ensure(fileId).simple.push({ id: list.id, name: list.name });
      }
    }

    const smartById = new Map(this.smartLists().map((l) => [l.id, l]));
    for (const [fileId, smartListIds] of Object.entries(this.smartListMemberships())) {
      for (const id of smartListIds) {
        const list = smartById.get(id);
        if (list) ensure(fileId).smart.push({ id, name: list.name });
      }
    }

    return result;
  });

  conditionChips = computed(() => {
    const lookups = {
      tags: this.availableTags(),
      sources: this.sourceDirectories(),
      simpleLists: this.simpleLists(),
      smartLists: this.smartLists(),
    };
    return this.conditions()
      .filter((c) => c.type)
      .map((c) => ({ id: c.id, label: describeCondition(c, lookups) }));
  });

  constructor() {
    this.videoRequests
      .pipe(
        switchMap((params) =>
          this.videoService.getVideos(params).pipe(
            map((response) => ({ response, error: null })),
            catchError((error: unknown) => of({ response: null, error })),
          ),
        ),
        takeUntilDestroyed(),
      )
      .subscribe(({ response, error }) => {
        this.isLoading.set(false);
        if (response) {
          this.videos.set(response.videos);
          this.total.set(response.total);
        } else {
          console.error('Failed to load videos:', error);
          this.videos.set([]);
          this.total.set(0);
          this.loadError.set('Could not load videos.');
        }
      });

    this.conditionChanges.pipe(debounceTime(400), takeUntilDestroyed()).subscribe(() => {
      this.offset.set(0);
      this.loadVideos();
    });

    this.searchSubject
      .pipe(debounceTime(300), distinctUntilChanged(), takeUntilDestroyed())
      .subscribe(() => {
        this.offset.set(0);
        this.loadVideos();
      });

    // React to query param changes (handles same-route navigation e.g. /library <-> /library?history)
    this.route.queryParamMap.pipe(takeUntilDestroyed()).subscribe((params) => {
      const historyParam = params.has('history');
      const smartListParam = params.get('smartList');
      const simpleListParam = params.get('simpleList');
      const sourceParam = params.get('source');

      if (historyParam) {
        this.onListSelectionChange('history');
      } else if (smartListParam) {
        if (this.smartListsLoaded) {
          this.onListSelectionChange('smart:' + smartListParam);
        } else {
          this.pendingListParam = 'smart:' + smartListParam;
        }
      } else if (simpleListParam) {
        this.onListSelectionChange('simple:' + simpleListParam);
      } else {
        if (sourceParam) {
          this.conditions.set([createCondition('sourceDirectory', { refId: sourceParam })]);
          this.showQueryBuilder.set(true);
        }
        // Reset history/list state when navigating to plain /library
        if (this.historyMode() || this.selectedSmartListId() || this.selectedSimpleListId()) {
          this.onListSelectionChange('');
        } else {
          this.loadVideos();
        }
      }
    });
  }

  ngOnInit() {
    this.loadTags();
    this.loadSourceDirectories();
    this.loadSmartLists();
    this.loadSimpleLists();
    this.loadSmartListMemberships();
  }

  /** Reloads the current page; also used by the error state's Retry button. */
  loadVideos() {
    this.isLoading.set(true);
    this.loadError.set(null);
    this.videoRequests.next(this.buildQueryParams());
  }

  /**
   * Flat filters (search, history, simple list) are sent together with the
   * criteria; the server returns their intersection.
   */
  private buildQueryParams(): VideoQueryParams {
    const params: VideoQueryParams = {
      limit: this.limit().toString(),
      offset: this.offset().toString(),
      sort: this.selectedSort(),
    };

    if (this.historyMode()) {
      params['played'] = 'true';
      params['sort'] = 'last_played_desc';
    }

    const search = this.searchInput().trim();
    if (search) {
      params['search'] = search;
    }

    const criteria = this.criteria();
    if (criteria) {
      params['criteria'] = criteria;
    }

    // Filtered server-side, so an empty list yields an empty result.
    const simpleListId = this.selectedSimpleListId();
    if (simpleListId) {
      params['simpleListIds'] = simpleListId;
    }

    return params;
  }

  private loadTags() {
    this.tagService.getTags().subscribe({
      next: (tags: TagInfo[]) => {
        this.availableTags.set(tags);
      },
      error: (error) => {
        console.error('Failed to load tags:', error);
      },
    });
  }

  private loadSourceDirectories() {
    this.sourceDirectoryService.getSourceDirectories().subscribe({
      next: (directories: SourceDirectoryInfo[]) => {
        this.sourceDirectories.set(directories);
      },
      error: (error) => {
        console.error('Failed to load source directories:', error);
      },
    });
  }

  private loadSmartLists() {
    this.smartListService.getSmartLists().subscribe({
      next: (lists: SmartListDTO[]) => {
        this.smartLists.set(lists);
        this.smartListsLoaded = true;
        if (this.pendingListParam) {
          this.onListSelectionChange(this.pendingListParam);
          this.pendingListParam = null;
        }
      },
      error: (error) => {
        console.error('Failed to load smart lists:', error);
      },
    });
  }

  private loadSimpleLists() {
    this.simpleListService.getSimpleLists().subscribe({
      next: (lists: SimpleListDTO[]) => {
        this.simpleLists.set(lists);
      },
      error: (error) => {
        console.error('Failed to load simple lists:', error);
      },
    });
  }

  private loadSmartListMemberships() {
    this.smartListService.getSmartListMemberships().subscribe({
      next: (memberships) => {
        this.smartListMemberships.set(memberships);
      },
      error: (error) => {
        console.error('Failed to load smart list memberships:', error);
      },
    });
  }

  // --- List selection ---

  onListSelectionChange(value: string) {
    if (!value) {
      // "All Videos"
      this.selectedSmartListId.set(null);
      this.selectedSimpleListId.set(null);
      this.historyMode.set(false);
      this.conditions.set([]);
      this.offset.set(0);
      this.loadVideos();
      return;
    }

    if (value === 'history') {
      this.historyMode.set(true);
      this.selectedSmartListId.set(null);
      this.selectedSimpleListId.set(null);
      this.conditions.set([]);
      this.selectedSort.set('last_played_desc');
      this.offset.set(0);
      this.loadVideos();
      return;
    }

    this.historyMode.set(false);
    const [type, id] = value.split(':');

    if (type === 'smart') {
      this.selectedSmartListId.set(id);
      this.selectedSimpleListId.set(null);

      const list = this.smartLists().find((l) => l.id === id);
      if (list) {
        this.conditions.set(parseCriteria(list.criteria));
        this.showQueryBuilder.set(true);
      }

      this.offset.set(0);
      this.loadVideos();
    } else if (type === 'simple') {
      this.selectedSimpleListId.set(id);
      this.selectedSmartListId.set(null);
      this.conditions.set([]);
      this.offset.set(0);
      this.loadVideos();
    }
  }

  // --- Query builder methods ---

  removeConditionById(id: string) {
    this.conditions.update((conds) => conds.filter((c) => c.id !== id));
    this.onConditionsChanged();
  }

  onConditionsChange(conditions: ConditionDraft[]) {
    const previous = this.criteria();
    this.conditions.set(conditions);
    // Only refetch when the effective (complete) criteria changed.
    if (this.criteria() !== previous) {
      this.onConditionsChanged();
    }
  }

  onConditionsChanged() {
    this.conditionChanges.next();
  }

  // --- Search ---

  onSearchChange(value: string) {
    this.searchInput.set(value);
    this.searchSubject.next(value);
  }

  // --- Sort / pagination ---

  onSortChange(value: string) {
    this.selectedSort.set(value);
    this.offset.set(0);
    this.loadVideos();
  }

  previousPage() {
    const newOffset = Math.max(0, this.offset() - this.limit());
    this.offset.set(newOffset);
    this.loadVideos();
  }

  nextPage() {
    if (this.offset() + this.limit() < this.total()) {
      this.offset.set(this.offset() + this.limit());
      this.loadVideos();
    }
  }

  // --- Save as Smart List ---

  onSmartListSaved(created: SmartListDTO) {
    this.loadSmartLists();
    this.loadSmartListMemberships();
    this.selectedSmartListId.set(created.id);
  }
  // --- Video helpers ---

  selectVideo(video: VideoItem) {
    this.selectedVideo.set(video);
  }

  playCurrentSelections(): void {
    const videos = this.videos();
    if (videos.length === 0 || this.isBuildingClipSequence()) return;

    this.isBuildingClipSequence.set(true);
    this.clipSequenceError.set('');

    this.clipSequenceBuilder
      .buildFromView(videos, this.buildQueryParams(), {
        title: 'Selections',
        sourceLabel: this.currentClipSequenceSourceLabel(),
      })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (sequence) => {
          this.isBuildingClipSequence.set(false);
          if (sequence.segments.length === 0) {
            this.clipSequenceError.set('No playable selections in current view');
            return;
          }
          this.selectedClipSequence.set(sequence);
        },
        error: (error) => {
          console.error('Failed to build clip sequence:', error);
          this.isBuildingClipSequence.set(false);
          this.clipSequenceError.set('Could not load selections');
        },
      });
  }

  // --- Context menu ---

  onVideoContextMenu(event: MouseEvent, video: VideoItem) {
    event.preventDefault();

    // Estimated dimensions of the root menu and its (tallest) submenu, used to
    // keep both fully on-screen regardless of where the click lands.
    const margin = 8;
    const menuWidth = 170;
    const menuHeight = 130;
    const submenuWidth = 200;
    const submenuHeight = 320;
    const vw = window.innerWidth;
    const vh = window.innerHeight;

    // Open the submenu to the left / upward when there isn't room on the
    // preferred side.
    const flipX = event.clientX + menuWidth + submenuWidth + margin > vw;
    const flipY = event.clientY + submenuHeight + margin > vh;

    let x = Math.min(event.clientX, vw - menuWidth - margin);
    // When the submenu opens left, leave room for it beside the root menu.
    x = Math.max(x, flipX ? submenuWidth + margin : margin);

    const y = Math.min(Math.max(event.clientY, margin), vh - menuHeight - margin);

    this.contextMenu.set({ x, y, flipX, flipY, video });
  }

  closeContextMenu() {
    this.contextMenu.set(null);
  }

  onVideoPatched({ videoId, changes }: { videoId: string; changes: Partial<VideoItem> }) {
    this.videos.update((vids) => vids.map((v) => (v.id === videoId ? { ...v, ...changes } : v)));
    this.loadSmartListMemberships();
    this.closeContextMenu();
  }

  onTagCreated(tag: TagInfo) {
    this.availableTags.update((tags) => [...tags, tag]);
  }

  onListsChanged() {
    this.loadSimpleLists();
    this.loadSmartListMemberships();
    this.closeContextMenu();
  }

  onRatingChanged(event: { fileId: string; rating: number }): void {
    this.videos.update((vids) =>
      vids.map((v) => (v.fileId === event.fileId ? { ...v, rating: event.rating } : v)),
    );
    this.loadSmartListMemberships();
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

  private currentClipSequenceSourceLabel(): string {
    if (this.historyMode()) return 'History';

    const smartListId = this.selectedSmartListId();
    if (smartListId) {
      const smartList = this.smartLists().find((list) => list.id === smartListId);
      return smartList ? `Smart List: ${smartList.name}` : 'Smart List';
    }

    const simpleListId = this.selectedSimpleListId();
    if (simpleListId) {
      const simpleList = this.simpleLists().find((list) => list.id === simpleListId);
      return simpleList ? `List: ${simpleList.name}` : 'List';
    }

    if (this.hasValidConditions()) return 'Filtered library';
    if (this.searchInput().trim()) return `Search: ${this.searchInput().trim()}`;
    return 'Library';
  }

  protected readonly Math = Math;
}
