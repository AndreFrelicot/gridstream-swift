import { Component, OnInit, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { SourceDirectoryService } from '../../core/services/source-directory.service';
import { SourceDirectoryInfo } from '../../core/models/source-directory.model';
import { LoadErrorComponent } from '../../shared/ui/load-error.component';

@Component({
  selector: 'app-sources',
  imports: [RouterLink, LoadErrorComponent],
  template: `
    <div class="min-h-screen bg-background p-6">
      <div class="max-w-7xl mx-auto">
        <h1 class="text-3xl font-bold text-foreground mb-8">Source Directories</h1>

        @if (loading()) {
          <div class="flex justify-center items-center h-64">
            <div class="text-muted-foreground">Loading sources...</div>
          </div>
        } @else if (loadError()) {
          <app-load-error [message]="loadError()!" (retry)="loadSources()" />
        } @else if (sources().length === 0) {
          <div class="flex flex-col items-center justify-center h-64 text-center">
            <div class="text-2xl text-muted-foreground mb-2">No source directories configured</div>
            <div class="text-muted-foreground/70">Add source directories to get started</div>
          </div>
        } @else {
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            @for (source of sources(); track source.id) {
              <a
                routerLink="/library"
                [queryParams]="{ source: source.id }"
                class="block p-6 bg-card rounded-2xl hover:bg-secondary cursor-pointer transition border border-border hover:border-primary/50 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
              >
                <h3 class="text-xl font-semibold text-foreground mb-2">{{ source.name }}</h3>
                @if (source.path) {
                  <p class="text-sm text-muted-foreground truncate">{{ source.path }}</p>
                }
                <div
                  class="mt-4 inline-block px-3 py-1 bg-secondary rounded-full text-xs text-secondary-foreground"
                >
                  Browse
                </div>
              </a>
            }
          </div>
        }
      </div>
    </div>
  `,
})
export class SourcesComponent implements OnInit {
  private sourceDirectoryService = inject(SourceDirectoryService);

  sources = signal<SourceDirectoryInfo[]>([]);
  loading = signal(false);
  loadError = signal<string | null>(null);

  ngOnInit() {
    this.loadSources();
  }

  loadSources() {
    this.loading.set(true);
    this.loadError.set(null);
    this.sourceDirectoryService.getSourceDirectories().subscribe({
      next: (sources) => {
        this.sources.set(sources);
        this.loading.set(false);
      },
      error: (err: unknown) => {
        console.error('Failed to load source directories:', err);
        this.sources.set([]);
        this.loadError.set('Could not load source directories.');
        this.loading.set(false);
      },
    });
  }
}
