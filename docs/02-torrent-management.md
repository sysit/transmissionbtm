# 02 -- Torrent Management

## Overview

The Torrent Management domain provides the Java-side abstraction layer over the native Transmission C library (`libtransmission`). It models torrents as composable hierarchical file trees, manages their lifecycle (add, remove, start, stop, verify), reports download statistics and status, tracks media metadata, and bridges all operations to JNI.

The domain is responsible for:

- Modeling the torrent file/directory hierarchy via `TorrentItem` / `TorrentItemContainer` interfaces
- Managing per-torrent state, status and statistics (`TorrentStat`)
- Translating Java API calls into `Native.*` JNI calls for the C library
- Configuring and managing the Transmission daemon session (`Transmission.java`)
- Watch directory auto-import of `.torrent` files via `FileObserver`
- Media file type detection and metadata extraction (`MediaInfo`)
- Exception types for domain-specific error conditions

---

## File Inventory

| File | Lines | Purpose |
|------|-------|---------|
| `torrent/Torrent.java` | 625 | Main torrent entity -- file tree, lifecycle ops, JNI bridge |
| `torrent/TorrentFile.java` | 482 | Single file within torrent -- stat, progress, piece-level reading |
| `torrent/TorrentDir.java` | 222 | Directory node -- hierarchical children, recursive operations |
| `torrent/TorrentItem.java` | 19 | Interface -- common item contract |
| `torrent/TorrentItemContainer.java` | 11 | Interface -- directory-like containers with `ls()` |
| `torrent/TorrentFs.java` | 258 | Filesystem root -- session-level torrent listing, caching |
| `torrent/Transmission.java` | 685 | Session management -- lifecycle, add/remove, watch dirs, executors |
| `torrent/TorrentStat.java` | 67 | Status/statistics -- typed access to stat arrays |
| `torrent/MediaInfo.java` | 106 | Media metadata extraction from files |
| `torrent/DuplicateTorrentException.java` | 12 | Thrown when adding a duplicate |
| `torrent/NoSuchTorrentException.java` | 12 | Thrown when torrent not found |
| `torrent/TorrentException.java` | 12 | Base exception class |
| `Native.java` | 264 | JNI native method declarations + Init/ABI extraction |
| `NaturalOrderComparator.java` | 54 | Human-friendly string sorting |
| `BindingHelper.java` | 136 | Data-binding bridge for UI layer |
| `Localizable.java` | 8 | Interface for resource-ID-backed enums |

---

## 1. Class Hierarchy

```
TorrentException (Exception)
├── DuplicateTorrentException
└── NoSuchTorrentException

TorrentItem (interface)
├── [getters: getId, getName, isComplete, isDnd, getParent, getFs]
│
├── TorrentItemContainer (interface extends TorrentItem)
│   └── [adds: ls()]
│
├── Torrent (implements TorrentItemContainer)    -- a torrent itself
├── TorrentDir (implements TorrentItemContainer) -- a directory within a torrent
├── TorrentFile (implements TorrentItem)          -- a single file within a torrent
└── TorrentFs (implements TorrentItemContainer)   -- the root "Transmission BTC"

Other types:
- TorrentStat                         -- torrent status/statistics container
- MediaInfo                           -- media metadata extracted from files
- Transmission                        -- session manager (not a data model)
- Native                              -- JNI declarations (static methods)
- NaturalOrderComparator              -- String comparator implementing Comparator<String>
- BindingHelper                       -- Android DataBinding exposure
- Localizable                         -- Interface for resource-ID-backed values
```

---

## 2. Core Data Models

### 2.1 TorrentItem (interface)

**File:** `torrent/TorrentItem.java`

A leaf-interface for any node in the torrent file hierarchy.

| Method | Return Type | Description |
|--------|-------------|-------------|
| `getId()` | `String` | Unique identifier for this item |
| `getName()` | `String` | Display name (file name, dir name) |
| `isComplete()` | `boolean` | Whether all bytes have been downloaded |
| `isDnd()` | `boolean` | Whether this item is "do not download" (unwanted) |
| `getParent()` | `TorrentItemContainer` | Parent container (null for root) |
| `getFs()` | `TorrentFs` | The filesystem root for this item |

No fields, no constructors -- pure interface contract.

---

### 2.2 TorrentItemContainer (interface)

**File:** `torrent/TorrentItemContainer.java`

Extends `TorrentItem` adding directory-listing support.

| Method | Return Type | Description |
|--------|-------------|-------------|
| `ls()` | `List<TorrentItem>` | List immediate children |

Implemented by: `Torrent`, `TorrentDir`, `TorrentFs`.

---

### 2.3 Torrent -- The Core Entity

**File:** `torrent/Torrent.java` (625 lines)

#### Fields

| Field | Type | Visibility | Default | Description |
|-------|------|-----------|---------|-------------|
| `fs` | `TorrentFs` | `private final` | constructor | The filesystem/session this torrent belongs to |
| `torrentId` | `int` | `private final` | constructor | Numeric ID assigned by the native library |
| `hashString` | `String` | `private final` | constructor | Hex-encoded SHA1 hash string (40 chars) |
| `name` | `String` | `private final` | constructor | Torrent display name |
| `hash` | `byte[]` | `private` | null | Raw 20-byte SHA1 hash (lazy-loaded) |
| `dirIndex` | `List<TorrentDir>` | `private` | null | Cached directory index (lazy, unmodifiable) |
| `fileIndex` | `List<TorrentFile>` | `private` | null | Cached file index (lazy, unmodifiable) |
| `stat` | `TorrentStat` | `private` | null | Last-known torrent statistics (lazy) |

#### Constructor

```java
Torrent(TorrentFs fs, int torrentId, String hashString, String name)
```

Package-private -- only `TorrentFs` creates `Torrent` instances.

