import { Component, input, output } from '@angular/core';

/** Error state with a Retry button, shown instead of an empty state when a load failed. */
@Component({
  selector: 'app-load-error',
  host: { class: 'flex flex-col items-center justify-center gap-3 py-8', role: 'alert' },
  template: `
    <div class="text-sm text-destructive">{{ message() }}</div>
    <button
      type="button"
      (click)="retry.emit()"
      class="rounded-full bg-secondary px-3 py-1.5 text-xs text-secondary-foreground transition hover:bg-secondary/80"
    >
      Retry
    </button>
  `,
})
export class LoadErrorComponent {
  readonly message = input.required<string>();
  readonly retry = output<void>();
}
