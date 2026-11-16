import { Component, OnInit, signal, inject } from '@angular/core';
import { DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { SimpleListService } from '../../core/services/simple-list.service';
import {
  SIMPLE_LIST_SORT_ORDERS,
  SimpleListDTO,
  normalizeSortOrder,
} from '../../core/models/simple-list.model';
import { LoadErrorComponent } from '../../shared/ui/load-error.component';

interface EditingState {
  id: string;
  name: string;
  sortOrder: string;
}

interface DeleteConfirmation {
  id: string;
  name: string;
}

@Component({
  selector: 'app-simple-lists',
  imports: [DatePipe, FormsModule, LoadErrorComponent],
  template: `
    <div class="min-h-screen bg-background p-8">
      <div class="max-w-6xl mx-auto">
        <!-- Header -->
        <div class="mb-8">
          <h1 class="text-3xl font-bold text-foreground mb-2">Simple Lists</h1>
          <p class="text-muted-foreground">Manage and organize your video collections</p>
        </div>

        <!-- Create New List Form -->
        <div class="bg-card border border-border rounded-2xl p-6 mb-8">
          <h2 class="text-lg font-semibold text-foreground mb-4">Create New List</h2>
          <div class="flex gap-3">
            <input
              type="text"
              aria-label="New list name"
              [ngModel]="newListName()"
              (ngModelChange)="newListName.set($event)"
              placeholder="Enter list name..."
              class="flex-1 px-4 py-2 bg-background border border-border rounded-lg text-foreground placeholder-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary"
            />
            <button
              (click)="createList()"
              [disabled]="!newListName() || isCreating()"
              class="px-6 py-2 bg-primary text-primary-foreground rounded-full font-medium hover:opacity-90 disabled:opacity-50 disabled:cursor-not-allowed transition"
            >
              {{ isCreating() ? 'Creating...' : 'Create' }}
            </button>
          </div>
        </div>

        <!-- Error Message -->
        @if (error()) {
          <div
            role="alert"
            class="bg-destructive/10 border border-destructive text-destructive px-4 py-3 rounded-lg mb-6"
          >
            {{ error() }}
          </div>
        }

        @if (loadError()) {
          <app-load-error [message]="loadError()" (retry)="loadLists()" />
        } @else if (!loaded()) {
          <p class="text-muted-foreground">Loading lists...</p>
        } @else if (lists().length > 0) {
          <!-- Lists Table -->
          <div class="bg-card border border-border rounded-2xl overflow-hidden">
            <table class="w-full">
              <thead>
                <tr class="border-b border-border bg-background/50">
                  <th class="px-6 py-3 text-left text-sm font-semibold text-foreground">Name</th>
                  <th class="px-6 py-3 text-left text-sm font-semibold text-foreground">Videos</th>
                  <th class="px-6 py-3 text-left text-sm font-semibold text-foreground">
                    Sort Order
                  </th>
                  <th class="px-6 py-3 text-left text-sm font-semibold text-foreground">Created</th>
                  <th class="px-6 py-3 text-right text-sm font-semibold text-foreground">Actions</th>
                </tr>
              </thead>
              <tbody>
                @for (list of lists(); track list.id) {
                  <tr class="border-b border-border hover:bg-background/50 transition">
                    <!-- Edit Mode Row -->
                    @if (isEditing(list.id)) {
                      <td colspan="5" class="px-6 py-4">
                        <div class="space-y-4">
                          <div>
                            <label
                              [for]="'list-name-' + list.id"
                              class="block text-sm font-medium text-foreground mb-2"
                              >List Name</label
                            >
                            <input
                              [id]="'list-name-' + list.id"
                              type="text"
                              [ngModel]="editingState().name"
                              (ngModelChange)="updateEditingName($event)"
                              class="w-full px-4 py-2 bg-background border border-border rounded-lg text-foreground focus:outline-none focus:ring-2 focus:ring-primary"
                            />
                          </div>
                          <div>
                            <label
                              [for]="'list-sort-' + list.id"
                              class="block text-sm font-medium text-foreground mb-2"
                              >Sort Order</label
                            >
                            <select
                              [id]="'list-sort-' + list.id"
                              [ngModel]="editingState().sortOrder"
                              (ngModelChange)="updateEditingSortOrder($event)"
                              class="w-full px-4 py-2 bg-background border border-border rounded-lg text-foreground focus:outline-none focus:ring-2 focus:ring-primary"
                            >
                              @for (option of sortOrders; track option.value) {
                                <option [value]="option.value">{{ option.label }}</option>
                              }
                            </select>
                          </div>
                          <div class="flex gap-3 justify-end">
                            <button
                              (click)="cancelEdit()"
                              class="px-4 py-2 border border-border text-foreground rounded-full hover:bg-background/50 transition"
                            >
                              Cancel
                            </button>
                            <button
                              (click)="saveEdit(list.id)"
                              [disabled]="isUpdating()"
                              class="px-4 py-2 bg-primary text-primary-foreground rounded-full hover:brightness-110 disabled:opacity-50 disabled:cursor-not-allowed transition"
                            >
                              {{ isUpdating() ? 'Saving...' : 'Save' }}
                            </button>
                          </div>
                        </div>
                      </td>
                    } @else {
                      <!-- View Mode Row -->
                      <td class="px-6 py-4">
                        <button
                          (click)="navigateToList(list.id)"
                          class="text-foreground font-medium hover:text-primary transition"
                        >
                          {{ list.name }}
                        </button>
                      </td>
                      <td class="px-6 py-4 text-muted-foreground">{{ list.videoCount }}</td>
                      <td class="px-6 py-4 text-muted-foreground">
                        {{ formatSortOrder(list.sortOrder) }}
                      </td>
                      <td class="px-6 py-4 text-muted-foreground">{{ list.createdAt | date: 'mediumDate' }}</td>
                      <td class="px-6 py-4">
                        <div class="flex justify-end gap-3">
                          <button
                            (click)="startEdit(list)"
                            class="px-3 py-1 text-sm bg-secondary text-secondary-foreground rounded-full hover:bg-secondary/80 transition"
                          >
                            Edit
                          </button>
                          <button
                            (click)="startDelete(list.id, list.name)"
                            class="px-3 py-1 text-sm bg-destructive/20 text-destructive rounded-full hover:bg-destructive/30 transition"
                          >
                            Delete
                          </button>
                        </div>
                      </td>
                    }
                  </tr>
                }
              </tbody>
            </table>
          </div>
        } @else {
          <!-- No Lists State -->
          <div class="bg-card border border-border rounded-2xl p-12 text-center">
            <p class="text-muted-foreground mb-4">
              No simple lists yet. Create your first list above!
            </p>
          </div>
        }

        <!-- Delete Confirmation Modal -->
        @if (deleteConfirmation()) {
          <div class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
            <div
              role="alertdialog"
              aria-modal="true"
              aria-labelledby="delete-list-title"
              class="bg-card border border-border rounded-2xl p-6 max-w-sm"
            >
              <h3 id="delete-list-title" class="text-lg font-semibold text-foreground mb-2">Delete List?</h3>
              <p class="text-muted-foreground mb-6">
                Are you sure you want to delete "<strong>{{ deleteConfirmation()?.name }}</strong
                >"?
              </p>
              <div class="flex gap-3 justify-end">
                <button
                  (click)="cancelDelete()"
                  class="px-4 py-2 border border-border text-foreground rounded-full hover:bg-background/50 transition"
                >
                  Cancel
                </button>
                <button
                  (click)="confirmDelete()"
                  [disabled]="isDeleting()"
                  class="px-4 py-2 bg-destructive text-destructive-foreground rounded-full hover:opacity-90 disabled:opacity-50 disabled:cursor-not-allowed transition"
                >
                  {{ isDeleting() ? 'Deleting...' : 'Delete' }}
                </button>
              </div>
            </div>
          </div>
        }
      </div>
    </div>
  `,
  styles: [],
})
export class SimpleListsComponent implements OnInit {
  private router = inject(Router);
  private simpleListService = inject(SimpleListService);

  lists = signal<SimpleListDTO[]>([]);
  newListName = signal('');
  isCreating = signal(false);
  isUpdating = signal(false);
  isDeleting = signal(false);
  error = signal('');
  loadError = signal('');
  loaded = signal(false);
  editingId = signal<string | null>(null);
  deleteConfirmation = signal<DeleteConfirmation | null>(null);
  editingState = signal<EditingState>({ id: '', name: '', sortOrder: '' });
  readonly sortOrders = SIMPLE_LIST_SORT_ORDERS;

  ngOnInit(): void {
    this.loadLists();
  }

  loadLists(): void {
    this.loadError.set('');
    this.simpleListService.getSimpleLists().subscribe({
      next: (lists) => {
        this.lists.set(lists);
        this.loaded.set(true);
      },
      error: (err) => {
        console.error('Error loading lists:', err);
        this.loadError.set('Failed to load lists.');
      },
    });
  }

  createList(): void {
    const name = this.newListName().trim();
    if (!name) return;

    this.isCreating.set(true);
    this.error.set('');

    this.simpleListService.createSimpleList(name).subscribe({
      next: (newList) => {
        this.lists.set([...this.lists(), newList]);
        this.newListName.set('');
        this.isCreating.set(false);
      },
      error: (err) => {
        console.error('Error creating list:', err);
        this.error.set('Failed to create list');
        this.isCreating.set(false);
      },
    });
  }

  startEdit(list: SimpleListDTO): void {
    this.editingId.set(list.id);
    this.editingState.set({
      id: list.id,
      name: list.name,
      sortOrder: normalizeSortOrder(list.sortOrder),
    });
  }

  cancelEdit(): void {
    this.editingId.set(null);
    this.editingState.set({ id: '', name: '', sortOrder: '' });
  }

  updateEditingName(name: string): void {
    this.editingState.update((s) => ({ ...s, name }));
  }

  updateEditingSortOrder(sortOrder: string): void {
    this.editingState.update((s) => ({ ...s, sortOrder }));
  }

  saveEdit(listId: string): void {
    const state = this.editingState();
    if (!state.name.trim()) return;

    this.isUpdating.set(true);
    this.error.set('');

    this.simpleListService.updateSimpleList(listId, state.name, state.sortOrder).subscribe({
      next: (updatedList) => {
        this.lists.set(this.lists().map((list) => (list.id === listId ? updatedList : list)));
        this.editingId.set(null);
        this.isUpdating.set(false);
      },
      error: (err) => {
        console.error('Error updating list:', err);
        this.error.set('Failed to update list');
        this.isUpdating.set(false);
      },
    });
  }

  startDelete(id: string, name: string): void {
    this.deleteConfirmation.set({ id, name });
  }

  cancelDelete(): void {
    this.deleteConfirmation.set(null);
  }

  confirmDelete(): void {
    const confirmation = this.deleteConfirmation();
    if (!confirmation) return;

    this.isDeleting.set(true);
    this.error.set('');

    this.simpleListService.deleteSimpleList(confirmation.id).subscribe({
      next: () => {
        this.lists.set(this.lists().filter((list) => list.id !== confirmation.id));
        this.deleteConfirmation.set(null);
        this.isDeleting.set(false);
      },
      error: (err) => {
        console.error('Error deleting list:', err);
        this.error.set('Failed to delete list');
        this.isDeleting.set(false);
      },
    });
  }

  navigateToList(id: string): void {
    this.router.navigate(['/library'], { queryParams: { simpleList: id } });
  }

  isEditing(listId: string): boolean {
    return this.editingId() === listId;
  }

  formatSortOrder(sortOrder: string | undefined): string {
    if (!sortOrder) return 'Default';
    const canonical = normalizeSortOrder(sortOrder);
    return SIMPLE_LIST_SORT_ORDERS.find((o) => o.value === canonical)?.label ?? sortOrder;
  }
}
