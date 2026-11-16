import { HttpClient } from '@angular/common/http';
import { inject } from '@angular/core';

/** Base path of the GridStream REST API. Only services build URLs from it. */
export const API_BASE = '/api/v1';

/**
 * Builds an API URL from a template literal, percent-encoding every
 * interpolated value: apiUrl`videos/${fileId}/stream`.
 */
export function apiUrl(strings: TemplateStringsArray, ...values: (string | number)[]): string {
  let path = strings[0];
  values.forEach((value, i) => {
    path += encodeURIComponent(String(value)) + strings[i + 1];
  });
  return `${API_BASE}/${path}`;
}

export abstract class ApiService {
  protected readonly http = inject(HttpClient);
}