#### Identity

A `Torrent` is uniquely identified by either:
- **Numeric ID:** `torrentId` (int) -- assigned by native session
- **Hash string:** `hashString` (String) -- 40-char hex, e.g. `"A1B2..."`

`getId()` returns `getHashString()`. The torrent-level `TorrentItemContainer` identity is always the hash string.

#### State/Status Machine

Torrent state is **not** stored in `Torrent.java` directly. It is obtained from the native layer via `getStat()`, which calls `Native.torrentStatBrief()`. The per-torrent status is reported through `TorrentStat.Status` (see section 2.5).

The valid status values (from `TorrentStat.Status` enum):

| Status | Ordinal | Meaning |
|--------|---------|---------|
| `STOPPED` | 0 | Torrent is paused / not active |
| `CHECK` | 1 | Torrent is verifying local data |
| `DOWNLOAD` | 2 | Torrent is actively downloading |
| `SEED` | 3 | Torrent is seeding (upload-only) |
| `ERROR` | 4 | Torrent has an error condition |

The native library manages all state transitions; `Torrent.java` only reads them via the stat array.

#### Key Methods

| Method | Visibility | Return Type | Description |
|--------|-----------|-------------|-------------|
| `ls(Consumer<List<TorrentItem>>)` | public | `void` | Async listing via `AsyncTask` |
| `ls()` | public | `List<TorrentItem>` | Sync listing -- files and dirs at root level |
| `hasFiles()` | public | `boolean` | Whether the torrent contains any files |
| `hasMediaFiles()` | public | `boolean` | Whether any files are video or audio |
| `getStat(boolean, int)` | public | `TorrentStat` | Get stat with timeout (via executor) |
| `getStat(boolean)` | public | `TorrentStat` | Get stat synchronously |
| `getStat()` | (package) | `TorrentStat` | Direct field access |
| `setStat(TorrentStat)` | (package) | void | Direct field set |
| `lsFiles()` | public | `List<TorrentFile>` | Return all files |
| `preloadIndex(int)` | public | `boolean` | Preload file/dir index (timeout variant) |
| `preloadIndexAndFileStat(int)` | public | `boolean` | Preload index + file stat |
| `getName()` | public | `String` | Display name |
| `getId()` | public | `String` | Returns hashString |
| `isComplete()` | public | `boolean` | True if all children are complete |
| `isDnd()` | public | `boolean` | True if all children are DnD |
| `getParent()` | public | `TorrentItemContainer` | Returns `getFs()` |
| `getFs()` | public | `TorrentFs` | The filesystem |
| `getTransmission()` | public | `Transmission` | The session |
| `getTorrentId()` | public | `int` | Numeric torrent ID |
| `getHash()` | public | `byte[]` | 20-byte raw hash (cloned) |
| `getHashString()` | public | `String` | 40-char hex hash |
| `remove(boolean)` | public | `Future<Void>` | Remove torrent (optional local data delete) |
| `stop()` | public | `Future<Void>` | Stop torrent |
| `start()` | public | `Future<Void>` | Start torrent |
| `verify()` | public | `Future<Void>` | Verify torrent data |
| `ListFilesFromFile(String)` | public static | `String[]` | Read file list from .torrent file |
| `hashStringToBytes(String)` | public static | `byte[]` | Convert hex hash to bytes |
| `hashBytesToString(byte[])` | public static | `String` | Convert bytes to hex hash |
| `getPieceHash(long, byte[])` | public | `void` | Get SHA-1 hash of a piece |
| `getPiece(long, byte[], int, int)` | public | `void` | Read piece data |
| `setPiecesHiPri(long, long)` | public | `void` | Raise priority of piece range |
| `setLocation(File)` | public | `Future<Void>` | Change download location |
| `getFile(int)` | public | `TorrentFile` | Get file by index |
| `getDir(int)` | public | `TorrentDir` | Get dir by index |
| `getPlaylistUri()` | public | `Uri` | Build playlist URI for HTTP streaming |
| `play(Activity, View)` | public | `boolean` | Open playlist URI in external player |
| `toString()` | public | `String` | Debug representation |
| `readLock()` | (package) | `Lock` | Delegates to `getFs().readLock()` |
| `getSessionId()` | (package) | `long` | Delegates to `getFs().getSessionId()` |
| `checkValid()` | (package) | void | Delegates to `getFs().checkValid()` |

#### JNI Interaction Points

| Method | Native Call | Purpose |
|--------|-------------|---------|
| `index()` | `Native.torrentListFiles(sessionId, torrentId)` | List all files in the torrent |
| `getHash()` | `Native.torrentGetHash(sessionId, torrentId, h)` | Get raw hash |
| `remove()` | `Native.torrentRemove(sessionId, torrentId, removeLocalData)` | Remove the torrent |
| `stop()` | `Native.torrentStop(sessionId, torrentId)` | Stop the torrent |
| `start()` | `Native.torrentStart(sessionId, torrentId)` | Start the torrent |
| `verify()` | `Native.torrentVerify(sessionId, torrentId)` | Verify the torrent |
| `getPieceHash()` | `Native.torrentGetPieceHash(...)` | Get piece hash |
| `getPiece()` | `Native.torrentGetPiece(...)` | Get piece data |
| `setPiecesHiPri()` | `Native.torrentSetPiecesHiPri(...)` | Set pieces high priority |
| `setLocation()` | `Native.torrentSetLocation(...)` | Move torrent data |
| `ListFilesFromFile()` | `Native.torrentListFilesFromFile(torrentFilePath)` | List files from .torrent meta |
| `hashStringToBytes()` | `Native.hashStringToBytes(hash)` | Hex-to-bytes conversion |
| `hashBytesToString()` | `Native.hashBytesToString(hash)` | Bytes-to-hex conversion |

