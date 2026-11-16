import { HttpErrorResponse, HttpHeaders } from '@angular/common/http';
import { loginErrorMessage } from './auth.service';

function httpError(status: number, headers: Record<string, string> = {}, error: unknown = null) {
  return new HttpErrorResponse({ status, headers: new HttpHeaders(headers), error });
}

describe('loginErrorMessage', () => {
  it('reports a wrong PIN only for 401', () => {
    expect(loginErrorMessage(httpError(401))).toBe('Invalid PIN.');
  });

  it('includes the Retry-After delay for 429', () => {
    expect(loginErrorMessage(httpError(429, { 'Retry-After': '8' }))).toBe(
      'Too many attempts. Try again in 8 s.',
    );
    expect(loginErrorMessage(httpError(429, { 'Retry-After': '120' }))).toBe(
      'Too many attempts. Try again in 2 min.',
    );
    expect(loginErrorMessage(httpError(429))).toBe('Too many attempts. Try again later.');
  });

  it('distinguishes network and server errors from a wrong PIN', () => {
    expect(loginErrorMessage(httpError(0))).toContain('Cannot reach');
    expect(loginErrorMessage(httpError(503))).toBe('Server error (503). Try again.');
  });

  it('shows the server reason for other client errors', () => {
    expect(loginErrorMessage(httpError(400, {}, { error: true, reason: 'PIN too short' }))).toBe(
      'PIN too short',
    );
    expect(loginErrorMessage(new Error('boom'))).toBe('Unable to sign in. Try again.');
  });
});
