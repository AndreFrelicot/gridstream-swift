# Security

GridStream is **experimental software**. It is meant for a trusted local network (a studio, an office, a home LAN). It has not been through a professional security audit or penetration test. Do not expose the server to the Internet.

## Threat model

The macOS app runs an HTTP server (default port `8080`) that serves your video library, its metadata (tags, ratings, lists, annotations, captures) and the web UI. The iPad app and browsers on the same network are its clients.

GridStream tries to protect against:

- other devices on the same network browsing or streaming your library without the PIN;
- PIN guessing (rate limiting);
- web pages you visit reaching the server through your browser (DNS rebinding, cross-site framing).

It does **not** protect against:

- **network eavesdropping.** Traffic is plain HTTP, so anyone who can capture packets on your network can read the PIN at login, session tokens and video data. Use a network you trust.
- a compromised Mac or iPad;
- other user accounts on the same Mac reading the app's data directory.

## What the server does

- **Authentication is on by default.**
  - On first launch the server generates a random 6-digit PIN and shows it in the menu bar app.
  - New PINs must have at least 6 digits.
  - You can turn authentication off. The app then shows a persistent warning.
- **Sessions.**
  - Logging in returns a signed token (HMAC-SHA256) with an expiry and a unique id.
  - Logging out revokes that id.
  - Changing the PIN revokes every session.
- **Login rate limiting.**
  - Per client, an exponential backoff starts after 3 failures and is capped at 15 minutes.
  - A global lockout applies under sustained failures.
  - Blocked attempts get HTTP 429 with `Retry-After`.
- **Media routes need a session too** (stream, thumbnail, scrub frames, capture images). Players that cannot send headers pass the token as a `token` query item, and the server never logs it.
- **When authentication is off,** requests whose `Host` header is not an IP address, `localhost`, a `.local` name or the Mac's own host name are rejected. This guards against DNS rebinding.
- **Response headers.**
  - All responses carry `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer` and `X-Frame-Options: DENY`.
  - The web UI also gets a strict Content-Security-Policy.
- **Release builds** run in production mode, so error responses carry no internal details.
- **File access.**
  - Files are served only from the folders you added, through macOS security-scoped bookmarks.
  - Videos are looked up by id in the catalog. The server never accepts a file path from a client.

## What the clients do

- **iPad:**
  - The session token lives in the Keychain (this device only).
  - API traffic uses an ephemeral session with no cookie storage.
  - Tokens are stripped from logs and cache keys.
- **Web:** the session is an `HttpOnly`, `SameSite=Strict` cookie on the server's own origin.

## Reporting a vulnerability

Please report security issues privately through GitHub's "Report a vulnerability" button (private security advisories) on the repository, not in a public issue. Include steps to reproduce and the versions you tested. This is a spare-time project: expect a best-effort response.