#### File Index Construction (index method)

The `index(boolean isFile)` method:

1. Calls `Native.torrentListFiles(getSessionId(), getTorrentId())` which returns an array of path strings like `{"dir1/fileA.mp4", "dir1/fileB.mp3", "fileC.txt"}`
2. Tokenizes each path by `/` separator using `StringTokenizer`
3. For intermediate tokens, creates `TorrentDir` instances keyed by path in a `HashMap<String, TorrentDir>`
4. For leaf tokens, creates `TorrentFile` instances with torrent reference, parent, index (position in array), name, and fullName
5. Directories get `addChild()` calls for both nested dirs and files
6. After construction, `compactChildren()` trims and freezes each dir's children list
7. Results are stored as `Collections.unmodifiableList()` in `dirIndex` and `fileIndex`
8. Cached -- subsequent calls return the cached list

---

### 2.4 TorrentFile

**File:** `torrent/TorrentFile.java` (482 lines)

#### Fields

| Field | Type | Visibility | Default | Description |
|-------|------|-----------|---------|-------------|
| `VERIFY_PIECE` | `boolean` | `private static final` | false | Whether to verify pieces after download |
| `torrent` | `Torrent` | `private final` | constructor | Owning torrent |
| `index` | `int` | `private final` | constructor | Position in native file list |
| `parent` | `TorrentItemContainer` | `private final` | constructor | Parent directory (Torrent or TorrentDir) |
| `name` | `String` | `private final` | constructor | Simple filename |
| `fullName` | `String` | `private final` | constructor | Full path within torrent |
| `location` | `String` | `private` | null | Absolute filesystem path (lazy) |
| `strId` | `String` | `private` | null | Cached composite ID |
| `stat` | `long[]` | `private` | null | File stat array (lazy) |
| `mimeType` | `String` | `private` | null | Cached MIME type |
| `type` | `byte` | `private` | -1 | Cached media type: 0=unknown, 1=video, 2=audio, 3=image, 4=text |
| `mediaInfo` | `MediaInfo` | `private` | null | Cached media metadata |

#### Stat Array Layout

The `long[] stat` array returned by `Native.torrentGetFileStat(...)` has this structure:

| Index | Field | Getter | Description |
|-------|-------|--------|-------------|
| `[0]` | pieceLength | `getPieceLength()` | Size of each piece in bytes |
| `[1]` | length | `getLength()` | Total file length in bytes |
| `[2]` | fileOffset | (internal) | Byte offset of this file within the torrent |
| `[3]` | firstPiece | `getFirstPieceIndex()` | Index of the first piece containing this file |
| `[4]` | lastPiece | `getLastPieceIndex()` | Index of the last piece containing this file |
| `[5]` | flags | `isComplete()` / `isDnd()` | 0=incomplete, 1=complete, 2=do-not-download |
| `[6+]` | bitfield | (internal) | Piece availability bitfield (64 bits per field) |

When a file is 100% complete, the stat array is truncated to indices `[0..5]` via `Arrays.copyOf(s, 6)`.

#### Key Methods

| Method | Return Type | Description |
|--------|-------------|-------------|
| `getTorrent()` | `Torrent` | Owning torrent |
| `getName()` | `String` | Simple file name |
| `getFullName()` | `String` | Full path within torrent |
| `getId()` | `String` | Format: `<hashString>-f<index>` |
| `getParent()` | `TorrentItemContainer` | Parent (Torrent or TorrentDir) |
| `getFs()` | `TorrentFs` | Filesystem root |
| `getTransmission()` | `Transmission` | Session |
| `getIndex()` | `int` | File index |
| `findLocation()` | `String` | Absolute path on disk via `Native.torrentFindFile()` |
| `getLength()` | `long` | File byte length from stat |
| `getPieceLength()` | `long` | Piece size from stat |
| `getFirstPieceIndex()` | `long` | First piece index from stat |
| `getLastPieceIndex()` | `long` | Last piece index from stat |
| `getProgress(boolean)` | `int` | Download progress 0-100 |
| `isComplete()` | `boolean` | Whether fully downloaded |
| `isDnd()` | `boolean` | Whether marked Do-Not-Download |
| `setDnd(boolean)` | `Future<Void>` | Mark/unmark Do-Not-Download |
| `setDndStat(boolean)` | (package) `void` | Update cached stat flag without native call |
| `getMimeType()` | `String` | MIME type from file extension |
| `isVideo()` | `boolean` | Type == video |
| `isAudio()` | `boolean` | Type == audio |
| `isMedia()` | `boolean` | Type == video or audio |
| `getMediaInfo()` | `MediaInfo` | Extract media metadata, or null |
| `getHttpUri()` | `Uri` | URI for HTTP streaming |
| `open(Activity, View)` | `boolean` | Open file in external app |
| `read(...)` | `int` | Read bytes from a piece |
| `waitForPiece(...)` | `boolean` | Block until piece is available |
| `statLoaded()` | (package) `boolean` | Whether stat has been loaded at least once |
| `toString()` | `String` | Debug representation |

#### Piece-Level Reading

The `read()` method reads file data at the piece level:

1. Retrieves file stat array
2. Calculates `torrentOff = fileOffset + off` and `pieceIdx = torrentOff / pieceLength`
3. Computes offset within piece and bounds the read length to piece boundary
4. Calls `waitForPiece()` which:
   - Returns immediately if piece is already available
   - If missing, calls `increasePriority()` to raise piece priority (via `torrent.setPiecesHiPri()`)
   - Polls stat updates in a loop with configurable sleep/retry until piece arrives
   - Throws `TimeoutException` after `retries` failures
5. Calls `getTorrent().getPiece(pieceIdx, dst, offset, len)` to read the actual data
6. Optionally verifies piece SHA-1 hash (when `VERIFY_PIECE` is true)

