import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';

import { App } from './app';

describe('App', () => {
  let fixture: ComponentFixture<App>;
  let http: HttpTestingController;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [App],
      providers: [provideRouter([]), provideHttpClient(), provideHttpClientTesting()],
    }).compileComponents();

    fixture = TestBed.createComponent(App);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => http.verify());

  async function resolveSession(body: object): Promise<HTMLElement> {
    fixture.detectChanges();
    const request = http.expectOne('/api/v1/auth/session');
    expect(request.request.method).toBe('GET');
    expect(request.request.withCredentials).toBe(true);
    request.flush(body);
    await fixture.whenStable();
    fixture.detectChanges();
    return fixture.nativeElement as HTMLElement;
  }

  it('shows the session check until the server answers', () => {
    fixture.detectChanges();
    expect((fixture.nativeElement as HTMLElement).textContent).toContain('Checking session');
    http.expectOne('/api/v1/auth/session').flush({
      authEnabled: true,
      authenticated: false,
      expiresAt: null,
    });
  });

  it('renders the lock screen when the session is not authenticated', async () => {
    const element = await resolveSession({
      authEnabled: true,
      authenticated: false,
      expiresAt: null,
    });
    expect(element.querySelector('h1')?.textContent).toContain('Unlock this device');
    expect(element.querySelector('router-outlet')).toBeNull();
  });

  it('renders the router outlet when the session is authenticated', async () => {
    const element = await resolveSession({
      authEnabled: true,
      authenticated: true,
      expiresAt: '2030-01-01T00:00:00Z',
    });
    expect(element.querySelector('router-outlet')).not.toBeNull();
    expect(element.querySelector('app-lock-screen')).toBeNull();
  });
});
