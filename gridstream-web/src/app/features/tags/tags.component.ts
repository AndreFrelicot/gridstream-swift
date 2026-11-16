import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { TagService } from '../../core/services/tag.service';
import { LoadErrorComponent } from '../../shared/ui/load-error.component';
import {
  TagInfo,
  CreateTagRequest,
  UpdateTagRequest,
  TAG_COLORS,
} from '../../core/models/tag.model';

@Component({
  selector: 'app-tags',
  imports: [FormsModule, LoadErrorComponent],
  template: `
    <div class="flex flex-col h-full bg-background text-foreground">
      <!-- Header -->
      <div class="p-4 border-b border-border flex justify-between items-center">
        <h1 class="text-2xl font-bold">Tags</h1>
        <button
          (click)="openCreateForm()"
          class="px-3 py-2 bg-primary text-primary-foreground rounded-full hover:opacity-90 transition"
        >
          + New Tag
        </button>
      </div>

      <!-- Create/Edit Form -->
      @if (showForm()) {
      <div class="p-4 border-b border-border bg-card">
        <form (ngSubmit)="saveTag()" class="space-y-3">
          <!-- Name input -->
          <div>
            <label for="tag-name" class="block text-sm font-medium text-muted-foreground mb-1"
              >Tag Name</label
            >
            <input
              id="tag-name"
              [(ngModel)]="formName"
              name="name"
              type="text"
              placeholder="Enter tag name"
              class="w-full px-3 py-2 bg-background border border-border rounded-lg text-foreground placeholder-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary"
            />
          </div>

          <!-- Color picker -->
          <fieldset>
            <legend class="block text-sm font-medium text-muted-foreground mb-2">Color</legend>
            <div class="flex gap-2 flex-wrap">
              @for (color of TAG_COLORS; track color) {
                <button
                  (click)="selectColor(color)"
                  type="button"
                  [attr.aria-label]="'Color ' + color"
                  [attr.aria-pressed]="formColor === color"
                  [style.background-color]="color"
                  [class.ring-2]="formColor === color"
                  [class.ring-offset-2]="formColor === color"
                  class="w-8 h-8 rounded-full transition hover:opacity-80"
                ></button>
              }
            </div>
          </fieldset>

          <!-- Rating enabled toggle -->
          <div class="flex items-center gap-2">
            <input
              [(ngModel)]="formRatingEnabled"
              name="ratingEnabled"
              type="checkbox"
              id="ratingEnabled"
              class="w-4 h-4 rounded-lg border-border accent-primary"
            />
            <label for="ratingEnabled" class="text-sm font-medium">Enable Ratings</label>
          </div>

          <!-- Form actions -->
          <div class="flex gap-2">
            <button
              type="submit"
              class="px-4 py-2 bg-primary text-primary-foreground rounded-full hover:brightness-110 transition"
            >
              {{ editingId() ? 'Update' : 'Create' }}
            </button>
            <button
              (click)="closeForm()"
              type="button"
              class="px-4 py-2 bg-secondary rounded-full hover:bg-accent transition"
            >
              Cancel
            </button>
          </div>
        </form>
      </div>
      }

      <!-- Tags list -->
      <div class="flex-1 overflow-y-auto p-4">
        @if (actionError()) {
          <div class="mb-3 text-sm text-destructive" role="alert">{{ actionError() }}</div>
        }
        @if (loadError()) {
          <app-load-error [message]="loadError()!" (retry)="loadTags()" />
        }
        @if (!loadError() && tags().length === 0) {
          <div class="text-center py-8 text-muted-foreground">
            No tags yet. Create one to get started.
          </div>
        }

        <div class="space-y-2">
          @for (tag of tags(); track tag.id) {
            <div
              class="flex items-center justify-between gap-3 p-3 bg-card border border-border rounded-xl hover:bg-secondary transition"
            >
              <button
                type="button"
                (click)="editTag(tag)"
                [attr.aria-label]="'Edit tag ' + tag.name"
                class="flex items-center gap-3 flex-1 text-left rounded focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
              >
                <!-- Color dot -->
                <span
                  [style.background-color]="tag.color"
                  class="w-4 h-4 rounded-full flex-shrink-0"
                ></span>

                <!-- Tag name and badges -->
                <span class="flex items-center gap-2">
                  <span class="font-medium">{{ tag.name }}</span>
                  @if (tag.ratingEnabled) {
                    <span class="px-2 py-1 text-xs bg-accent text-accent-foreground rounded-full">
                      Ratings enabled
                    </span>
                  }
                </span>
              </button>

              <!-- Delete button -->
              <button
                type="button"
                (click)="deleteTag(tag.id)"
                [attr.aria-label]="'Delete tag ' + tag.name"
                class="px-3 py-1 text-sm bg-destructive/20 text-destructive rounded-full hover:bg-destructive/30 transition"
              >
                Delete
              </button>
            </div>
          }
        </div>
      </div>

      <!-- Footer with tag count -->
      <div class="p-4 border-t border-border bg-card text-sm text-muted-foreground text-center">
        {{ tags().length }} / 30 tags
      </div>
    </div>
  `,
})
export class TagsComponent implements OnInit {
  private tagService = inject(TagService);

