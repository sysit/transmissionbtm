# 03 — HTTP Server, UPnP/DLNA & SSDP

## Overview

This domain implements a custom, embedded HTTP server serving torrent file content for streaming and UPnP/DLNA media server functionality. All networking is built from scratch on Java `ServerSocket`/`Socket` with raw byte-level HTTP parsing — no third-party HTTP libraries. The SSDP module handles UPnP device discovery via multicast UDP.

Key ports: 9091 (Transmission RPC/web UI, native), 9092 (Java HTTP server, configurable), 1900 (SSDP multicast).

---

## File Inventory

| File | Lines | Purpose |
|------|-------|---------|
| `http/HttpServer.java` | 26 | Interface: start/stop/port/isRunning + Transmission access |
| `http/SimpleHttpServer.java` | 249 | Concrete: ServerSocket, thread-pool dispatching, handler routing |
| `http/Request.java` | 236 | Raw HTTP request parsing from InputStream |
| `http/Response.java` | 75 | Interface + static singletons: 400/404/405/413/500/503/505 |
| `http/Range.java` | 53 | Byte range alignment, satisfiability, length |
| `http/Method.java` | 24 | Enum: GET, POST, HEAD |
| `http/HttpVersion.java` | 27 | Enum: HTTP/1.0, HTTP/1.1 |
| `http/RequestHandler.java` | 10 | Single-method: `handle(HttpServer, Request, Socket)` |
| `handlers/HandlerBase.java` | 211 | Abstract base: 200/206/416 response construction, debug logging |
| `handlers/AssetHandler.java` | 48 | Serves from Android AssetManager (UPnP SCPD XML) |
| `handlers/StaticResourceHandler.java` | 95 | Abstract: static file serving with range + HEAD |
| `handlers/SoapHandler.java` | 199 | Generic SOAP 1.1 parser/dispatcher for UPnP control |
| `handlers/torrent/TorrentHandler.java` | 278 | Torrent file HTTP streaming (complete + incomplete) |
| `handlers/torrent/PlaylistHandler.java` | 197 | M3U playlist generation for torrent media |
| `handlers/upnp/ContentDirectoryHandler.java` | 275 | UPnP ContentDirectory:1 Browse, DIDL-Lite XML |
| `handlers/upnp/DescriptorHandler.java` | 122 | UPnP device descriptor XML, handler registration |
| `ssdp/SsdpServer.java` | 215 | SSDP: M-SEARCH response, NOTIFY alive/byebye, multicast on 239.255.255.250:1900 |
| `assets/upnp/ConnectionManagerScpd.xml` | 132 | UPnP ConnectionManager:1 SCPD |
| `assets/upnp/ContentDirectoryScpd.xml` | 148 | UPnP ContentDirectory:1 SCPD |

---

## 1. HTTP Server Architecture

### 1.1 Lifecycle

**Start**: UPnP ON → `ServerSocket(9092)` on all interfaces. UPnP OFF → `ServerSocket(0)` on 127.0.0.1 only. Accept loop runs on shared `Transmission.getExecutor()`.

**Stop**: Close `ServerSocket` → accept loop exits via `SocketException`.

### 1.2 Threading

Accept thread + one handler thread per connection (from shared executor pool). Optional watchdog thread monitors input stream for unexpected close.

### 1.3 Request Parsing (Request.read)

Byte-by-byte `readLine()` → split into method/path/version → validate via enums → read headers (Host, Content-Length, Range) → read body (capped at 512KB). Range supports `bytes=-N`, `bytes=N-`, `bytes=N-M`.

### 1.4 Handler Dispatch

`rootHandlers`: `/torrent` → TorrentHandler, `/playlist` → PlaylistHandler
`handlers`: 4 UPnP paths mapped to DescriptorHandler, AssetHandler (×2), ContentDirectoryHandler

### 1.5 Response Construction

All byte-level, no keep-alive. `responseOk(type, len)` → 200. `responsePartial(type, len, start, end, total)` → 206 with Content-Range. `responseNotSatisfiable(total)` → 416. Seven error singletons.

---

## 2. Handler Catalog

### TorrentHandler (`/torrent/<hash>/<fileIdx>[.<ext>]`)

Streams torrent file data. PIECE_MARGIN=20MB, SLEEP=1000ms, max 300 retries (5 min). Complete files: FileInputStream streaming. Incomplete files: `TorrentFile.read()` piece-by-piece with margin. Switches to file streaming when complete. IPv6-safe URI construction.

