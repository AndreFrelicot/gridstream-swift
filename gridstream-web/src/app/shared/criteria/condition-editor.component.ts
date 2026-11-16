import { Component, computed, input, output } from '@angular/core';
import { NgTemplateOutlet } from '@angular/common';
import { FormsModule } from '@angular/forms';

import { SimpleListDTO } from '../../core/models/simple-list.model';
import { SmartListDTO } from '../../core/models/smart-list.model';
import { SourceDirectoryInfo } from '../../core/models/source-directory.model';
import { TagInfo } from '../../core/models/tag.model';
import {
  CRITERIA_GROUPS,
  ConditionDraft,
  CriteriaKind,
  MAX_PATTERN_LENGTH,
  MAX_RATING,
  createCondition,
  isComplete,
  updateCondition,
  withType,
} from './criteria';

/**
 * Editor for a list of smart-list conditions. Stateless: every edit emits a new
 * array through `conditionsChange`, so parents can debounce and derive state
 * from an immutable signal.
 */
@Component({
  selector: 'app-condition-editor',
  imports: [FormsModule, NgTemplateOutlet],
  host: { class: 'block' },
  template: `
    <div class="grid gap-2 [grid-template-columns:repeat(auto-fill,minmax(15rem,1fr))]">
      @for (c of conditions(); let i = $index; track c.id) {
        <fieldset
          class="space-y-1.5 rounded-xl border bg-background p-2"
          [class.border-border]="!c.type || complete(c)"
          [class.border-destructive]="!!c.type && !complete(c)"
        >
          <legend class="sr-only">Condition {{ i + 1 }}</legend>
          <div class="flex items-center gap-1">
            @if (i > 0) {
              <button
                type="button"
                (click)="toggleOperator(c)"
                class="rounded-full border border-border bg-secondary px-1.5 py-0.5 text-xs font-semibold transition-colors hover:bg-secondary/80"
                [attr.aria-label]="'Logic operator ' + c.logicOperator + ', click to toggle'"
              >
                {{ c.logicOperator }}
              </button>
            }
            <select
              [ngModel]="c.type"
              (ngModelChange)="setType(c, $event)"
              [attr.aria-label]="'Condition ' + (i + 1) + ' type'"
              class="min-w-0 flex-1 rounded-lg border border-border bg-card px-2 py-1 text-xs text-foreground focus:outline-none focus:ring-1 focus:ring-primary"
            >
              <option value="">Select type...</option>
              @for (group of groups(); track group.label) {
                <optgroup [label]="group.label">
                  @for (option of group.options; track option.value) {
                    <option [value]="option.value">{{ option.label }}</option>
                  }
                </optgroup>
              }
            </select>
            <button
              type="button"
              (click)="remove(c)"
              class="shrink-0 p-1 text-muted-foreground transition-colors hover:text-destructive"
              [attr.aria-label]="'Remove condition ' + (i + 1)"
              title="Remove"
            >
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
                aria-hidden="true"
              >
                <path d="M18 6 6 18" />
                <path d="m6 6 12 12" />
              </svg>
            </button>
          </div>

          @switch (c.type) {
            @case ('tagsInclude') {
              <ng-container
                *ngTemplateOutlet="tagSelect; context: { $implicit: c, label: 'Tags to include' }"
              />
            }
            @case ('tagsExclude') {
              <ng-container
                *ngTemplateOutlet="tagSelect; context: { $implicit: c, label: 'Tags to exclude' }"
              />
            }
            @case ('ratingMin') {
              <input
                type="number"
                min="0"
                [max]="maxRating"
                step="1"
                [ngModel]="c.value"
                (ngModelChange)="patch(c, { value: $event })"
                aria-label="Minimum rating (0-10)"
                placeholder="Min rating (0-10)"
                [class]="fieldClass"
              />
            }
            @case ('ratingMax') {
              <input
                type="number"
                min="0"
                [max]="maxRating"
                step="1"
                [ngModel]="c.value"
                (ngModelChange)="patch(c, { value: $event })"
                aria-label="Maximum rating (0-10)"
                placeholder="Max rating (0-10)"
                [class]="fieldClass"
              />
            }
            @case ('sourceDirectory') {
              <select
                [ngModel]="c.refId"
                (ngModelChange)="patch(c, { refId: $event })"
                aria-label="Source directory"
                [class]="fieldClass"
              >
                <option value="">Select source...</option>
                @for (source of sources(); track source.id) {
                  <option [value]="source.id">{{ source.name }}</option>
                }
              </select>
            }
            @case ('simpleListInclude') {
              <select
                [ngModel]="c.refId"
                (ngModelChange)="patch(c, { refId: $event })"
                aria-label="Simple list"
                [class]="fieldClass"
              >
                <option value="">Select a list...</option>
                @for (list of simpleLists(); track list.id) {
                  <option [value]="list.id">{{ list.name }}</option>
                }
              </select>
            }
            @case ('smartListInclude') {
              <select
                [ngModel]="c.refId"
                (ngModelChange)="patch(c, { refId: $event })"
                aria-label="Smart list"
                [class]="fieldClass"
              >
                <option value="">Select a smart list...</option>
                @for (list of smartLists(); track list.id) {
                  <option [value]="list.id">{{ list.name }}</option>
                }
              </select>
            }
            @case ('fileSizeMin') {
              <input
                type="number"
                min="0"
                [ngModel]="c.megabytes"
                (ngModelChange)="patch(c, { megabytes: $event })"
                aria-label="Minimum file size in MB"
                placeholder="Min MB"
                [class]="fieldClass"
              />
            }
            @case ('fileSizeMax') {
              <input
                type="number"
                min="0"
                [ngModel]="c.megabytes"
                (ngModelChange)="patch(c, { megabytes: $event })"
                aria-label="Maximum file size in MB"
                placeholder="Max MB"
                [class]="fieldClass"
              />
            }
            @case ('playCountMin') {
              <ng-container
                *ngTemplateOutlet="countInput; context: { $implicit: c, label: 'Minimum plays' }"
              />
            }
            @case ('playCountMax') {
              <ng-container
                *ngTemplateOutlet="countInput; context: { $implicit: c, label: 'Maximum plays' }"
              />
            }
            @case ('annotationCountMin') {
              <ng-container
                *ngTemplateOutlet="
                  countInput;
                  context: { $implicit: c, label: 'Minimum annotations' }
                "
              />
            }
            @case ('annotationCountMax') {
              <ng-container
                *ngTemplateOutlet="
                  countInput;
                  context: { $implicit: c, label: 'Maximum annotations' }
                "
              />
            }
            @case ('filenameContains') {
              <ng-container
                *ngTemplateOutlet="textInput; context: { $implicit: c, label: 'Contains...' }"
              />
            }
            @case ('filenameStartsWith') {
              <ng-container
                *ngTemplateOutlet="textInput; context: { $implicit: c, label: 'Starts with...' }"
              />
            }
            @case ('filenameEndsWith') {
              <ng-container
                *ngTemplateOutlet="textInput; context: { $implicit: c, label: 'Ends with...' }"
              />
            }
            @case ('filenameRegex') {
              <ng-container
                *ngTemplateOutlet="textInput; context: { $implicit: c, label: 'Regex...' }"
              />
            }
            @case ('annotationTextSearch') {
              <ng-container
                *ngTemplateOutlet="textInput; context: { $implicit: c, label: 'Annotation text' }"
              />
            }
            @case ('dateAddedAfter') {
              <ng-container
                *ngTemplateOutlet="dateInput; context: { $implicit: c, label: 'Added after' }"
              />
            }
            @case ('dateAddedBefore') {
              <ng-container
                *ngTemplateOutlet="dateInput; context: { $implicit: c, label: 'Added before' }"
              />
            }
            @case ('dateModifiedAfter') {
              <ng-container
                *ngTemplateOutlet="dateInput; context: { $implicit: c, label: 'Modified after' }"
              />
            }
            @case ('dateModifiedBefore') {
              <ng-container
                *ngTemplateOutlet="dateInput; context: { $implicit: c, label: 'Modified before' }"
              />
            }
            @case ('hasAnnotations') {
              <ng-container
                *ngTemplateOutlet="flagSelect; context: { $implicit: c, label: 'Has annotations' }"
              />
            }
            @case ('hasTextAnnotations') {
              <ng-container
                *ngTemplateOutlet="
                  flagSelect;
                  context: { $implicit: c, label: 'Has text annotation' }
                "
              />
            }
            @case ('hasTimeRanges') {
              <ng-container
                *ngTemplateOutlet="flagSelect; context: { $implicit: c, label: 'Has segments' }"
              />
            }
          }
        </fieldset>
      }
    </div>

    <button
      type="button"
      (click)="add()"
      class="mt-2 w-full rounded-lg border border-dashed border-border px-3 py-1.5 text-xs text-muted-foreground transition-colors hover:border-primary/50 hover:text-foreground"
    >
      + Add Condition
    </button>

    <ng-template #tagSelect let-c let-label="label">
      <select
        multiple
        [ngModel]="c.tagIds"
        (ngModelChange)="patch(c, { tagIds: $event })"
        [attr.aria-label]="label"
        [class]="fieldClass + ' h-20'"
      >
        @for (tag of tags(); track tag.id) {
          <option [value]="tag.id">{{ tag.name }}</option>
        }
      </select>
    </ng-template>

    <ng-template #countInput let-c let-label="label">
      <input
        type="number"
        min="0"
        step="1"
        [ngModel]="c.value"
        (ngModelChange)="patch(c, { value: $event })"
        [attr.aria-label]="label"
        [placeholder]="label"
        [class]="fieldClass"
      />
    </ng-template>

    <ng-template #textInput let-c let-label="label">
      <input
        type="text"
        [maxlength]="maxPatternLength"
        [ngModel]="c.text"
        (ngModelChange)="patch(c, { text: $event })"
        [attr.aria-label]="label"
        [placeholder]="label"
        [class]="fieldClass"
      />
    </ng-template>

    <ng-template #dateInput let-c let-label="label">
      <input
        type="date"
        [ngModel]="c.date"
        (ngModelChange)="patch(c, { date: $event ?? '' })"
        [attr.aria-label]="label"
        [class]="fieldClass"
      />
    </ng-template>

    <ng-template #flagSelect let-c let-label="label">
      <select
        [ngModel]="c.flag"
        (ngModelChange)="patch(c, { flag: $event })"
        [attr.aria-label]="label"
        [class]="fieldClass"
      >
        <option [ngValue]="true">Yes</option>
        <option [ngValue]="false">No</option>
      </select>
    </ng-template>
  `,
})
export class ConditionEditorComponent {
  readonly conditions = input.required<readonly ConditionDraft[]>();
  readonly tags = input<readonly TagInfo[]>([]);
  readonly sources = input<readonly SourceDirectoryInfo[]>([]);
  readonly simpleLists = input<readonly SimpleListDTO[]>([]);
  readonly smartLists = input<readonly SmartListDTO[]>([]);
  /** Criteria types this context cannot offer (e.g. smart lists referencing smart lists). */
  readonly excludedTypes = input<readonly CriteriaKind[]>([]);