  // Signals
  tags = signal<TagInfo[]>([]);
  loadError = signal<string | null>(null);
  actionError = signal<string | null>(null);
  showForm = signal(false);
  editingId = signal<string | null>(null);

  // Form data
  formName = '';
  formColor = TAG_COLORS[0];
  formRatingEnabled = false;

  // Make TAG_COLORS available in template
  readonly TAG_COLORS = TAG_COLORS;

  ngOnInit() {
    this.loadTags();
  }

  loadTags() {
    this.loadError.set(null);
    this.tagService.getTags().subscribe({
      next: (tags) => this.tags.set(tags),
      error: (err) => {
        console.error('Error loading tags:', err);
        this.loadError.set('Could not load tags.');
      },
    });
  }

  openCreateForm() {
    this.editingId.set(null);
    this.formName = '';
    this.formColor = TAG_COLORS[0];
    this.formRatingEnabled = false;
    this.showForm.set(true);
  }

  editTag(tag: TagInfo) {
    this.editingId.set(tag.id);
    this.formName = tag.name;
    this.formColor = tag.color;
    this.formRatingEnabled = tag.ratingEnabled;
    this.showForm.set(true);
  }

  closeForm() {
    this.showForm.set(false);
    this.editingId.set(null);
  }

  selectColor(color: string) {
    this.formColor = color;
  }

  saveTag() {
    this.actionError.set(null);
    if (!this.formName.trim()) {
      alert('Please enter a tag name');
      return;
    }

    if (this.tags().length >= 30 && !this.editingId()) {
      alert('Maximum 30 tags allowed');
      return;
    }

    if (this.editingId()) {
      // Update
      const request: UpdateTagRequest = {
        name: this.formName,
        color: this.formColor,
        ratingEnabled: this.formRatingEnabled,
      };

      this.tagService.updateTag(this.editingId()!, request).subscribe({
        next: (updatedTag) => {
          const currentTags = this.tags();
          const index = currentTags.findIndex((t) => t.id === this.editingId());
          if (index !== -1) {
            currentTags[index] = updatedTag;
            this.tags.set([...currentTags]);
          }
          this.closeForm();
        },
        error: (err) => this.reportActionError('Could not update the tag.', err),
      });
    } else {
      // Create
      const request: CreateTagRequest = {
        name: this.formName,
        color: this.formColor,
        ratingEnabled: this.formRatingEnabled,
      };

      this.tagService.createTag(request).subscribe({
        next: (newTag) => {
          this.tags.set([...this.tags(), newTag]);
          this.closeForm();
        },
        error: (err) => this.reportActionError('Could not create the tag.', err),
      });
    }
  }

  private reportActionError(message: string, err: unknown) {
    console.error(message, err);
    this.actionError.set(message);
  }

  deleteTag(id: string) {
    if (confirm('Are you sure you want to delete this tag?')) {
      this.tagService.deleteTag(id).subscribe({
        next: () => {
          this.tags.set(this.tags().filter((t) => t.id !== id));
        },
        error: (err) => this.reportActionError('Could not delete the tag.', err),
      });
    }
  }
}
