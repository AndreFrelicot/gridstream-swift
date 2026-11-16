import { Component, inject, input, output, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { SimpleListDTO } from '../../core/models/simple-list.model';
import { SmartListDTO } from '../../core/models/smart-list.model';
import { SourceDirectoryInfo } from '../../core/models/source-directory.model';
import { TagInfo } from '../../core/models/tag.model';
import { SmartListService } from '../../core/services/smart-list.service';
import { ConditionEditorComponent } from '../../shared/criteria/condition-editor.component';
import { ConditionDraft } from '../../shared/criteria/criteria';

/** Library filter sidebar: condition editor plus "Save as Smart List". */
@Component({
  selector: 'app-library-filters-panel',
  imports: [FormsModule, ConditionEditorComponent],
  host: { class: 'w-72 flex-shrink-0 border-l border-border flex flex-col bg-card' },
  template: `
    <div class="px-3 py-2 border-b border-border flex items-center justify-between">
      <span class="text-xs font-semibold text-foreground uppercase tracking-wide">Filters</span>
      <button
        (click)="closed.emit()"
        aria-label="Close filters"
        class="text-muted-foreground hover:text-foreground transition-colors"
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
        >
          <path d="M18 6 6 18" />
          <path d="m6 6 12 12" />
        </svg>
      </button>
    </div>
    <div class="flex-1 overflow-auto p-3 space-y-2">
      <app-condition-editor
        [conditions]="conditions()"
        (conditionsChange)="conditionsChange.emit($event)"
        [tags]="tags()"
        [sources]="sources()"
        [simpleLists]="simpleLists()"
        [smartLists]="smartLists()"
      />

      @if (criteria()) {
        <div class="flex items-center gap-1.5 pt-2 border-t border-border">
          @if (!showSaveInput()) {
            <button
              (click)="showSaveInput.set(true)"
              class="px-3 py-1 bg-primary text-primary-foreground rounded-full text-xs hover:bg-opacity-80 transition whitespace-nowrap"
            >
              Save as Smart List
            </button>
          } @else {
            <input
              type="text"
              placeholder="Name..."
              aria-label="Smart list name"
              [ngModel]="newName()"
              (ngModelChange)="newName.set($event)"
              class="px-2 py-1 bg-background text-foreground border border-border rounded-lg text-xs focus:outline-none focus:ring-1 focus:ring-primary flex-1 min-w-0"
            />
            <button
              (click)="save()"
              [disabled]="!newName().trim()"
              class="px-3 py-1 bg-primary text-primary-foreground rounded-full text-xs hover:bg-opacity-80 disabled:opacity-50 transition"
            >
              Save
            </button>
            <button
              (click)="showSaveInput.set(false); newName.set('')"
              class="px-3 py-1 bg-secondary text-secondary-foreground rounded-full text-xs hover:bg-opacity-80 transition"
            >
              Cancel
            </button>
          }
        </div>
      }
    </div>
  `,
})
export class LibraryFiltersPanelComponent {
  private readonly smartListService = inject(SmartListService);

  readonly conditions = input.required<ConditionDraft[]>();
  /** Serialized complete criteria; null hides "Save as Smart List". */
  readonly criteria = input<string | null>(null);
  readonly tags = input<TagInfo[]>([]);
  readonly sources = input<SourceDirectoryInfo[]>([]);
  readonly simpleLists = input<SimpleListDTO[]>([]);
  readonly smartLists = input<SmartListDTO[]>([]);

  readonly conditionsChange = output<ConditionDraft[]>();
  readonly closed = output<void>();
  readonly saved = output<SmartListDTO>();

  readonly showSaveInput = signal(false);
  readonly newName = signal('');

  save(): void {
    const name = this.newName().trim();
    const criteria = this.criteria();
    if (!name || !criteria) return;

    this.smartListService.createSmartList(name, criteria).subscribe({
      next: (created) => {
        this.newName.set('');
        this.showSaveInput.set(false);
        this.saved.emit(created);
      },
      error: (error) => {
        console.error('Failed to save smart list:', error);
      },
    });
  }
}
