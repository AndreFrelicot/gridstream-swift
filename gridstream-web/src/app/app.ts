import { Component, OnInit, inject } from '@angular/core';
import { RouterOutlet } from '@angular/router';

import { LockScreenComponent } from './features/auth/lock-screen.component';
import { AuthService } from './core/services/auth.service';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, LockScreenComponent],
  template: `
    <div class="min-h-screen bg-background text-foreground">
      @if (auth.isChecking()) {
        <div class="flex min-h-screen items-center justify-center">
          <p class="text-sm uppercase tracking-[0.2em] text-muted-foreground">Checking session...</p>
        </div>
      } @else if (auth.isAuthenticated()) {
        <router-outlet />
      } @else {
        <app-lock-screen />
      }
    </div>
  `,
})
export class App implements OnInit {
  protected readonly auth = inject(AuthService);

  async ngOnInit(): Promise<void> {
    await this.auth.initialize();
  }
}
