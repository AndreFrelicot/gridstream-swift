# GridStream macOS Server - Manual Testing Guide

This document provides a checklist for manually verifying the functionality of the GridStream macOS server application.

## Prerequisites

- macOS 15.6 or later
- Xcode 26 or later (validated with 26.3)
- Sample video files (.mp4, .m4v, .mov)
- Terminal access for curl commands

## Test Checklist

### 1. Application Launch

- [ ] Build and run the application from Xcode
- [ ] Verify app appears in menu bar with server icon
- [ ] Verify app appears in the Dock and the menu bar
- [ ] Click menu bar icon to open dropdown menu

### 2. Source Directory Management

#### Add Directory
- [ ] Click "Configure Sources..." to open Settings window
- [ ] Click the "+" button to add a source directory
- [ ] Select a folder containing video files
- [ ] Verify the directory appears in the list
- [ ] Verify the directory shows as "Enabled" by default

#### Toggle Directory
- [ ] Click the toggle switch to disable a directory
- [ ] Verify the toggle reflects the disabled state
- [ ] Re-enable the directory

#### Remove Directory
- [ ] Click the remove button (trash icon) on a directory
- [ ] Verify the directory is removed from the list

### 3. Video Scanning

- [ ] Add at least one directory with video files
- [ ] Click "Rescan Videos" button
- [ ] Verify progress indicator appears during scan
- [ ] Verify video count updates in menu bar after scan completes
- [ ] Check Console.app for scan completion log messages

### 4. Server Controls

#### Start Server
- [ ] Click "Start Server" in the menu bar dropdown
- [ ] Verify status changes to "Server Running" (green indicator)
- [ ] Verify port number is displayed

#### Stop Server
- [ ] Click "Stop Server"
- [ ] Verify status changes to "Server Stopped" (red indicator)

### 5. API Testing with curl

Start the server before running these tests. Default port is 8080. Authentication is on by default; the PIN is shown in the menu bar window.

#### Health Check (No Auth Required)
```bash
curl -v http://localhost:8080/api/v1/health
```
Expected: HTTP 200 with JSON `{"status":"ok","version":"1.0"}`

#### Log In
```bash
TOKEN=$(curl -s -X POST -H 'Content-Type: application/json' -d '{"pin":"YOUR_PIN"}' http://localhost:8080/api/v1/auth/login | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')
```
Expected: a token in `$TOKEN`. A wrong PIN returns 401; after 3 failures the server answers 429 with a `Retry-After` header.

#### Video List (Auth Required)
```bash
curl -v -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/videos
```
Expected: HTTP 200 with JSON containing a videos array

#### Authentication Rejection
```bash
curl -v http://localhost:8080/api/v1/videos
curl -v "http://localhost:8080/api/v1/videos?token=$TOKEN"
```
Expected: HTTP 401 for both (metadata routes do not accept the query token)

#### Single Video Metadata
Replace `FILE_ID` with a `fileId` from the list endpoint:
```bash
curl -v -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/videos/by-file-id/FILE_ID
```
Expected: HTTP 200 with the video's metadata

#### Video Streaming (Full File)
Media routes accept the Bearer header, the session cookie or a `token` query item:
```bash
curl -v "http://localhost:8080/api/v1/videos/FILE_ID/stream?token=$TOKEN" -o test_download.mp4
```
Expected: HTTP 200, video file downloaded. Without a token: HTTP 401.

### 6. Byte-Range Streaming

#### Partial Content Request
```bash
curl -v -H "Authorization: Bearer $TOKEN" -H "Range: bytes=0-1023" http://localhost:8080/api/v1/videos/FILE_ID/stream -o partial.dat
```
Expected:
- HTTP 206 Partial Content
- Content-Range header present (e.g., `bytes 0-1023/TOTAL_SIZE`)
- 1024 bytes downloaded

#### Different Range
```bash
curl -v -H "Authorization: Bearer $TOKEN" -H "Range: bytes=1000-1999" http://localhost:8080/api/v1/videos/FILE_ID/stream -o partial2.dat
```
Expected: HTTP 206 with appropriate Content-Range

### 7. Bonjour Discovery

#### Verify Service Advertisement
With the server running, open a new terminal and run:
```bash
dns-sd -B _gridstream._tcp
```
Expected: the GridStream service appears in the list

#### Browse Service Details
```bash
dns-sd -L GridStream _gridstream._tcp local
```
Expected: Shows hostname and port information

### 8. iPad Testing (if available)

- [ ] Ensure iPad and Mac are on the same network
- [ ] Open the GridStream iPad app: it should list the Mac and ask for the PIN
- [ ] Play a few videos in the grid and scrub them

### 9. Error Handling

#### Unknown Video
```bash
curl -v -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/videos/does-not-exist/stream
```
Expected: HTTP 404 Not Found

#### Log Out
```bash
curl -v -X POST -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/auth/logout
curl -v -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/videos
```
Expected: the second request returns 401 (the token is revoked)

### 10. Port Configuration

- [ ] Open Settings window
- [ ] Change port number (e.g., to 9090)
- [ ] Stop and restart the server
- [ ] Verify server responds on new port:
```bash
curl -v http://localhost:9090/api/v1/health
```

### 11. Console Logging

Open Console.app and filter for "com.gridstream.macos" to monitor:
- [ ] Server start/stop events
- [ ] Scan completion statistics
- [ ] Any warnings or errors during operation

## Troubleshooting

### Server Won't Start
- Check if the port is already in use: `lsof -i :8080`
- Try a different port number

### Videos Not Found
- Ensure source directories are enabled
- Click "Rescan Videos" after adding directories
- Check Console.app for scan errors

### Bonjour Not Working
- Ensure "Local Network" permission is granted in System Preferences
- Check firewall settings

### Authentication Issues
- Use the PIN shown in the menu bar window; changing it revokes every session
- Send `Authorization: Bearer <token>` on metadata routes; the `token` query item only works on media routes
- After repeated wrong PINs, wait for the `Retry-After` delay

## Performance Notes

- Target scrubbing latency: <30ms
- Target concurrent streams: 9+
- Test with multiple simultaneous curl requests to verify concurrency
