import { Component, signal, inject, OnInit } from '@angular/core';
import { DatePipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { EMPTY, Subject, catchError, debounceTime, map, of, switchMap, tap } from 'rxjs';
import { SmartListService } from '../../core/services/smart-list.service';
import { TagService } from '../../core/services/tag.service';
import { SourceDirectoryService } from '../../core/services/source-directory.service';
import { VideoService } from '../../core/services/video.service';
import { SimpleListService } from '../../core/services/simple-list.service';
import { SmartListDTO } from '../../core/models/smart-list.model';
import { TagInfo } from '../../core/models/tag.model';
import { SourceDirectoryInfo } from '../../core/models/source-directory.model';
import { SimpleListDTO } from '../../core/models/simple-list.model';
import { ConditionEditorComponent } from '../../shared/criteria/condition-editor.component';
import { LoadErrorComponent } from '../../shared/ui/load-error.component';
import {
  ConditionDraft,
  createCondition,
  parseCriteria,
  serializeCriteria,
} from '../../shared/criteria/criteria';

@Component({
  selector: 'app-smart-lists',
  imports: [DatePipe, FormsModule, ConditionEditorComponent, LoadErrorComponent],
  template: `
    <div class="min-h-screen bg-background text-foreground p-8">
      <div class="max-w-7xl mx-auto">
        <!-- Header -->
        <div class="flex justify-between items-center mb-8">
          <div>
            <h1 class="text-4xl font-bold mb-2">Smart Lists</h1>
            <p class="text-muted-foreground">
              Create and manage smart lists to organize your videos
            </p>
          </div>
          <button
            (click)="openCreateModal()"
            class="px-6 py-3 bg-primary text-primary-foreground rounded-full font-semibold transition-all duration-200 hover:opacity-90 shadow-lg"
          >
            + Create Smart List
          </button>
        </div>

        <!-- Smart Lists Table -->
        <div class="bg-card rounded-2xl border border-border overflow-hidden">
          @if (loadError()) {
            <app-load-error [message]="loadError()!" (retry)="loadSmartLists()" />
          } @else if (smartLists().length === 0) {
            <div class="p-8 text-center text-muted-foreground">
              <p>No smart lists created yet. Click "Create Smart List" to get started.</p>
            </div>
          } @else {
            <table class="w-full">
              <thead class="border-b border-border bg-background/50">
                <tr>
                  <th class="px-6 py-4 text-left text-sm font-semibold text-foreground">Name</th>
                  <th class="px-6 py-4 text-left text-sm font-semibold text-foreground">
                    Criteria
                  </th>
                  <th class="px-6 py-4 text-left text-sm font-semibold text-foreground">Created</th>
                  <th class="px-6 py-4 text-right text-sm font-semibold text-foreground">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-border">
                @for (list of smartLists(); track list.id) {
                  <tr
                    class="hover:bg-secondary transition-colors cursor-pointer"
                    (click)="viewSmartList(list.id)"
                  >
                    <td class="px-6 py-4 font-medium">{{ list.name }}</td>
                    <td class="px-6 py-4 text-muted-foreground text-sm">
                      {{ getCriteriaSummary(list.criteria) }}
                    </td>
                    <td class="px-6 py-4 text-muted-foreground text-sm">
                      {{ list.createdAt | date: 'mediumDate' }}
                    </td>
                    <td class="px-6 py-4 text-right space-x-2" (click)="$event.stopPropagation()">
                      <button
                        (click)="openEditModal(list)"
                        class="px-3 py-1 text-sm bg-secondary text-secondary-foreground rounded-full hover:bg-secondary/80 transition-colors"
                      >
                        Edit
                      </button>
                      <button
                        (click)="deleteSmartList(list.id)"
                        class="px-3 py-1 text-sm bg-destructive/20 text-destructive rounded-full hover:bg-destructive/30 transition-colors"
                      >
                        Delete
                      </button>
                    </td>
                  </tr>
                }
              </tbody>
            </table>
          }
        </div>
      </div>

      <!-- Query Builder Modal -->
      @if (showModal()) {
        <div
          class="fixed inset-0 bg-black/50 backdrop-blur-sm flex items-center justify-center p-4 z-50"
        >
          <div
            class="bg-card rounded-2xl border border-border max-w-2xl w-full max-h-[90vh] overflow-y-auto shadow-2xl"
          >
            <div class="p-6 border-b border-border bg-background/50 sticky top-0">
              <h2 class="text-2xl font-bold">{{ isEditing() ? 'Edit' : 'Create' }} Smart List</h2>
            </div>

            <div class="p-6 space-y-6">
              <!-- Name Input -->
              <div>
                <label
                  for="smart-list-name"
                  class="block text-sm font-semibold text-muted-foreground mb-2"
                  >Name</label
                >
                <input
                  id="smart-list-name"
                  [(ngModel)]="formName"
                  type="text"
                  placeholder="e.g., Recent 4K Videos"
                  class="w-full px-4 py-2 bg-background border border-border rounded-lg text-foreground placeholder-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary transition-colors"
                />
              </div>

              <!-- Conditions -->
              <div>
                <h3 class="block text-sm font-semibold text-muted-foreground mb-4">Conditions</h3>
                <app-condition-editor
                  [conditions]="conditions()"
                  (conditionsChange)="onConditionsChange($event)"
                  [tags]="availableTags()"
                  [sources]="availableSources()"
                  [simpleLists]="simpleLists()"
                  [excludedTypes]="['smartListInclude']"
                />
              </div>

              <!-- Preview Count -->
              <div class="bg-background/50 p-4 rounded-lg border border-border">
                <p class="text-muted-foreground text-sm">
                  @if (previewLoading()) {
                    <span>Loading preview...</span>
                  } @else if (previewError()) {
                    <span class="text-destructive">Could not evaluate these conditions.</span>
                  } @else {
                    <span>
                      <span class="font-semibold text-lg text-accent">{{ previewCount() }}</span>
                      <span
                        >{{ previewCount() === 1 ? 'video' : 'videos' }} will match this
                        criteria</span
                      >
                    </span>
                  }
                </p>
              </div>
            </div>

            <!-- Modal Footer -->
            <div
              class="p-6 border-t border-border bg-background/50 flex items-center justify-end gap-3 sticky bottom-0"
            >
              @if (saveError()) {
                <span class="mr-auto text-sm text-destructive" role="alert">{{ saveError() }}</span>
              }
              <button
                (click)="closeModal()"
                class="px-6 py-2 bg-secondary hover:bg-secondary/80 rounded-full font-semibold transition-colors"
              >
                Cancel
              </button>
              <button
                (click)="saveSmartList()"
                class="px-6 py-2 bg-primary text-primary-foreground hover:opacity-90 rounded-full font-semibold transition-all duration-200"
              >
                Save
              </button>
            </div>
          </div>
        </div>
      }
    </div>
  `,
  styles: [],
})
export class SmartListsComponent implements OnInit {
  private smartListService = inject(SmartListService);
  private tagService = inject(TagService);
  private sourceDirectoryService = inject(SourceDirectoryService);
  private videoService = inject(VideoService);
  private simpleListService = inject(SimpleListService);
  private router = inject(Router);

  smartLists = signal<SmartListDTO[]>([]);
  loadError = signal<string | null>(null);
  saveError = signal<string | null>(null);
  previewError = signal(false);
  showModal = signal(false);
  isEditing = signal(false);
  editingId = signal<string | null>(null);
  formName = '';
  conditions = signal<ConditionDraft[]>([]);
  availableTags = signal<TagInfo[]>([]);
  availableSources = signal<SourceDirectoryInfo[]>([]);
  simpleLists = signal<SimpleListDTO[]>([]);
  previewCount = signal(0);
  previewLoading = signal(false);

  private readonly previewRequests = new Subject<void>();

  constructor() {
    // Debounced, cancellable preview of how many videos the current conditions match.
    this.previewRequests
      .pipe(
        debounceTime(500),
        map(() => serializeCriteria(this.conditions())),
        tap((criteria) => {
          this.previewLoading.set(criteria !== null);
          this.previewError.set(false);
          if (criteria === null) this.previewCount.set(0);
        }),
        switchMap((criteria) =>
          criteria === null
            ? EMPTY
            : this.videoService.getVideos({ criteria, limit: '1' }).pipe(
                map((response) => response.total),
                catchError(() => of(null)),
              ),
        ),
        takeUntilDestroyed(),
      )
      .subscribe((total) => {
        this.previewLoading.set(false);
        this.previewError.set(total === null);
        this.previewCount.set(total ?? 0);
      });
  }

  ngOnInit(): void {
    this.loadSmartLists();
    this.loadAvailableData();
    this.simpleListService.getSimpleLists().subscribe((lists) => {
      this.simpleLists.set(lists);
    });
  }

  loadSmartLists(): void {
    this.loadError.set(null);
    this.smartListService.getSmartLists().subscribe({
      next: (lists) => this.smartLists.set(lists),
      error: (err: unknown) => {
        console.error('Failed to load smart lists:', err);
        this.loadError.set('Could not load smart lists.');
      },
    });
  }

  private loadAvailableData(): void {
    this.tagService.getTags().subscribe((tags) => {
      this.availableTags.set(tags);
    });

    this.sourceDirectoryService.getSourceDirectories().subscribe((sources) => {
      this.availableSources.set(sources);
    });
  }

  openCreateModal(): void {
    this.isEditing.set(false);
    this.editingId.set(null);
    this.formName = '';
    this.conditions.set([createCondition()]);
    this.showModal.set(true);
    this.updatePreviewCount();
  }

  openEditModal(list: SmartListDTO): void {
    this.isEditing.set(true);
    this.editingId.set(list.id);
    this.formName = list.name;
    this.conditions.set(parseCriteria(list.criteria));
    this.showModal.set(true);
    this.updatePreviewCount();
  }

  closeModal(): void {
    this.showModal.set(false);
    this.saveError.set(null);
  }

  onConditionsChange(conditions: ConditionDraft[]): void {
    this.conditions.set(conditions);
    this.updatePreviewCount();
  }

  saveSmartList(): void {
    if (!this.formName.trim()) {
      alert('Please enter a name for the smart list');
      return;
    }

    const criteriaJSON = serializeCriteria(this.conditions());
    if (!criteriaJSON) {
      alert('Please add at least one complete condition');
      return;
    }

    const editingId = this.isEditing() ? this.editingId() : null;
    const request = editingId
      ? this.smartListService.updateSmartList(editingId, this.formName, criteriaJSON)
      : this.smartListService.createSmartList(this.formName, criteriaJSON);

    this.saveError.set(null);
    request.subscribe({
      next: () => {
        this.loadSmartLists();
        this.closeModal();
      },
      error: (err: unknown) => {
        console.error('Failed to save smart list:', err);
        this.saveError.set(serverReason(err) ?? 'Could not save the smart list.');
      },
    });
  }

  deleteSmartList(id: string): void {
    if (confirm('Are you sure you want to delete this smart list?')) {
      this.smartListService.deleteSmartList(id).subscribe({
        next: () => this.loadSmartLists(),
        error: (err: unknown) => {
          console.error('Failed to delete smart list:', err);
          this.loadError.set('Could not delete the smart list.');
        },
      });
    }
  }

  viewSmartList(id: string): void {
    this.router.navigate(['/library'], { queryParams: { smartList: id } });
  }

  updatePreviewCount(): void {
    this.previewRequests.next();
  }

  getCriteriaSummary(criteriaJSON: string): string {
    const count = parseCriteria(criteriaJSON).length;
    if (count === 0) {
      return 'No criteria';
    }
    return `${count} condition${count > 1 ? 's' : ''}`;
  }
}

/** The `reason` of a Vapor error response, when there is one. */
function serverReason(err: unknown): string | null {
  if (!(err instanceof HttpErrorResponse)) return null;
  const reason = (err.error as { reason?: unknown } | null)?.reason;
  return typeof reason === 'string' && reason ? reason : null;
}