#### Media Type Detection

The `type()` method returns a byte constant based on MIME type:

| Value | Meaning | Criteria |
|-------|---------|---------|
| -1 | Uncached | Initial default |
| 0 | Unknown | |
| 1 | Video | `mime.startsWith("video/")` |
| 2 | Audio | `mime.startsWith("audio/")` OR `.ogg`/`.opus` extension |
| 3 | Image | `mime.startsWith("image/")` |
| 4 | Text | `mime.startsWith("text/")` |
| 22 | Playlist | `.m3u` extension (augments audio=2 with 20 offset) |

---

### 2.5 TorrentDir

**File:** `torrent/TorrentDir.java` (222 lines)

#### Fields

| Field | Type | Visibility | Default | Description |
|-------|------|-----------|---------|-------------|
| `parent` | `TorrentItemContainer` | `private final` | constructor | Parent (Torrent or TorrentDir) |
| `name` | `String` | `private final` | constructor | Directory name |
| `fullName` | `String` | `private final` | constructor | Full path within torrent |
| `index` | `int` | `private final` | constructor | Position in torrent dir index |
| `strId` | `String` | `private` | null | Cached composite ID |
| `children` | `List<TorrentItem>` | `private` | `new ArrayList<>()` | Child items (frozen to unmodifiable after construction) |

#### Key Methods

| Method | Return Type | Description |
|--------|-------------|-------------|
| `getTorrent()` | `Torrent` | Walk up parent chain to find root Torrent |
| `ls()` | `List<TorrentItem>` | Return children list |
| `lsFiles()` | `List<TorrentFile>` | Return only TorrentFile children |
| `getName()` | `String` | Directory name |
| `getFullName()` | `String` | Full path |
| `getIndex()` | `int` | Index |
| `getId()` | `String` | `<hashString>-d<index>` |
| `isComplete()` | `boolean` | All children complete |
| `isDnd()` | `boolean` | All children DnD |
| `setDnd(boolean)` | `Future<Void>` | Set DnD for all descendant files |
| `hasMediaFiles()` | `boolean` | Any child is video or audio |
| `getPlaylistUri()` | `Uri` | HTTP streaming playlist URI |
| `play(Activity, View)` | `boolean` | Open playlist in external player |
| `getParent()` | `TorrentItemContainer` | Parent |
| `getFs()` | `TorrentFs` | Filesystem root |
| `addChild(TorrentItem)` | (package) `void` | Add child during index construction |
| `compactChildren()` | (package) `void` | Trim and freeze children list |

---

### 2.6 TorrentStat

**File:** `torrent/TorrentStat.java` (67 lines)

#### Fields

| Field | Type | Visibility | Default | Description |
|-------|------|-----------|---------|-------------|
| `stat` | `long[]` | `private` | constructor | Pointer into owning TorrentFs stat array |
| `offset` | `int` | `private` | constructor | Index into `stat` for this torrent's slice |
| `error` | `String` | `private` | constructor | Error text (set separately for ERROR status) |

#### Stat Array Slice Layout (10 slots per torrent)

`updateStat()` in `TorrentFs` calls `Native.torrentStatBrief(sid, s)` which returns a flat `long[]`.
Each torrent occupies 10 consecutive slots:

| Offset Field | Getter | Description |
|--------------|--------|-------------|
| `offset + 0` | (internal) | Torrent ID (used to match to Torrent object) |
| `offset + 1` | `getStatus()` | Status ordinal -> `Status` enum |
| `offset + 2` | `getProgress()` | Download progress 0-100 |
| `offset + 3` | `getTotalLength()` | Total size in bytes |
| `offset + 4` | `getRemainingLength()` | Remaining bytes to download |
| `offset + 5` | `getUploadedLength()` | Bytes uploaded |
| `offset + 6` | `getPeersUp()` | Number of peers uploading to us |
| `offset + 7` | `getPeersDown()` | Number of peers downloading from us |
| `offset + 8` | `getSpeedUp()` | Upload speed in bytes/sec |
| `offset + 9` | `getSpeedDown()` | Download speed in bytes/sec |

#### Methods

| Method | Return Type | Description |
|--------|-------------|-------------|
| `update(long[], int, String)` | (package) `void` | Update stat slice reference |
| `getStatus()` | `Status` | Status enum value |
| `getProgress()` | `int` | 0-100 progress |
| `getTotalLength()` | `long` | Total bytes |
| `getRemainingLength()` | `long` | Remaining bytes |
| `getUploadedLength()` | `long` | Uploaded bytes |
| `getPeersUp()` | `int` | Leech count |
| `getPeersDown()` | `int` | Seed count |
| `getSpeedUp()` | `int` | Upload speed |
| `getSpeedDown()` | `int` | Download speed |
| `getError()` | `String` | Error message (null if no error) |

#### Status Enum

```java
public enum Status {
    STOPPED,   // 0
    CHECK,     // 1
    DOWNLOAD,  // 2
    SEED,      // 3
    ERROR;     // 4
    private static final Status[] values = values();
}
```

---

### 2.7 MediaInfo

**File:** `torrent/MediaInfo.java` (106 lines)

#### Fields

| Field | Type | Visibility | Description |
|-------|------|-----------|-------------|
| `title` | `String` | `private final` | Track title |
| `album` | `String` | `private final` | Album name |
| `artist` | `String` | `private final` | Artist name |
| `genre` | `String` | `private final` | Genre |
| `mimeType` | `String` | `private final` | MIME type |
| `date` | `String` | `private final` | Date (formatted as yyyy-MM-dd) |
| `duration` | `String` | `private final` | Duration string (HH:mm:ss.SSS) |
| `resolution` | `String` | `private final` | Resolution string (WxH) |

#### Constructor