### PlaylistHandler (`/playlist/[<hash>[/<folderIdx>]].m3u`)

MIME: `audio/mpegurl`. Three modes: master (all torrents), per-torrent, per-folder. `#EXTM3U` + `#EXTINF:-1,<title>` + TorrentHandler URLs. Sorted with NaturalOrderComparator.

### SoapHandler

SOAP 1.1: `http://schemas.xmlsoap.org/soap/envelope/`. `Map<String, MessageHandler>` by action name. POST only. Parse XML → dispatch → serialize response. No handler → SOAP fault.

### AssetHandler / StaticResourceHandler

AssetHandler serves from AssetManager. StaticResourceHandler: abstract `open()` + `getContentType()`, range support, HEAD support, content length caching.

---

## 3. UPnP/DLNA Media Server

### 3.1 Device Descriptor

`deviceType`: `urn:schemas-upnp-org:device:MediaServer:1`. `friendlyName`: `Transmission BTC (<ip>)`. `UDN`: `uuid:<random>`. `dlna:X_DLNADOC`: `DMS-1.50`. Two services: ContentDirectory:1 + ConnectionManager:1.

### 3.2 ContentDirectory (Browse Only)

**ObjectID resolution**: `"0"`/`"-1"` = root (TorrentFs), others via `TorrentFs.findItem()`.

**DIDL-Lite containers**: `object.container.storageFolder` with dc:title, childCount.

**DIDL-Lite items**: `<res protocolInfo="http-get:*:<mime>:DLNA.ORG_OP=01" size="<bytes>" [duration/resolution]>` with URL to TorrentHandler. UPnP class mapped: video→videoItem.movie, audio→audioItem.musicTrack, image→imageItem.photo, text→textItem, playlist→playlist.

**Metadata enrichment**: MediaInfo provides title, artist, album, genre, date, duration, resolution — overriding file-extension-based MIME when available.

### 3.3 ConnectionManager

Declared in descriptor but no Java handler — control URL returns 404. GetProtocolInfo not implemented.

---

## 4. SSDP Discovery

| Parameter | Value |
|-----------|-------|
| Multicast addr | 239.255.255.250:1900 |
| NOTIFY interval | 60s |
| Cache-Control | max-age=1800 (30 min) |
| Server | Transmission BTC UPnP/1.0 |
| ST | urn:schemas-upnp-org:device:MediaServer:1 |

Messages: M-SEARCH → unicast 200 OK with Location header. NOTIFY alive (multicast every 60s). NOTIFY byebye (multicast on stop). Suspension-aware: ignores M-SEARCH and skips NOTIFY when suspended.

---

## 5. Key Data Flows

**UPnP Discovery → Media Playback:**
SSDP M-SEARCH → 200 OK (Location) → GET descriptor.xml → GET SCPD → POST Browse → DIDL-Lite with TorrentHandler URLs → GET /torrent/<hash>/<idx>.mp4 → TorrentHandler streams

**Torrent Streaming:**
Parse hash+fileIdx → lookup TorrentFile → check DnD → if complete: FileInputStream → if incomplete: piece-by-piece via Native.torrentGetPiece() → switch to file streaming on completion

---

## 6. Platform-Specific API → HarmonyOS Mapping

| Android API | HarmonyOS Equivalent |
|---|---|
| `ServerSocket/Socket` (java.net) | `@ohos.net.socket` |
| `MulticastSocket/DatagramSocket` | `@ohos.net.socket.MulticastSocket` |
| `AssetManager` | `@ohos.resourceManager` |
| `MimeTypeMap` | Custom mapping or `@ohos.utils.uri.URI` |
| `DocumentBuilder` (javax.xml) | `@ohos.xml` |
| `Transformer` (javax.xml.transform) | `@ohos.org.w3c.dom.ls` |
| `ExecutorService/ScheduledExecutorService` | `@ohos.taskpool` or java.util.concurrent |
| `FileInputStream` | `@ohos.file.fs` |
| `ByteBuffer` | java.nio.ByteBuffer (available) |

---

## 7. Configuration

| Pref Key | Default | Effect |
|----------|---------|--------|
| `ENABLE_UPNP` | false | Enables UPnP + SSDP, binds to all interfaces |
| `HTTP_SERVER_PORT` | 9092 | HTTP server port (UPnP mode only) |
| `UUID` | Auto-generated | UPnP device UDN (persisted) |
