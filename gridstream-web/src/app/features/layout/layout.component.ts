import { Component, inject } from '@angular/core';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';

import { AuthService } from '../../core/services/auth.service';

interface NavItem {
  label: string;
  route: string;
  queryParams?: Record<string, string>;
  icon: NavIcon;
}

type NavIcon = 'grid' | 'clock' | 'tag' | 'filter' | 'list' | 'folder' | 'aperture' | 'alert';

@Component({
  selector: 'app-layout',
  imports: [RouterOutlet, RouterLink, RouterLinkActive],
  template: `
    <div class="flex h-screen overflow-hidden">
      <!-- Sidebar -->
      <aside class="flex w-60 shrink-0 flex-col border-r border-border bg-card">
        <div class="flex h-16 items-center gap-2.5 px-4">
          <img
            src="app-icon.png"
            alt=""
            width="32"
            height="32"
            class="h-8 w-8 rounded-[9px] shadow-md shadow-black/40"
          />
          <h1 class="text-[17px] font-semibold tracking-tight text-foreground">GridStream</h1>
        </div>
        <nav class="flex-1 space-y-0.5 overflow-y-auto px-3 py-1">
          @for (item of navItems; track item.label) {
            <a
              [routerLink]="item.route"
              [queryParams]="item.queryParams"
              routerLinkActive="bg-primary/15 !text-primary"
              [routerLinkActiveOptions]="{ exact: item.route === '/library' }"
              class="flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground"
            >
              <svg
                class="h-4 w-4 shrink-0"
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                aria-hidden="true"
              >
                @switch (item.icon) {
                  @case ('grid') {
                    <svg:rect width="7" height="7" x="3" y="3" rx="1" />
                    <svg:rect width="7" height="7" x="14" y="3" rx="1" />
                    <svg:rect width="7" height="7" x="14" y="14" rx="1" />
                    <svg:rect width="7" height="7" x="3" y="14" rx="1" />
                  }
                  @case ('clock') {
                    <svg:circle cx="12" cy="12" r="10" />
                    <svg:polyline points="12 6 12 12 16 14" />
                  }
                  @case ('tag') {
                    <svg:path
                      d="M12.586 2.586A2 2 0 0 0 11.172 2H4a2 2 0 0 0-2 2v7.172a2 2 0 0 0 .586 1.414l8.704 8.704a2.426 2.426 0 0 0 3.42 0l6.58-6.58a2.426 2.426 0 0 0 0-3.42z"
                    />
                    <svg:circle cx="7.5" cy="7.5" r=".5" fill="currentColor" />
                  }
                  @case ('filter') {
                    <svg:path d="M3 6h18" />
                    <svg:path d="M7 12h10" />
                    <svg:path d="M10 18h4" />
                  }
                  @case ('list') {
                    <svg:path d="M11 12H3" />
                    <svg:path d="M16 6H3" />
                    <svg:path d="M16 18H3" />
                    <svg:path d="m19 10-4 4" />
                    <svg:path d="m15 10 4 4" />
                  }
                  @case ('folder') {
                    <svg:path
                      d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"
                    />
                  }
                  @case ('aperture') {
                    <svg:circle cx="12" cy="12" r="10" />
                    <svg:circle cx="12" cy="12" r="3" />
                    <svg:path d="M12 2v2" />
                    <svg:path d="M12 20v2" />
                    <svg:path d="m4.93 4.93 1.41 1.41" />
                    <svg:path d="m17.66 17.66 1.41 1.41" />
                    <svg:path d="M2 12h2" />
                    <svg:path d="M20 12h2" />
                    <svg:path d="m6.34 17.66-1.41 1.41" />
                    <svg:path d="m19.07 4.93-1.41 1.41" />
                  }
                  @case ('alert') {
                    <svg:path
                      d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"
                    />
                    <svg:path d="M12 9v4" />
                    <svg:path d="M12 17h.01" />
                  }
                }
              </svg>
              {{ item.label }}
            </a>
          }
        </nav>
        <div class="border-t border-border p-3">
          <button
            type="button"
            class="w-full rounded-full bg-secondary px-3 py-1.5 text-xs font-medium text-muted-foreground transition hover:bg-accent hover:text-foreground"
            (click)="logout()"
          >
            Logout
          </button>
        </div>
      </aside>

      <!-- Main content -->
      <main class="flex-1 overflow-y-auto">
        <router-outlet />
      </main>
    </div>
  `,
})
export class LayoutComponent {
  private readonly auth = inject(AuthService);

  navItems: NavItem[] = [
    { label: 'Content', route: '/library', icon: 'grid' },
    { label: 'History', route: '/library', queryParams: { history: '' }, icon: 'clock' },
    { label: 'Tags', route: '/tags', icon: 'tag' },
    { label: 'Smart Lists', route: '/smart-lists', icon: 'filter' },
    { label: 'Simple Lists', route: '/simple-lists', icon: 'list' },
    { label: 'Sources', route: '/sources', icon: 'folder' },
    { label: 'Captures', route: '/captures', icon: 'aperture' },
    { label: 'Scrub Issues', route: '/scrub-issues', icon: 'alert' },
  ];

  protected async logout(): Promise<void> {
    await this.auth.logout();
  }
}