```java
MediaInfo(MediaMetadataRetriever r)
```

Consumes an Android `MediaMetadataRetriever` and extracts:

- `METADATA_KEY_TITLE` -> title
- `METADATA_KEY_ARTIST` -> artist
- `METADATA_KEY_ALBUM` -> album
- `METADATA_KEY_GENRE` -> genre
- `METADATA_KEY_MIMETYPE` -> mimeType
- `METADATA_KEY_DATE` -> date (parses `yyyyMMdd'T'HHmmss[.S...]` format, outputs `yyyy-MM-dd`)
- `METADATA_KEY_DURATION` -> duration (milliseconds to `HH:mm:ss.SSS` format)
- `METADATA_KEY_VIDEO_WIDTH` + `METADATA_KEY_VIDEO_HEIGHT` -> resolution (`WxH`)

Calls `r.release()` at the end of construction -- the `MediaMetadataRetriever` is consumed.

---

## 3. Session Management (Transmission.java)

**File:** `torrent/Transmission.java` (685 lines)

### 3.1 Session State Machine

Internal state field:

```java
private volatile byte state = STATE_STOPPED;
```

| Constant | Value | Meaning |
|----------|-------|---------|
| `STATE_STOPPED` | 0x00 | Not running |
| `STATE_STARTING` | 0x01 | In startup process |
| `STATE_RUNNING` | 0x02 | Actively running |
| `STATE_STOPPING` | 0x04 | In shutdown process |
| `STATE_SUSPENDED` | 0x08 | Suspended (network paused) |
| `STATE_SUSPENDED_BY_USER` | 0x10 | Suspended by explicit user action |

States use bit-flags: running+suspended = `STATE_RUNNING | STATE_SUSPENDED` = `0x0A`.

| Method | Logic |
|--------|-------|
| `isRunning()` | `(state & STATE_RUNNING) != 0` |
| `isStarting()` | `(state & STATE_STARTING) != 0` |
| `isStopping()` | `(state & STATE_STOPPING) != 0` |
| `isStopped()` | `state == STATE_STOPPED` |
| `isSuspended()` | `(state & (STATE_SUSPENDED | STATE_SUSPENDED_BY_USER)) != 0` |
| `isSuspendedByUser()` | `(state & STATE_SUSPENDED_BY_USER) != 0` |

### 3.2 Fields

| Field | Type | Visibility | Default | Description |
|-------|------|-----------|---------|-------------|
| `lock` | `ReadWriteLock` | `private final` | `new ReentrantReadWriteLock()` | Thread safety |
| `prefs` | `Prefs` | `private final` | constructor | Application preferences |
| `watchers` | `List<Watcher>` | `private` | null | Watch directory watchers |
| `powerLock` | `PowerLock` | `private` | null | Wake lock for active downloads |
| `ssdpServer` | `SsdpServer` | `private` | null | UPnP SSDP server instance |
| `semaphores` | `List<Long>` | `private volatile` | null | Active semaphore handles (for magnet conversion) |
| `httpServer` | `HttpServer` | `private volatile` | null | HTTP server for streaming |
| `torrentFs` | `TorrentFs` | `private volatile` | null | Filesystem/torrent listing |
| `executor` | `ExecutorService` | `private volatile` | null | Thread pool for background tasks |
| `scheduler` | `ScheduledExecutorService` | `private volatile` | null | Scheduler for periodic tasks |
| `session` | `long` | `private volatile` | 0 | Native session handle |
| `state` | `byte` | `private volatile` | `STATE_STOPPED` | Session state |

### 3.3 Session Configuration

The `start()` method configures and launches the native session:

1. Sets `state = STATE_STARTING`
2. Starts the executor (lazy-init)
3. **Directory setup:**
   - `dataDir` = `ctx.getApplicationInfo().dataDir`
   - `configDir` = `prefs.getSettingsDir()` (settings.json lives here)
   - `downloadDir` = `prefs.getDownloadDir()`
   - `webDir` = `dataDir/web/` (web UI assets)
   - `tmp` = `dataDir/tmp/`
4. Copies web assets from APK assets using `copyAssets()`
5. **Network suspend check:** If WiFi/Ethernet-only mode and no active WiFi, sets `suspend = true`
6. Environment setup:
   - `TMP` env var
   - `TRANSMISSION_WEB_HOME` env var
7. Socket buffer increase (optional root)
8. Proxy configuration
9. **Native session start:**
   ```java
   session = Native.transmissionStart(configDir, downloadDir,
       prefs.getEncryptionMode().ordinal(),
       prefs.isRpcEnabled(), prefs.getRpcPort(),
       prefs.isRpcAuthEnabled(), prefs.getRpcUsername(), prefs.getRpcPassword(),
       prefs.isRpcWhitelistEnabled(), prefs.getRpcWhitelist(),
       settings.exists(),                       // load existing config
       prefs.isSeqDownloadEnabled(),            // sequential download
       suspend);                                // start paused
   ```
10. Creates `TorrentFs`
11. Starts watch dirs (`FileObserver`)
12. Starts UPnP/SSDP
13. Acquires wake lock if there are downloading torrents
14. Sets RPC callbacks on native side

### 3.4 Torrent Lifecycle Methods

#### `addTorrent(File torrentFile, File downloadDir, int[] unwantedIndexes, byte[] returnMeTorrentHash, boolean delete, boolean sequential, int retries, int delay)`

Returns `AddTorrentResult`:

```java
public enum AddTorrentResult {
    OK,           // 0 - success
    PARSE_ERR,    // 1 - failed to parse .torrent file
    DUPLICATE,    // 2 - already added
    OK_DELETE,    // 3 - success and source file was deleted by native
    NOT_STARTED   // transmission not running
}
```

