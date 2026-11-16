import { FormsModule } from '@angular/forms';
import { Component, inject, signal } from '@angular/core';

import { AuthService } from '../../core/services/auth.service';

@Component({
  selector: 'app-lock-screen',
  imports: [FormsModule],
  template: `
    <div class="flex min-h-screen items-center justify-center bg-[radial-gradient(circle_at_top,rgba(235,89,13,0.28),transparent_45%)] bg-background px-6 text-foreground">
      <div class="w-full max-w-md rounded-3xl border border-border bg-card p-8 shadow-2xl shadow-black/50">
        <div class="mb-8">
          <img
            src="app-icon.png"
            alt=""
            width="64"
            height="64"
            class="h-16 w-16 rounded-2xl shadow-lg shadow-black/40"
          />
          <p class="mt-5 text-sm font-semibold text-primary">GridStream</p>
          <h1 class="mt-1 text-3xl font-semibold text-foreground">Unlock this device</h1>
          <p class="mt-2 text-sm text-muted-foreground">
            Enter the server PIN to continue. The browser will remember this device until the session expires.
          </p>
        </div>

        <form class="space-y-4" (ngSubmit)="submit()">
          <label class="block">
            <span class="mb-2 block text-sm text-muted-foreground">PIN</span>
            <input
              [(ngModel)]="pin"
              name="pin"
              type="password"
              inputmode="numeric"
              autocomplete="current-password"
              class="w-full rounded-xl border border-border bg-secondary px-4 py-3 text-lg tracking-[0.35em] text-foreground outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/30"
              placeholder="000000"
            />
          </label>

          @if (auth.error(); as error) {
            <p class="text-sm text-destructive">{{ error }}</p>
          }

          <button
            type="submit"
            class="bg-brand w-full rounded-full px-4 py-3 font-semibold text-white transition hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-60"
            [disabled]="submitting() || !pin.trim()"
          >
            {{ submitting() ? 'Unlocking...' : 'Unlock' }}
          </button>
        </form>
      </div>
    </div>
  `,
})
export class LockScreenComponent {
  protected readonly auth = inject(AuthService);
  protected readonly submitting = signal(false);
  protected pin = '';

  protected async submit(): Promise<void> {
    if (!this.pin.trim() || this.submitting()) {
      return;
    }

    this.submitting.set(true);
    const unlocked = await this.auth.unlock(this.pin.trim());
    this.submitting.set(false);

    if (unlocked) {
      this.pin = '';
    }
  }
}