  readonly conditionsChange = output<ConditionDraft[]>();

  protected readonly maxRating = MAX_RATING;
  protected readonly maxPatternLength = MAX_PATTERN_LENGTH;
  protected readonly fieldClass =
    'w-full rounded-lg border border-border bg-card px-2 py-1 text-xs text-foreground focus:outline-none focus:ring-1 focus:ring-primary';

  protected readonly groups = computed(() => {
    const excluded = new Set(this.excludedTypes());
    return CRITERIA_GROUPS.map((group) => ({
      ...group,
      options: group.options.filter((option) => !excluded.has(option.value)),
    })).filter((group) => group.options.length > 0);
  });

  protected complete(condition: ConditionDraft): boolean {
    return isComplete(condition);
  }

  protected add(): void {
    this.conditionsChange.emit([...this.conditions(), createCondition()]);
  }

  protected remove(condition: ConditionDraft): void {
    this.conditionsChange.emit(this.conditions().filter((c) => c.id !== condition.id));
  }

  protected setType(condition: ConditionDraft, type: CriteriaKind | ''): void {
    this.conditionsChange.emit(
      this.conditions().map((c) => (c.id === condition.id ? withType(c, type) : c)),
    );
  }

  protected toggleOperator(condition: ConditionDraft): void {
    this.patch(condition, { logicOperator: condition.logicOperator === 'AND' ? 'OR' : 'AND' });
  }

  protected patch(condition: ConditionDraft, changes: Partial<Omit<ConditionDraft, 'id'>>): void {
    this.conditionsChange.emit(updateCondition(this.conditions(), condition.id, changes));
  }
}