Logic:
1. Calls `Native.torrentAdd(session, path, downloadPath, delete, sequential, unwantedIndexes, returnMeTorrentHash)`
2. Retries up to `retries` times with `delay` ms between attempts (for PARSE_ERR = 1)
3. On success/duplicate, calls `torrentAddedOrChanged()`

#### `magnetToTorrent(final Uri magnetLink, final File destTorrentPath, final int timeout, final boolean[] enqueue)`

Returns `Promise<Void>` with:
- Creates a native semaphore for cancellation
- Calls `Native.torrentMagnetToTorrentFile(session, sem, magnetLink, destTorrentPath, timeout, enqueue)`
- Supports `cancel()` via `Native.semPost(sem)`

#### `remove(Future<Void> Torrent.remove(boolean removeLocalData))`

Called on `Torrent` instance, delegates to `Native.torrentRemove()`.

#### `start()`, `stop()`, `verify()`, `setLocation(File)`

Each delegates to the corresponding `Native.*()` call, submitted to the executor.

### 3.5 Watch Directory Mechanism

Uses Android's `FileObserver` (inner class `Watcher`):

```java
private final class Watcher extends FileObserver {
    private final File dir;
    private final File downloadDir;
}
```

Behavior:
1. Observes `FileObserver.CREATE` events on the watch directory
2. On creation (or initial scan via `scan()`), checks if file ends with `.torrent`
3. Calls `addTorrent(f, downloadDir, null, null, false, seqDownload, 10, 1000)`
4. After successful add (`OK`): renames file to `{name}.torrent.added`
5. After failure (`PARSE_ERR` or `DUPLICATE`): deletes file
6. Periodic scan: if `prefs.getWatchInterval() > 0`, a fixed-delay scheduled task rescans every N seconds

Multiple watch directories are supported via `prefs.getWatchDirs()` which returns `Map<String, String>` (watchDir -> downloadDir).

### 3.6 Callback Mechanism

Four native RPC callbacks are set via `Native.transmissionSetRpcCallbacks()`:

| Callback | Handler | Effect |
|----------|---------|--------|
| `torrentAddedOrChanged` | `torrentAddedOrChanged()` | Resets `TorrentFs` cache, acquires wakelock |
| `torrentRemoved` | `torrentRemoved()` | Resets `TorrentFs` cache |
| `sessionChanged` | `sessionChanged()` | Reads encryption mode from native, updates prefs |
| `scheduledAltSpeed` | `scheduledAltSpeed()` | Acquires wakelock |

JavaScript bridge: `@Keep` annotated methods `torrentAddedOrChangedCallback()`, `torrentStoppedCallback()`, `sessionChangedCallback()`, `scheduledAltSpeedCallback()` are called from native code and dispatch to the Java Runnables.

### 3.7 Thread Pool

```java
new ThreadPoolExecutor(0, 30, 60L, TimeUnit.SECONDS,
    new SynchronousQueue<>(),
    Executors.defaultThreadFactory(),
    new ThreadPoolExecutor.CallerRunsPolicy());
```

- Core pool: 0 (idle threads die after 60s)
- Max pool: 30
- Queue: `SynchronousQueue` (hands off directly to threads)
- Saturation: `CallerRunsPolicy` (runs on submitting thread if pool is full)

### 3.8 Power Lock

An Android `PowerLock` (partial wake lock) is acquired when there are active downloads and released when none remain. A scheduled task checks every minute whether downloads are still active.

---

## 4. File System (TorrentFs.java)

**File:** `torrent/TorrentFs.java` (258 lines)

### 4.1 Fields

| Field | Type | Visibility | Default | Description |
|-------|------|-----------|---------|-------------|
| `transmission` | `Transmission` | `private final` | constructor | Session reference |
| `sessionId` | `long` | `private final` | constructor | Native session handle |
| `cache` | `ConcurrentHashMap<String, Torrent>` | `private final` | `new ConcurrentHashMap<>()` | Hash-based torrent cache |
| `updateId` | `AtomicInteger` | `private final` | `new AtomicInteger(Math.abs(new Random().nextInt()))` | Monotonic version counter |
| `torrents` | `List<TorrentItem>` | `private volatile` | null | Cached torrent list (lazy) |
| `stat` | `long[]` | `private volatile` | null | Cached stat array |

### 4.2 Implementation of TorrentItemContainer

`TorrentFs` is the root container:

| Method | Implementation |
|--------|----------------|
| `getName()` | Returns `"Transmission BTC"` |
| `getId()` | Returns `"0"` |
| `getParent()` | Returns `null` (root) |
| `getFs()` | Returns `this` |

#### `ls()` - Listing Torrent Names

1. On first call, calls `Native.transmissionListTorrentNames(getSessionId())`
2. Tokenizes each result (`"<id> <hash> <name>"` split on space, limit=3)
3. Creates `Torrent` instances, stores in `cache` keyed by hashString
4. Increments `updateId` atomically
5. Caches the list as `Collections.unmodifiableList()`
6. On subsequent calls, returns cached list

#### `reset()`

Clears cache, `torrents` list, and `stat` array. Called when:
- `torrentAddedOrChanged()` RPC callback fires
- `torrentRemoved()` RPC callback fires
- `reportNoSuchTorrent()` is invoked

### 4.3 Stat Update (`updateStat()`)

