import { Routes } from '@angular/router';

export const routes: Routes = [
  {
    path: '',
    loadComponent: () =>
      import('./features/layout/layout.component').then((m) => m.LayoutComponent),
    children: [
      { path: '', redirectTo: 'library', pathMatch: 'full' },
      {
        path: 'library',
        loadComponent: () =>
          import('./features/content-library/content-library.component').then(
            (m) => m.ContentLibraryComponent,
          ),
      },
      {
        path: 'history',
        loadComponent: () =>
          import('./features/history/history.component').then((m) => m.HistoryComponent),
      },
      {
        path: 'tags',
        loadComponent: () => import('./features/tags/tags.component').then((m) => m.TagsComponent),
      },
      {
        path: 'smart-lists',
        loadComponent: () =>
          import('./features/smart-lists/smart-lists.component').then((m) => m.SmartListsComponent),
      },
      {
        path: 'simple-lists',
        loadComponent: () =>
          import('./features/simple-lists/simple-lists.component').then(
            (m) => m.SimpleListsComponent,
          ),
      },
      {
        path: 'sources',
        loadComponent: () =>
          import('./features/sources/sources.component').then((m) => m.SourcesComponent),
      },
      {
        path: 'captures',
        loadComponent: () =>
          import('./features/captures/captures.component').then((m) => m.CapturesComponent),
      },
      {
        path: 'scrub-issues',
        loadComponent: () =>
          import('./features/scrub-issues/scrub-issues.component').then(
            (m) => m.ScrubIssuesComponent,
          ),
      },
    ],
  },
  { path: '**', redirectTo: '' },
];
