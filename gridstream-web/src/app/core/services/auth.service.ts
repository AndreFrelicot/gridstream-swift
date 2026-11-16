import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Injectable, computed, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';

import { apiUrl } from './api.service';

interface SessionResponse {
  authEnabled: boolean;
  authenticated: boolean;
  expiresAt: string | null;
}

@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly http = inject(HttpClient);
  private readonly state = signal<'checking' | 'locked' | 'authenticated'>('checking');
  private readonly authEnabledState = signal(false);
  private readonly errorState = signal<string | null>(null);

  readonly isChecking = computed(() => this.state() === 'checking');
  readonly isAuthenticated = computed(() => this.state() === 'authenticated');
  readonly isLocked = computed(() => this.state() === 'locked');
  readonly authEnabled = computed(() => this.authEnabledState());
  readonly error = computed(() => this.errorState());

  async initialize(): Promise<void> {
    await this.refreshSession();
  }

  async refreshSession(): Promise<void> {
    this.state.set('checking');
    this.errorState.set(null);

    try {
      const response = await firstValueFrom(
        this.http.get<SessionResponse>(apiUrl`auth/session`, { withCredentials: true }),
      );

      this.authEnabledState.set(response.authEnabled);
      this.state.set(response.authenticated ? 'authenticated' : 'locked');
    } catch {
      this.authEnabledState.set(true);
      this.state.set('locked');
      this.errorState.set('Unable to verify the current session.');
    }
  }

  async unlock(pin: string): Promise<boolean> {
    this.errorState.set(null);

    try {
      const response = await firstValueFrom(
        this.http.post<SessionResponse>(apiUrl`auth/login`, { pin }, { withCredentials: true }),
      );

      this.authEnabledState.set(response.authEnabled);
      this.state.set('authenticated');
      return true;
    } catch (error) {
      this.authEnabledState.set(true);
      this.state.set('locked');
      this.errorState.set(loginErrorMessage(error));
      return false;
    }
  }

  async logout(): Promise<void> {
    try {
      await firstValueFrom(
        this.http.post(apiUrl`auth/logout`, {}, { withCredentials: true, responseType: 'text' }),
      );
    } catch (error) {
      // The local session is dropped either way; the server cookie expires on its own.
      console.error('Logout request failed:', error);
    } finally {
      this.authEnabledState.set(true);
      this.state.set('locked');
    }
  }

  handleUnauthorized(): void {
    this.authEnabledState.set(true);
    this.state.set('locked');
    this.errorState.set('Session expired. Enter the PIN again.');
  }
}

/** Maps a failed login to a message that tells a wrong PIN apart from other failures. */
export function loginErrorMessage(error: unknown): string {
  if (!(error instanceof HttpErrorResponse)) {
    return 'Unable to sign in. Try again.';
  }
  if (error.status === 401) {
    return 'Invalid PIN.';
  }
  if (error.status === 429) {
    const seconds = retryAfterSeconds(error.headers.get('Retry-After'));
    return seconds !== null
      ? `Too many attempts. Try again in ${formatWait(seconds)}.`
      : 'Too many attempts. Try again later.';
  }
  if (error.status === 0) {
    return 'Cannot reach the GridStream server. Check that it is running.';
  }
  if (error.status >= 500) {
    return `Server error (${error.status}). Try again.`;
  }
  const reason = (error.error as { reason?: unknown } | null)?.reason;
  return typeof reason === 'string' && reason ? reason : 'Unable to sign in. Try again.';
}

/** Parses a Retry-After header given either as delta-seconds or as an HTTP date. */
function retryAfterSeconds(header: string | null): number | null {
  if (!header) return null;
  const trimmed = header.trim();
  if (/^\d+$/.test(trimmed)) return Number(trimmed);
  const date = Date.parse(trimmed);
  if (Number.isNaN(date)) return null;
  return Math.max(0, Math.ceil((date - Date.now()) / 1000));
}

function formatWait(seconds: number): string {
  if (seconds < 60) return `${seconds} s`;
  const minutes = Math.ceil(seconds / 60);
  return `${minutes} min`;
}
