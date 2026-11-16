# API contract decisions

The rules the macOS server, the iPad app and the web UI follow when they exchange data over `/api/v1`. The Swift side implements them once, in `GridStreamKit`; the web UI follows the same shapes. The payloads in `fixtures/` are the reference examples both Swift apps are tested against.

## 1. Dates

- **Wire format emitted by everyone:** ISO 8601 UTC. Swift encoders use `.iso8601` (no fractional seconds). Web uses `Date.prototype.toISOString()` (fractional milliseconds).
- **Server decoding is tolerant** (one shared helper, used for `criteria` and every other place that currently sets `.iso8601`). It accepts, in order:
  1. ISO 8601 with fractional seconds,
  2. ISO 8601 without fractional seconds,
  3. date-only `YYYY-MM-DD` → start of that day in the server's current time zone,
  4. a JSON number → `Date(timeIntervalSinceReferenceDate:)` (legacy iPad `JSONEncoder` default, `.deferredToDate`).
- iPad decoding of criteria uses the same tolerant strategy (copy of the helper until GridStreamKit exists).
- Web date inputs convert `YYYY-MM-DD` to a full ISO string before sending.

## 2. Smart list criteria

- `ServerFilterCondition.id`: a non-UUID string is accepted and replaced by a fresh UUID on decode (web previously sent `Math.random()` ids). Clients must send `crypto.randomUUID()` / `UUID()`.
- Ratings in criteria are integers 0…10. Server accepts a JSON number with a fraction and rounds it; web inputs use `step="1"`.
- `tagRatings` with duplicate `tagId`: last one wins (`Dictionary(_:uniquingKeysWith:)`), never trap.
- Numeric bounds are validated (size in MB 0…10_000_000, durations ≥ 0, regex/text patterns ≤ 256 chars). Out of range → 400.
- **Smart list create/update validates `criteria`** with the tolerant decoder and stores it **re-encoded in canonical form** (ISO dates without fraction, UUID ids). Invalid → 400 with a reason. A new migration re-normalizes existing stored criteria best-effort (rows that cannot be decoded are left untouched and logged).
- `GET /videos` with `criteria` **and** flat filters (`search`, `played`, `videos`, `simpleListIds`, …): the server returns the **intersection**. Flat params are no longer ignored.
- Deleting a tag removes its id from every smart list's criteria **server-side** inside the same transaction (`TagRoutes.delete`). Clients stop doing this themselves.

## 3. Simple list `sortOrder`

- Canonical values are **snake_case**: `filename`, `filename_desc`, `file_size`, `file_size_desc`, `play_count`, `play_count_desc`, `play_time`, `play_time_desc`, `date_added`, `date_added_desc`.
- Server validates on create/update, maps camelCase aliases (`filenameDesc` → `filename_desc`, …) to canonical, rejects unknown values with 400. A migration normalizes existing rows.
- iPad decoder is tolerant: accepts both spellings, unknown → `.filename` (never fails the whole list).
- Web `<option value>` uses the canonical snake_case values.

## 4. Video tags

- `POST /api/v1/videos/:id/tags` keeps **replace** semantics (full set) for editors that hold the complete, freshly loaded set.
- New **additive** single-tag endpoint: `POST /api/v1/videos/:id/tags/:tagId` (idempotent attach, 200 with the video's tag list). Detach stays `DELETE /api/v1/videos/:id/tags/:tagId`.
- New **bulk** endpoint: `POST /api/v1/tags/apply` with body `{ "fileIds": [String], "addTagIds": [UUID], "removeTagIds": [UUID] }`. One transaction, one catalog-version bump, unknown fileIds/tagIds → 400. Response `{ "updated": Int }`.
- iPad: bulk tagging uses `/tags/apply` (add only); tag toggles use attach/detach, never the replace endpoint with a stale set.

## 5. Video existence / lookup

- Clients check existence with `GET /api/v1/videos/by-file-id/:fileId` (200 present, 404 absent, anything else = transient, keep the tile). It returns a single `VideoItem` (web type fixed accordingly).
- `GET /api/v1/videos` has no `fileId` filter; clients must not rely on one.

## 6. Thumbnails

- Clients use the server-provided `thumbnailUrl` (versioned with `?v=`), resolved against the server base URL. Client caches key on the URL **without** the auth token query item (see §7).

## 7. Authentication and media access (security hardening)

- **Auth is on by default.** On first launch (or on upgrade when no PIN exists), the server generates a random 6-digit PIN, enables auth and shows the PIN in the menu bar UI / settings. The user may disable auth explicitly; the UI then shows a persistent warning.
- New PINs must be ≥ 6 digits. Existing shorter PINs keep working until changed.
- Login is rate-limited: per client IP exponential backoff after 3 failures (1 s doubling, capped at 15 min) plus a global cap (≥ 20 failures/min → 60 s global lockout). Responses: 429 with `Retry-After`. Bcrypt runs off the cooperative pool (`app.threadPool`).
- Tokens carry a `jti`; logout records the jti in a persisted revocation list (pruned at expiry). `revokeAll` / PIN change keep the existing `pinRevision` mechanism.
- **Media routes require a session when auth is enabled**: `GET /videos/:id/stream`, `GET /videos/:id/thumbnail`, `GET /videos/:id/scrub/frame`, `GET /videos/:id/scrub/cached-times`, `GET /captures/:captureId/image`. Accepted credentials, in order: `Authorization: Bearer`, session cookie, `token` query item. 401 otherwise. (AVPlayer/AsyncImage on iPad use the `token` query item; the web relies on the same-origin cookie.)
- Request logging must not print the `token` query item.
- When auth is **disabled**, the server rejects requests whose `Host` header is not an IP literal, `localhost`, a `*.local` name, or the machine's own host names (DNS-rebinding guard).
- `exact=true` on scrub frames and any write-triggering media request require a session even if the route is otherwise readable; `time` is validated `0 ≤ time ≤ duration`.
- Release builds run Vapor in `.production` (no error details in responses).
- Security headers on every response: `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, `X-Frame-Options: DENY`; on the SPA HTML also a CSP: `default-src 'self'; img-src 'self' data: blob:; media-src 'self' blob:; style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'`. The web build must not emit inline scripts or inline event handlers (disable Angular critical-CSS inlining if needed).
- iPad uses a dedicated `URLSession` with `httpShouldSetCookies = false` and no cookie storage; the Bearer token lives only in the Keychain.

## 8. Bonjour

- Service type becomes **`_gridstream._tcp.`** (server `BonjourService`, iPad `ServerDiscoveryService`, iPad `Info.plist` `NSBonjourServices`). The TXT record keeps whatever it already carries.
- iPad `DiscoveredServer` equality/identity is `name + host + port`, not a per-resolution UUID.

## 9. Request hygiene

- `limit` is clamped to 1…10_000 (default unchanged), negative `offset` → 400.
- `addViewTime` is clamped to 0…86_400 per report; counters use overflow-safe addition.
- Clients percent-encode `+` in query strings (`%2B`).