1. Calls `Native.torrentStatBrief(sessionId, stat)` which returns a flat `long[]`
2. Iterates in steps of 10 (each step is one torrent's stat slice)
3. Matches `torrentId` (at `offset + 0`) to `Torrent` objects in the torrent list
4. Creates or updates `TorrentStat` objects
5. If status is `ERROR`, additionally fetches error text via `Native.torrentGetError()`

### 4.4 Torrent Lookup

| Method | Logic |
|--------|-------|
| `findTorrent(String hashString)` | Checks hash length; looks up in `cache`; if miss, calls `findTorrent(byte[], String)` and `putIfAbsent` |
| `findTorrent(byte[], String)` | Calls `Native.torrentFindByHash(sessionId, hash)` then `Native.torrentGetName(sessionId, id)` |
| `findItem(String id)` | Parses `"hash"`, `"hash-fNN"`, `"hash-dNN"` patterns; routes to findTorrent/getFile/getDir |

### 4.5 Sorting Utility

`sortByName(Collection<TorrentItem>, boolean skipDnd)`:

1. Optionally filters out DnD items
2. Sorts using `NaturalOrderComparator` on names
3. Directories (TorrentItemContainer) sort before files
4. Returns new `ArrayList`

---

## 5. Exception Types

### 5.1 TorrentException (base)

```
TorrentException extends Exception
```

Four constructors: no-arg, String, Throwable, (String, Throwable).

### 5.2 DuplicateTorrentException

```
DuplicateTorrentException extends TorrentException
```

Thrown when `Native.torrentMagnetToTorrentFile()` detects a duplicate.

### 5.3 NoSuchTorrentException

```
NoSuchTorrentException extends TorrentException
```

Thrown by many `Native.*` methods when a torrent ID/hash no longer refers to an active torrent. When caught, `reportNoSuchTorrent()` resets the TorrentFs cache.

---

## 6. Utility Classes

### 6.1 NaturalOrderComparator

**File:** `NaturalOrderComparator.java` (54 lines)

Implements `Comparator<String>`. Sorts strings with human-friendly numeric ordering:

- `"file2"` sorts before `"file10"` (numeric comparison of "2" vs "10")
- Compares character-by-character; when both characters are digits, parses the full numeric run and compares as `long`
- Equal numeric values with different digit lengths sort shorter first (`"2"` vs `"02"` -> shorter is less)

### 6.2 BindingHelper

**File:** `BindingHelper.java` (136 lines)

Provides Android DataBinding expressions for XML layouts.

Key bindings:
- `and(boolean...)` - logical AND of varargs
- `getIp()` - device IP address
- `isServiceRunning()` / `isServiceStarting()` - service state
- `isSuspended()` - session suspend state
- `startStopService(View...)` - toggle transmission service
- `suspend(boolean, Runnable)` - suspend/resume session
- `openUrl(String, String, int, String)` - open web UI
- `checkRoot(View)` - verify root access
- `addWatchDir()` - add watch directory preference

### 6.3 Localizable

**File:** `Localizable.java` (8 lines)

```java
public interface Localizable {
    int getResourceId();
}
```

Implemented by enums to map enumeration constants to Android string resources.

---

## 7. Data Flow

### 7.1 Adding a Torrent (full chain)

```
User Action
    |
    v
Activity / Fragment
    |  (e.g. AddTorrentActivity)
    v
Transmission.addTorrent(File, File, int[], byte[], boolean, boolean, int, int)
    |
    |  readLock.lock()
    |  mkdirs(downloadDir)
    |  for (i = 0; i <= retries; i++)
    v
Native.torrentAdd(session, path, downloadPath, delete, sequential,
                   unwantedIndexes, returnMeTorrentHash)
    |
    |  [native code processes .torrent, adds to session]
    v
Result: 0 (OK), 1 (PARSE_ERR), 2 (DUPLICATE), 3 (OK_DELETE)
    |
    |  if OK/OK_DELETE/DUPLICATE:
    v
transmission.torrentAddedOrChanged()
    |
    v
TorrentFs.reset()
    |  cache.clear()
    |  torrents = null
    |  stat = null
    |
v
[Next ls() call on TorrentFs rebuilds lists]
    |
    v
Native.transmissionListTorrentNames(sessionId)
    |  -> String[] {"<id> <hash> <name>"}
    v
TorrentFs.ls() creates new Torrent instances
```

**Magnet link path:**

```
Transmission.magnetToTorrent(Uri, File, int, boolean[])
    |
    v
Native.torrentMagnetToTorrentFile(session, sem, magnetLink, destPath, timeout, enqueue)
    |
    v
[converted .torrent file written to destPath]
    |
    |  enqueue[0] determines whether to auto-add
    v
addTorrent(destPath, ...)
```

**Watch directory path:**

```
FileObserver.CREATE event
    |
    v
Watcher.onEvent(int, String path)
    |
    |  if path.endsWith(".torrent"):
    v
Transmission.addTorrent(f, downloadDir, null, null, false, seq, 10, 1000)
    |
    |  OK -> rename file to {name}.added
    |  FAIL -> delete file
```

### 7.2 Status Update Cycle

```
Periodic trigger (scheduler tick / UI refresh / explicit call)
    |
    v
Torrent.getStat(boolean update, int timeout)
    |
    |  if update or stat is null:
    v
ExecutorService.submit(() -> {
    TorrentFs.updateStat()
        |
        |  readLock.lock()
        v
        Native.torrentStatBrief(sessionId, stat)
        |  Returns flat long[]: [id0, status0, prog0, total0, rem0, up0, pu0, pd0, spdU0, spdD0,
        |                         id1, status1, ...]
        v
        For each 10-slot chunk:
            Match torrent by ID
            Create or update TorrentStat
            If ERROR: fetch error text via Native.torrentGetError()
})
    |
    v
TorrentStat.offset points to this torrent's 10-slot slice
    |
    v
Consumers call TorrentStat.getStatus(), getProgress(), getSpeedDown(), etc.
```

### 7.3 File Selection Flow

```
Torrent.ls()  or  Torrent.lsFiles()
    |
    v
index(true/false) -> cached fileIndex/dirIndex
    |
    |  if null:
    v
Native.torrentListFiles(sessionId, torrentId)
    |  Returns String[]: {"dirA/file1.mp4", "dirA/file2.mp3", "file3.txt"}
    v
Tokenize with "/", build TorrentDir/TorrentFile tree
    |
    |  dirIndex = unmodifiableList(dirs)
    |  fileIndex = unmodifiableList(files)
    v
TorrentFile.setDnd(boolean)  [user wants to exclude/include files]
    |
    v
Native.torrentSetDnd(sessionId, torrentId, int[], boolean)
    |
    v
[Native library updates piece priority accordingly]
```

---

## 8. Platform-Specific API Usage

| Android API | File:Line | Purpose | HarmonyOS Equivalent |
|-------------|-----------|---------|---------------------|
| `android.os.AsyncTask` | Torrent.java:59 | Background listing with UI callback | `ohos.app.dispatcher.TaskDispatcher` or `NapiTask` |
| `android.os.FileObserver` | Transmission.java:621 | Watch directory file monitoring | `ohos.file.observer.FileWatcher` |
| `android.media.MediaMetadataRetriever` | MediaInfo.java:29 | Extract media metadata from file | `ohos.multimedia.media.AVMetadataHelper` |
| `android.net.Uri` | Torrent.java:583 | URI construction | `ohos.utils.net.Uri` |
| `android.content.Context` | Transmission.java:146 | Android application context | `ohos.app.Context` |
| `android.content.res.AssetManager` | Transmission.java:497 | Access bundled assets | `ohos.app.Context.getResourceManager()` |
| `android.os.PowerLock` | Transmission.java:576 | Wake lock for active downloads | `ohos.power.RunningLock` |
| `android.os.Build.SUPPORTED_ABIS` | Native.java:248 | Native library ABI detection | `ohos.system.DeviceInfo` |
| `android.databinding.ViewDataBinding` | BindingHelper.java:23 | Data binding library | N/A (ohos has different binding approach) |
| `android.support.annotation.Keep` | Native.java:8 | ProGuard keep annotation | N/A |
| `android.support.annotation.Nullable` | Native.java:9 | Nullability annotation | `ohos.annotation.Nullable` |
| `java.util.concurrent.locks.ReentrantReadWriteLock` | Transmission.java:66 | Read/write locking | `ohos.utils.concurrent.RwLock` |
| `java.util.concurrent.ThreadPoolExecutor` | Transmission.java:521 | Background thread pool | `ohos.app.dispatcher.TaskDispatcher` |
| `java.util.concurrent.ScheduledExecutorService` | Transmission.java:545 | Periodic tasks | `ohos.app.dispatcher.TaskDispatcher` |
| `java.util.concurrent.ExecutorService` | Transmission.java:514 | Async task execution | `ohos.app.dispatcher.TaskDispatcher` |
| `android.net.ConnectivityManager` | Transmission.java:163 (via Utils) | Network state checks | `ohos.net.NetManager` |

---

## 9. Serialization & Persistence

### 9.1 Native Session Persistence

The native `libtransmission` library handles its own persistence:

- Config/settings are read from `settings.json` in the config directory at startup
- On `transmissionStop()`, the native library writes settings back to the config directory
- Torrent metadata (`.torrent` files) and resume data are managed by the native library in the config directory
- The Java layer does not serialize any torrent data itself

### 9.2 Watch Directory State

Watch directory state is purely filesystem-based:
- `.added` suffix is used to mark processed `.torrent` files
- Failed files are deleted entirely
- No Java-side tracking of which files have been processed

### 9.3 Cached State (Volatile)

All Java-side caches are volatile and rebuilt on demand:
- `TorrentFs.torrents` -- rebuilt on `ls()` after `reset()`
- `TorrentFs.cache` (ConcurrentHashMap) -- cleared on `reset()`
- `Torrent.fileIndex`, `Torrent.dirIndex` -- rebuilt on first access after nullification
- `Torrent.stat` -- updated via `TorrentFs.updateStat()`
- `TorrentFile.stat` -- rebuilt on `stat(true)` (forced update)
- `TorrentFile.mediaInfo` -- cleared by GC, rebuilt independently

### 9.4 Preferences-Based Configuration

The `Prefs` object (Android SharedPreferences-backed) holds:
- Download directory path
- Settings directory path
- Watch directory configuration (map of watchDir -> downloadDir)
- Encryption mode
- RPC configuration (enabled, port, auth, whitelist)
- Sequential download flag
- WiFi-only mode and SSID
- UPnP enabled flag
- Socket buffer increase flag
- Alt web UI selection

All passed to the native library at session start.

---

## Key Architectural Observations for HarmonyOS Porting

1. **JNI is the central pattern.** Every torrent operation flows through JNI static methods on `Native.java`. The HarmonyOS port must either:
   - Reimplement the native C library for OHOS, or
   - Use an equivalent FFI mechanism (Napi)

2. **The `TorrentItem` / `TorrentItemContainer` hierarchy is a composite pattern.** `Torrent`, `TorrentDir`, and `TorrentFs` all implement `TorrentItemContainer`, while `TorrentFile` implements `TorrentItem`. This pattern is pure Java and ports directly.

3. **`MediaInfo` is the only Android-class-specific dependency** that could be problematic. `MediaMetadataRetriever` maps cleanly to `ohos.multimedia.media.AVMetadataHelper`.

4. **`FileObserver` (watch directories)** maps to `ohos.file.observer.FileWatcher` in HarmonyOS.

5. **Threading model**: `ExecutorService` / `ScheduledExecutorService` / `ReadWriteLock` map to OHOS `TaskDispatcher` / `RwLock`.

6. **Wake lock**: `PowerLock` (Android) maps to `RunningLock` (HarmonyOS).

7. **No serialization concerns** -- all state is either transient Java caches or managed by the native C library. The Java layer does no persistent serialization of its own.
