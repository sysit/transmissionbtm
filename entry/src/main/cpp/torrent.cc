// transmissionbtm — Torrent CRUD + statistics (N-API)
// transmissionbtm — torrent CRUD + stat collection via N-API
// Updated for Transmission 4.1 C++ API (2026-07-12)
// 20 exported functions
//
// Key 4.0.6→4.1 changes:
//   metainfo_ is private → use tor->info_hash(), tor->file_count(), etc.
//   completion_ is private → use tor->size_when_done(), tor->has_piece(), etc.
//   swarm is private → use tr_torrentStat() for peer counts and speeds
//   bytes_uploaded_ is private → use tr_torrentStat()->uploadedEver
//   cache is internal → read_block() removed; torrentGetPiece stubbed
//   tr_file_view → still exists, tr_torrentFile() unchanged
//   tor->error / tor->error_string → tor->error().error_type()==TR_STAT_LOCAL_ERROR / errmsg()

#include "commons.h"
#include <libtransmission/transmission.h>
#include <libtransmission/peer-common.h>   // tr_swarm_stats, tr_swarmGetStats
#include <libtransmission/torrent.h>
#include <libtransmission/session.h>
#include <cstring>
#include <cstdlib>
#include <vector>
#include <thread>
#include <fcntl.h>
#include <unistd.h>
#include <curl/curl.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x0001
#define LOG_TAG "transmissionbtm"

// ── Local helpers ───────────────────────────────────────────────────
static bool getBoolNapi(napi_env env, napi_value val) {
  bool b = false;
  napi_get_value_bool(env, val, &b);
  return b;
}

static int32_t getInt32Napi(napi_env env, napi_value val) {
  int32_t i = 0;
  napi_get_value_int32(env, val, &i);
  return i;
}

static int64_t getInt64FromBigInt(napi_env env, napi_value val) {
  uint64_t u;
  bool lossless;
  napi_get_value_bigint_uint64(env, val, &u, &lossless);
  return (int64_t) u;
}

// 4.1: getVerifyProgress uses tor->has_piece() (public accessor)
static double getVerifyProgress(tr_torrent const *tor) {
  double d = 0;
  if (tr_torrentHasMetadata(tor)) {
    tr_piece_index_t checked = 0;
    tr_piece_index_t pc = tor->piece_count();
    for (tr_piece_index_t i = 0; i < pc; ++i) {
      if (tor->has_piece(i)) checked++;
    }
    d = checked / (double) pc;
  }
  return d;
}

// Compute percent_done from public API
// P0 fix (codex review): the old guard `if (lud >= swd) return 1.0;` was
// inverted — a fresh torrent has left_until_done == size_when_done, so it
// reported 100% done. left_until_done == size_when_done means 0% done.
static double getPercentDone(tr_torrent const *tor) {
  auto swd = tor->size_when_done();
  if (swd == 0) return 0.0;
  auto lud = tor->left_until_done();
  if (lud >= swd) return 0.0;  // nothing downloaded yet
  return 1.0 - (double)lud / (double)swd;  // lud == 0 → 1.0 (complete)
}

// Helper: get bytes uploaded ever (via tr_stat, avoids private member)
static uint64_t getUploadedEver(tr_torrent *tor) {
  auto stat = tr_torrentStat(tor);
  return stat->uploadedEver;
}

extern "C" {

// ── torrentAdd (returns 0=OK, 1=PARSE_ERR, 2=DUPLICATE, 3=OK_DELETE) ─
// B1 (docs/11): tr_torrentNew + setFileDLs + duplicate handling run on the
// session event thread via torrentAddFunc; ctor construction and arg parsing
// stay on the calling thread (the ctor is only touched by the event thread
// once tr_torrentNew consumes it).
typedef struct {
  tr_ctor *ctor;
  bool deleteSource;
  bool paused;
  tr_file_index_t idxLen;
  tr_file_index_t *wantedFiles;
  uint8_t *outHash;
  size_t outHashLen;
  int err;
} TorrentAddData;

static void *torrentAddFunc(tr_session *s, void *d, Err *err) {
  (void)s;
  (void)err;
  auto *ad = (TorrentAddData *) d;

  // P0 fix (codex review): result-code semantics were wrong.
  // The ArkTS side treats 0=OK, 1=PARSE_ERR, 2=DUPLICATE, 3=OK_DELETE,
  // but the old logic only reached 0 on the unwanted-files branch, and
  // a plain duplicate (tor==null, dupTor!=null) fell through to err=1.
  tr_torrent *dupTor = nullptr;
  tr_torrent *tor = tr_torrentNew(ad->ctor, &dupTor);
  ad->err = 1;  // default PARSE_ERR

  if (tor != nullptr) {
    // Fresh torrent added → success (0), or OK_DELETE (3) if source deleted.
    ad->err = ad->deleteSource ? 3 : 0;
    // TEMP DIAG: log the actual pause/start state around the explicit start.
    bool ctorPaused = false;
    bool ctorHasPaused = tr_ctorGetPaused(ad->ctor, TR_FORCE, &ctorPaused);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                 "[DBG] addfunc paused=%{public}d ctorHasPaused=%{public}d ctorPaused=%{public}d shouldPauseAdded=%{public}d preActivity=%{public}d",
                 ad->paused ? 1 : 0, ctorHasPaused ? 1 : 0, ctorPaused ? 1 : 0,
                 s->shouldPauseAddedTorrents() ? 1 : 0, (int)tor->activity());
    // Explicitly drive the start state so a freshly-added torrent begins
    // downloading (or stays paused) per the `paused` flag, instead of relying
    // on the session's start-added-torrents setting — which left a just-added
    // torrent sitting in PAUSED state.
    if (ad->paused) {
      tr_torrentStop(tor);
    } else {
      tr_torrentStart(tor);
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                 "[DBG] addfunc postActivity=%{public}d isRunning=%{public}d",
                 (int)tor->activity(), tor->is_running() ? 1 : 0);
  } else if (dupTor != nullptr) {
    // Duplicate: report DUPLICATE (2). The OK_DELETE (3) case applies only
    // when every file is unwanted AND delete-source is set (source removed).
    ad->err = 2;
    if (ad->wantedFiles != nullptr && dupTor->file_count() > 0) {
      tr_file_index_t wantedCount = 0;
      for (tr_file_index_t i = 0; i < dupTor->file_count(); i++) {
        auto f = tr_torrentFile(dupTor, i);
        if (f.wanted) wantedCount++;
      }
      if (wantedCount == 0) {
        ad->err = ad->deleteSource ? 3 : 0;
      }
    }
  } else {
    ad->err = 1;  // PARSE_ERR
  }

  // 4.1: tr_ctorSetFilesWanted removed; set file DLs after creation
  if (tor != nullptr && ad->wantedFiles != nullptr && ad->idxLen > 0) {
    tr_torrentSetFileDLs(tor, ad->wantedFiles, ad->idxLen, true);
  }

  if (ad->outHash != nullptr && ad->outHashLen >= SHA_DIGEST_LENGTH) {
    auto const *metainfo = tr_ctorGetMetainfo(ad->ctor);
    if (metainfo != nullptr) {
      // 4.1: use info_hash() accessor
      auto const &hash = metainfo->info_hash();
      memcpy(ad->outHash, std::data(hash), SHA_DIGEST_LENGTH);
    }
  }
  return nullptr;
}

// ── Magnet / info-hash detection (D1, docs/11) ─────────────────────
// A magnet URI ("magnet:?xt=urn:btih:...") or a bare 40-hex info-hash is
// added natively: tr_ctorSetMetainfoFromMagnetLink parses the link and
// libtransmission fetches the metainfo from peers via BEP 9 (ut_metadata)
// in the background (metadataPercentComplete grows 0→1). Previously the
// string went to tr_ctorSetMetainfoFromFile and every magnet add failed
// with PARSE_ERR.
static bool isHexInfoHash(std::string_view s) {
  if (s.size() != 2 * (size_t) SHA_DIGEST_LENGTH) return false;
  for (char c : s) {
    if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')))
      return false;
  }
  return true;
}

static napi_value TorrentAdd(napi_env env, napi_callback_info info) {
  size_t argc = 8;
  napi_value args[8];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 2) {
    napi_throw_error(env, nullptr, "Expected at least 2 arguments: session, torrent path/uri");
    return nullptr;
  }

  // D1 (docs/11): build a magnet ctor when the input is a magnet URI or a
  // bare 40-hex info-hash; otherwise fall through to the file-based path.
  tr_ctor *ctor = nullptr;
  char *input = getStringUtf8(env, args[1]);
  if (input != nullptr) {
    std::string_view sv(input);
    if (sv.starts_with("magnet:") || isHexInfoHash(sv)) {
      std::string magnetUri = sv.starts_with("magnet:")
        ? std::string(sv)
        : "magnet:?xt=urn:btih:" + std::string(sv);
      ctor = tr_ctorNew(getSession(env, args[0]));
      if (ctor != nullptr &&
          !tr_ctorSetMetainfoFromMagnetLink(ctor, magnetUri.c_str(), nullptr)) {
        tr_ctorFree(ctor);
        ctor = nullptr;
      }
    }
  }
  free(input);
  if (ctor == nullptr) {
    ctor = ctorFromFile(env, args[0], args[1], false);
  }
  if (ctor == nullptr) {
    napi_value result;
    napi_create_int32(env, 1, &result);
    return result;
  }

  if (!isNapiNull(env, args[2])) {
    char *downloadDir = getStringUtf8(env, args[2]);
    if (downloadDir != nullptr) {
      tr_ctorSetDownloadDir(ctor, TR_FORCE, downloadDir);
    }
    free(downloadDir);
  }

  bool setDelete = getBoolNapi(env, args[3]);
  bool sequential = getBoolNapi(env, args[4]);
  (void)sequential;
  bool paused = (argc >= 8) ? getBoolNapi(env, args[7]) : false;

  // Force the initial run state on the ctor itself (TR_FORCE), matching the
  // upstream RPC path (rpcimpl.cc tr_ctorSetPaused(ctor, TR_FORCE, val)).
  // Without this, tr_torrentNew falls back to
  // session->shouldPauseAddedTorrents() (torrent-ctor.cc TR_FALLBACK), which
  // left freshly-added torrents PAUSED even though torrentAddFunc called
  // tr_torrentStart(). TR_FORCE makes the ctor's paused flag authoritative.
  tr_ctorSetPaused(ctor, TR_FORCE, paused);

  tr_file_index_t idxLen = 0;
  tr_file_index_t *wantedFiles = nullptr;
  if (!isNapiNull(env, args[5])) {
    void *idxData = nullptr;
    size_t idxByteLen = 0;
    // P1 fix (codex review): check the ArrayBuffer is present and its
    // length is a whole number of int32 elements before dereferencing.
    napi_get_arraybuffer_info(env, args[5], &idxData, &idxByteLen);
    if (idxData != nullptr && idxByteLen >= sizeof(int32_t) &&
        idxByteLen % sizeof(int32_t) == 0) {
      idxLen = (tr_file_index_t)(idxByteLen / sizeof(int32_t));
      int32_t *srcIdx = (int32_t *) idxData;
      wantedFiles = (tr_file_index_t *) malloc(idxLen * sizeof(tr_file_index_t));
      if (wantedFiles != nullptr) {
        for (tr_file_index_t i = 0; i < idxLen; i++)
          wantedFiles[i] = (tr_file_index_t) srcIdx[i];
      }
    }
  }

  bool deleteSource = false;
  tr_ctorSetDeleteSource(ctor, setDelete);
  tr_ctorGetDeleteSource(ctor, &deleteSource);

  uint8_t *outHash = nullptr;
  size_t outHashLen = 0;
  if (!isNapiNull(env, args[6])) {
    void *hashData = nullptr;
    // P1 fix (codex review): verify the output buffer is big enough before
    // copying the 20-byte info hash into it (checked inside torrentAddFunc).
    napi_get_arraybuffer_info(env, args[6], &hashData, &outHashLen);
    outHash = (uint8_t *) hashData;
  }

  TorrentAddData d;
  d.ctor = ctor;
  d.deleteSource = deleteSource;
  d.paused = paused;
  d.idxLen = idxLen;
  d.wantedFiles = wantedFiles;
  d.outHash = outHash;
  d.outHashLen = outHashLen;
  d.err = 1;

  runInTransmissionThread(__FILE__, __LINE__, env, args[0], torrentAddFunc, &d);
  free(wantedFiles);
  tr_ctorFree(ctor);

  napi_value result;
  napi_create_int32(env, d.err, &result);
  return result;
}

// ── torrentRemove ───────────────────────────────────────────────────
typedef struct { int32_t id; bool removeData; } TorrentRemoveData;
static void *torrentRemoveFunc(tr_session *s, void *d, Err *err) {
  auto *rd = (TorrentRemoveData *) d;
  tr_torrent *tor = findTorrentById(s, rd->id, err);
  if (tor) {
    // 4.1: tr_torrentRemove() re-dispatches to the session thread (fire-and-forget).
    // We are ALREADY on the session thread via runInTransmissionThread, so calling it
    // would queue a second task and return before the removal completes. Use the
    // InSessionThread variant, which runs inline and returns when the removal is done.
    tr_torrentRemoveInSessionThread(tor, rd->removeData, nullptr, nullptr, nullptr, nullptr);
  }
  return nullptr;
}
static napi_value TorrentRemove(napi_env env, napi_callback_info info) {
  size_t argc = 3; napi_value args[3];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  TorrentRemoveData d = {getInt32Napi(env, args[1]), getBoolNapi(env, args[2])};
  runInTransmissionThread(__FILE__, __LINE__, env, args[0], torrentRemoveFunc, &d);
  napi_value r; napi_get_undefined(env, &r); return r;
}

// ── torrentStart / torrentStop / torrentVerify ──────────────────────
// B1 (docs/11): the op now runs on the session event thread via
// runInTransmissionThread — previously tr_torrentStart/Stop/Verify ran
// directly on the calling (UI) thread.
#define DEF_TORRENT_OP(name, op) \
  static void *name##Func(tr_session *s, void *d, Err *err) { \
    tr_torrent *tor = findTorrentById(s, (int)(intptr_t)d, err); \
    if (tor) op(tor); \
    return nullptr; \
  } \
  static napi_value name(napi_env env, napi_callback_info info) { \
    size_t argc = 2; napi_value args[2]; \
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr); \
    int32_t id = getInt32Napi(env, args[1]); \
    runInTransmissionThread(__FILE__, __LINE__, env, args[0], \
        name##Func, (void *)(intptr_t)id); \
    napi_value r; napi_get_undefined(env, &r); return r; \
  }
// Custom TorrentStart that logs engine state before/after tr_torrentStart,
// so we can see exactly what an explicit start does to a fresh torrent.
static void *TorrentStartFunc(tr_session *s, void *d, Err *err) {
  tr_torrent *tor = findTorrentById(s, (int)(intptr_t)d, err);
  if (!tor) return nullptr;
  auto logState = [&](const char *tag) {
    auto dir = tor->queue_direction();
    auto errs = std::string(tor->error().errmsg());
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                 "[DBG] start %{public}s id=%{public}d act=%{public}d run=%{public}d queued=%{public}d dir=%{public}d total=%{public}lld localerr=%{public}d err='%{private}s'",
                 tag, tr_torrentId(tor), (int)tor->activity(), tor->is_running()?1:0,
                 tor->is_queued(dir)?1:0, (int)dir, (long long)tor->size_when_done(),
                 tor->error().error_type() == TR_STAT_LOCAL_ERROR?1:0, errs.c_str());
  };
  logState("BEFORE");
  tr_torrentStart(tor);
  logState("AFTER");
  return nullptr;
}
static napi_value TorrentStart(napi_env env, napi_callback_info info) {
  size_t argc = 2; napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int32_t id = getInt32Napi(env, args[1]);
  runInTransmissionThread(__FILE__, __LINE__, env, args[0],
      TorrentStartFunc, (void *)(intptr_t)id);
  napi_value r; napi_get_undefined(env, &r); return r;
}
DEF_TORRENT_OP(TorrentStop,   tr_torrentStop)
DEF_TORRENT_OP(TorrentVerify, tr_torrentVerify)

// ── torrentListFilesFromFile ────────────────────────────────────────
static napi_value TorrentListFilesFromFile(napi_env env, napi_callback_info info) {
  size_t argc = 1; napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  char *path = getStringUtf8(env, args[0]);
  if (path == nullptr) return nullptr;

  tr_ctor *ctor = tr_ctorNew(nullptr);
  if (!tr_ctorSetMetainfoFromFile(ctor, path, nullptr)) {
    free(path);
    tr_ctorFree(ctor);
    napi_throw_error(env, nullptr, "Failed to parse torrent file");
    return nullptr;
  }
  free(path);

  auto const *metainfo = tr_ctorGetMetainfo(ctor);
  if (metainfo == nullptr) {
    tr_ctorFree(ctor);
    napi_throw_error(env, nullptr, "No metainfo in torrent file");
    return nullptr;
  }

  // 4.1: use file_count() accessor instead of fileCount()
  tr_file_index_t fileCount = metainfo->file_count();
  napi_value result;
  napi_create_array_with_length(env, fileCount, &result);
  for (tr_file_index_t i = 0; i < fileCount; i++)
    napi_set_element(env, result, i, newStringUtf8(env, metainfo->file_subpath(i).c_str()));

  tr_ctorFree(ctor);
  return result;
}

// ── torrentListFiles ────────────────────────────────────────────────
typedef struct { int32_t id, count; char **names; } ListFilesData;
static void *torrentListFilesFunc(tr_session *s, void *d, Err *err) {
  auto *ld = (ListFilesData *) d;
  tr_torrent *tor = findTorrentById(s, ld->id, err);
  if (!tor) return nullptr;
  ld->count = (int)tor->file_count();
  if (!ld->count) return nullptr;
  ld->names = (char **) malloc(ld->count * sizeof(char *));
  if (!ld->names) { ld->count = 0; return nullptr; }
  for (int i = 0; i < ld->count; i++) {
    auto f = tr_torrentFile(tor, (tr_file_index_t)i);
    ld->names[i] = strdup(f.name);
  }
  return nullptr;
}
static napi_value TorrentListFiles(napi_env env, napi_callback_info info) {
  size_t argc = 2; napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  ListFilesData d = {getInt32Napi(env, args[1]), 0, nullptr};
  runInTransmissionThread(__FILE__, __LINE__, env, args[0], torrentListFilesFunc, &d);
  if (!d.count) { napi_value r; napi_get_null(env, &r); return r; }
  napi_value r; napi_create_array_with_length(env, d.count, &r);
  for (int i = 0; i < d.count; i++) {
    napi_set_element(env, r, i, newStringUtf8(env, d.names[i]));
    free(d.names[i]);
  }
  free(d.names); return r;
}

// ── torrentFindByHash ───────────────────────────────────────────────
typedef struct { uint8_t hash[SHA_DIGEST_LENGTH]; int32_t id; } FindByHashData;
static void *torrentFindByHashFunc(tr_session *s, void *d, Err *err) {
  auto *fh = (FindByHashData *) d;
  fh->id = findTorrentByHash(s, fh->hash, err);
  return nullptr;
}
static napi_value TorrentFindByHash(napi_env env, napi_callback_info info) {
  size_t argc = 2; napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  FindByHashData d;
  void *data = nullptr; size_t len = 0;
  napi_status status = napi_get_arraybuffer_info(env, args[1], &data, &len);
  if (status != napi_ok || data == nullptr || len < SHA_DIGEST_LENGTH) {
    napi_throw_error(env, nullptr, "Hash buffer too small, need 20 bytes");
    return nullptr;
  }
  memcpy(d.hash, data, SHA_DIGEST_LENGTH);
  runInTransmissionThread(__FILE__, __LINE__, env, args[0], torrentFindByHashFunc, &d);
  napi_value r; napi_create_int32(env, d.id, &r); return r;
}

// ── torrentGetName ──────────────────────────────────────────────────
static void *torrentGetNameFunc(tr_session *s, void *d, Err *err) {
  tr_torrent *tor = findTorrentById(s, (int)(intptr_t)d, err);
  return tor ? strdup(tor->name().c_str()) : nullptr;
}
static napi_value TorrentGetName(napi_env env, napi_callback_info info) {
  size_t argc = 2; napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int32_t tid = getInt32Napi(env, args[1]);
  char *name = (char *) runInTransmissionThread(__FILE__, __LINE__, env, args[0],
      torrentGetNameFunc, (void *)(intptr_t)tid);
  if (!name) { napi_value r; napi_get_null(env, &r); return r; }
  napi_value r = newStringUtf8(env, name); free(name); return r;
}

// ── torrentGetHash ──────────────────────────────────────────────────
typedef struct { int32_t id; uint8_t *hash; } GetHashData;
static void *torrentGetHashFunc(tr_session *s, void *d, Err *err) {
  auto *gh = (GetHashData *) d;
  tr_torrent *tor = findTorrentById(s, gh->id, err);
  if (tor) {
    // 4.1: tor->info_hash() is public
    auto const &hash = tor->info_hash();
    memcpy(gh->hash, std::data(hash), SHA_DIGEST_LENGTH);
  }
  return nullptr;
}
static napi_value TorrentGetHash(napi_env env, napi_callback_info info) {
  size_t argc = 3; napi_value args[3];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  void *hashBuf = nullptr; size_t hashBufLen = 0;
  napi_status status = napi_get_arraybuffer_info(env, args[2], &hashBuf, &hashBufLen);
  if (status != napi_ok || hashBuf == nullptr || hashBufLen < SHA_DIGEST_LENGTH) {
    napi_throw_error(env, nullptr, "Hash buffer too small, need 20 bytes");
    return nullptr;
  }
  GetHashData d = {getInt32Napi(env, args[1]), (uint8_t *) hashBuf};
  runInTransmissionThread(__FILE__, __LINE__, env, args[0], torrentGetHashFunc, &d);
  napi_value r; napi_get_undefined(env, &r); return r;
}

// ── torrentGetPieceHash ─────────────────────────────────────────────
typedef struct { int32_t id; int64_t idx; uint8_t *hash; } GetPieceHashData;
static void *torrentGetPieceHashFunc(tr_session *s, void *d, Err *err) {
  auto *ph = (GetPieceHashData *) d;
  tr_torrent *tor = findTorrentById(s, ph->id, err);
  if (tor && ph->idx >= 0 && ph->idx < (int64_t)tor->piece_count()) {
    // 4.1: tor->piece_hash(idx) is public
    auto const &pieceHash = tor->piece_hash((tr_piece_index_t)ph->idx);
    memcpy(ph->hash, std::data(pieceHash), SHA_DIGEST_LENGTH);
  }
  return nullptr;
}
// RESERVED (E1, docs/11): no ArkTS caller today. Corresponds to the original
// torrentGetPieceHash feature; kept for the D5 HTTP-streaming / file-preview
// reserve (per-piece hash integrity check).
static napi_value TorrentGetPieceHash(napi_env env, napi_callback_info info) {
  size_t argc = 4; napi_value args[4];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  void *hashBuf = nullptr; size_t hashBufLen = 0;
  // P1 fix (codex review): verify the output buffer holds 20 bytes before
  // torrentGetPieceHashFunc memcpy's the SHA-1 into it.
  napi_get_arraybuffer_info(env, args[3], &hashBuf, &hashBufLen);
  if (hashBuf == nullptr || hashBufLen < SHA_DIGEST_LENGTH) {
    napi_throw_error(env, nullptr, "Hash buffer too small, need 20 bytes");
    return nullptr;
  }
  GetPieceHashData d = {getInt32Napi(env, args[1]), getInt64FromBigInt(env, args[2]),
                        (uint8_t *) hashBuf};
  runInTransmissionThread(__FILE__, __LINE__, env, args[0], torrentGetPieceHashFunc, &d);
  napi_value r; napi_get_undefined(env, &r); return r;
}

// ── torrentSetPiecesHiPri ───────────────────────────────────────────
typedef struct { int32_t id; int64_t first, last; } SetPiecesHiPriData;
static void *torrentSetPiecesHiPriFunc(tr_session *s, void *d, Err *err) {
  auto *sp = (SetPiecesHiPriData *) d;
  tr_torrent *tor = findTorrentById(s, sp->id, err);
  if (!tor) return nullptr;
  tr_piece_index_t pc = tor->piece_count();
  tr_piece_index_t first = (tr_piece_index_t)sp->first;
  tr_piece_index_t last = (tr_piece_index_t)sp->last;
  if (last >= pc) last = pc - 1;
  if (first > last) return nullptr;

  // 4.1 has no per-piece priority setter — a piece's priority is derived from its
  // containing FILE (piece_priority() is read-only). Hi-pri a piece range by setting
  // TR_PRI_HIGH on every file whose piece span overlaps [first,last] (endPiece is
  // exclusive, so a file covers [beginPiece, endPiece) and overlaps the range iff
  // beginPiece <= last && endPiece > first).
  std::vector<tr_file_index_t> files;
  for (tr_file_index_t f = 0; f < tor->file_count(); ++f) {
    auto const view = tr_torrentFile(tor, f);
    if (view.beginPiece <= last && view.endPiece > first) files.push_back(f);
  }
  if (!files.empty()) {
    tr_torrentSetFilePriorities(tor, files.data(), (tr_file_index_t)files.size(), TR_PRI_HIGH);
  }
  return nullptr;
}
// RESERVED (E1, docs/11): no ArkTS caller today. Maps to the original
// set-pieces-high-priority feature; kept for the D5 sequential-download /
// play-while-downloading reserve. Implemented as FILE-level priority — 4.1 has no
// per-piece priority setter, so hi-pri a piece range by raising the containing files.
static napi_value TorrentSetPiecesHiPri(napi_env env, napi_callback_info info) {
  size_t argc = 4; napi_value args[4];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  SetPiecesHiPriData d = {getInt32Napi(env, args[1]), getInt64FromBigInt(env, args[2]),
                          getInt64FromBigInt(env, args[3])};
  runInTransmissionThread(__FILE__, __LINE__, env, args[0], torrentSetPiecesHiPriFunc, &d);
  napi_value r; napi_get_undefined(env, &r); return r;
}

// ── torrentFindFile ─────────────────────────────────────────────────
typedef struct { int32_t id, fileIdx; } FileData;
static void *torrentFindFileFunc(tr_session *s, void *d, Err *err) {
  auto *fd = (FileData *) d;
  tr_torrent *tor = findTorrentById(s, fd->id, err);
  if (!tor) return nullptr;
  getWantedFileInfo(tor, (uint32_t)fd->fileIdx, err);
  if (err->isSet) return nullptr;
  // 4.1: tr_torrentFindFile still exists
  auto path = tr_torrentFindFile(tor, (tr_file_index_t)fd->fileIdx);
  return strdup(path.c_str());
}
// RESERVED (E1, docs/11): no ArkTS caller today. Maps to the original
// torrentFindFile feature (locate a torrent's data on disk).
static napi_value TorrentFindFile(napi_env env, napi_callback_info info) {
  size_t argc = 3; napi_value args[3];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  FileData d = {getInt32Napi(env, args[1]), getInt32Napi(env, args[2])};
  char *path = (char *) runInTransmissionThread(__FILE__, __LINE__, env, args[0],
      torrentFindFileFunc, &d);
  if (!path) { napi_value r; napi_get_null(env, &r); return r; }
  napi_value r = newStringUtf8(env, path); free(path); return r;
}

// ── torrentGetFileName ──────────────────────────────────────────────
static void *torrentGetFileNameFunc(tr_session *s, void *d, Err *err) {
  auto *fd = (FileData *) d;
  tr_torrent *tor = findTorrentById(s, fd->id, err);
  if (!tor) return nullptr;
  tr_file_view f = getFileInfo(tor, (uint32_t)fd->fileIdx, err);
  if (err->isSet) return nullptr;
  return strdup(f.name);
}
static napi_value TorrentGetFileName(napi_env env, napi_callback_info info) {
  size_t argc = 3; napi_value args[3];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  FileData d = {getInt32Napi(env, args[1]), getInt32Napi(env, args[2])};
  char *name = (char *) runInTransmissionThread(__FILE__, __LINE__, env, args[0],
      torrentGetFileNameFunc, &d);
  if (!name) { napi_value r; napi_get_null(env, &r); return r; }
  napi_value r = newStringUtf8(env, name); free(name); return r;
}

// ── torrentGetFileStat (returns ArrayBuffer: 6 + N int64 values) ────
typedef struct { int32_t id, fileIdx, bfLen; int64_t *bf; bool alloc; } FileStatData;
static void *torrentGetFileStatFunc(tr_session *s, void *d, Err *err) {
  auto *fs = (FileStatData *) d;
  tr_torrent *tor = findTorrentById(s, fs->id, err);
  if (!tor) return nullptr;
  tr_file_view f = getFileInfo(tor, (uint32_t)fs->fileIdx, err);
  if (err->isSet) return nullptr;

  // 4.1: compute byte range from cumulative file sizes (file_size() is public)
  uint64_t byteStart = 0;
  for (tr_file_index_t i = 0; i < (tr_file_index_t)fs->fileIdx; i++) {
    byteStart += tor->file_size(i);
  }
  uint64_t byteEnd = byteStart + f.length;
  if (byteEnd > byteStart) byteEnd--;

  // 4.1: byte_loc() maps byte offset → Location with .piece field
  tr_piece_index_t firstPiece = tor->byte_loc(byteStart).piece;
  tr_piece_index_t lastPiece = tor->byte_loc(byteEnd).piece;

  tr_piece_index_t pc = tor->piece_count();
  if (pc == 0) return nullptr;
  int8_t *tabs = (int8_t *) malloc(pc);
  if (!tabs) return nullptr;
  tr_torrentAvailability(tor, tabs, (int)pc);

  size_t pieceRange = lastPiece - firstPiece + 1;
  size_t fc = (pieceRange + 63) / 64;
  int32_t sl = (int32_t)(fc + 6);
  // (size_t)sl must be compared, not (int32_t)(SIZE_MAX/8): the int32 cast of
  // ~2^61 truncates to a negative value, so a plain int32 compare ALWAYS
  // trips and this func returned a 0-length buffer for every file (breaking
  // file stat, DnD wanted-flip, and the FileTree view).
  if (sl < 0 || (size_t)sl > SIZE_MAX / sizeof(int64_t)) { free(tabs); return nullptr; }
  int64_t *bf = fs->bf;
  if (!bf) { bf = fs->bf = (int64_t *) malloc(sizeof(int64_t) * (size_t)sl); fs->alloc = true; }
  if (!bf) { free(tabs); return nullptr; }
  fs->bfLen = sl;

  bool complete = true;
  for (int32_t i = 6; i < sl; i++) {
    int64_t bfv = 0;
    tr_piece_index_t tIdx = firstPiece + (tr_piece_index_t)((i - 6) * 64);
    for (int n = 0; n < 64 && tIdx <= lastPiece; n++, tIdx++)
      if (tabs[tIdx] == -1) bfv |= (1LL << n); else complete = false;
    bf[i] = bfv;
  }

  bf[0] = tor->piece_size();
  bf[1] = f.length;
  bf[2] = (int64_t)byteStart;
  bf[3] = firstPiece;
  bf[4] = lastPiece;
  bf[5] = (!f.wanted) ? 2 : complete ? 1 : 0;
  free(tabs);
  return nullptr;
}
static napi_value TorrentGetFileStat(napi_env env, napi_callback_info info) {
  size_t argc = 4; napi_value args[4];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  FileStatData d = {getInt32Napi(env, args[1]), getInt32Napi(env, args[2]), 0, nullptr, false};
  runInTransmissionThread(__FILE__, __LINE__, env, args[0], torrentGetFileStatFunc, &d);
  // C5 (codex): runInTransmissionThread may have thrown (e.g. invalid file
  // index); with an exception pending, napi_create_arraybuffer would fail and
  // leave `out`/`r` uninitialized. Bail first and never touch a bad buffer.
  if (hasPendingException(env)) {
    if (d.alloc) free(d.bf);
    return nullptr;
  }
  napi_value r; void *out;
  size_t bfBytes = (size_t)d.bfLen * sizeof(int64_t);
  napi_create_arraybuffer(env, bfBytes, &out, &r);
  // C11 (codex): guard the copy — a 0-length stat (null/invalid-index torrent)
  // leaves d.bf null or unallocated; memcpy(dst, null, 0) is UB even at len 0.
  if (d.bf != nullptr && bfBytes > 0) {
    memcpy(out, d.bf, bfBytes);
  }
  if (d.alloc) free(d.bf);
  return r;
}

// ── torrentGetPiece ─────────────────────────────────────────────────
// Reads piece data directly from downloaded files via POSIX I/O.
// Transmission 4.1 made cache->readBlock() private, so we read from
// the on-disk files tr_torrentFindFile() resolves.
typedef struct { int32_t id, offset, len; int64_t pieceIdx; uint8_t *dst; } GetPieceData;
static void *torrentGetPieceFunc(tr_session *s, void *d, Err *err) {
  auto *gp = (GetPieceData *) d;
  tr_torrent *tor = findTorrentById(s, gp->id, err);
  if (!tor || !gp->dst || gp->len <= 0) return nullptr;

  tr_piece_index_t pieceIdx = static_cast<tr_piece_index_t>(gp->pieceIdx);
  if (pieceIdx >= tor->piece_count()) {
    memset(gp->dst, 0, (uint32_t)gp->len);
    return nullptr;
  }

  uint32_t pieceSize = tor->piece_size();

  // P1 fix (codex review): validate offset/len against the piece size before
  // computing byte ranges. A negative offset would underflow the uint64 math
  // and read from arbitrary file offsets; len beyond the piece would read
  // into the next piece's bytes.
  if (gp->offset < 0 || (uint64_t)gp->offset >= pieceSize ||
      gp->len <= 0 || (uint64_t)gp->len > (uint64_t)pieceSize - (uint64_t)gp->offset) {
    memset(gp->dst, 0, (uint32_t)gp->len);
    return nullptr;
  }

  uint64_t byteStart = pieceIdx * (uint64_t)pieceSize + (uint64_t)gp->offset;
  uint64_t byteEnd = byteStart + (uint64_t)gp->len;

  // Iterate through files to find which ones contain the requested byte range
  uint64_t fileByteOff = 0;
  tr_file_index_t fileCount = tor->file_count();
  size_t bytesRead = 0;

  for (tr_file_index_t i = 0; i < fileCount && bytesRead < (size_t)gp->len; i++) {
    uint64_t fileSize = tor->file_size(i);
    uint64_t fileEnd = fileByteOff + fileSize;

    // Check overlap: [fileByteOff, fileEnd) vs [byteStart, byteEnd)
    if (fileEnd <= byteStart || fileByteOff >= byteEnd) {
      fileByteOff = fileEnd;
      continue;
    }

    // Compute read boundaries within this file
    uint64_t readOff = (byteStart > fileByteOff) ? (byteStart - fileByteOff) : 0;
    uint64_t readEnd = (byteEnd < fileEnd) ? (byteEnd - fileByteOff) : fileSize;
    size_t readLen = (size_t)(readEnd - readOff);

    // Open the file and read
    std::string path = tr_torrentFindFile(tor, i);
    if (!path.empty()) {
      int fd = open(path.c_str(), O_RDONLY);
      if (fd >= 0) {
        ssize_t n = pread(fd, gp->dst + bytesRead, readLen, (off_t)readOff);
        if (n > 0) bytesRead += (size_t)n;
        close(fd);
      }
    }

    fileByteOff = fileEnd;
  }

  // Zero-fill any unread portion
  if (bytesRead < (size_t)gp->len) {
    memset(gp->dst + bytesRead, 0, (size_t)gp->len - bytesRead);
  }
  return nullptr;
}
// RESERVED (E1, docs/11): no ArkTS caller today. Maps to the original
// torrentGetPiece feature; kept for the D5 HTTP-streaming / preview reserve
// (read a specific piece's raw bytes).
static napi_value TorrentGetPiece(napi_env env, napi_callback_info info) {
  size_t argc = 6; napi_value args[6];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  void *dst = nullptr; size_t dstLen = 0;
  napi_status status = napi_get_arraybuffer_info(env, args[3], &dst, &dstLen);
  int32_t len = getInt32Napi(env, args[5]);
  // P1 fix (codex review): reject a destination buffer smaller than the
  // requested length before the native func writes into it.
  if (status != napi_ok || dst == nullptr || len < 0 || dstLen < (size_t)len) {
    napi_throw_error(env, nullptr, "Destination buffer too small for piece data");
    return nullptr;
  }
  GetPieceData d = {getInt32Napi(env, args[1]), getInt32Napi(env, args[4]),
                    len, getInt64FromBigInt(env, args[2]),
                    (uint8_t *) dst};
  runInTransmissionThread(__FILE__, __LINE__, env, args[0], torrentGetPieceFunc, &d);
  // C5 (codex): don't touch napi while a dispatch exception is pending.
  if (hasPendingException(env)) {
    return nullptr;
  }
  napi_value r; napi_get_undefined(env, &r); return r;
}

// ── torrentStatBrief (10 int64 per torrent) ─────────────────────────
typedef struct { int64_t *stat; int32_t statLen; bool alloc; } StatBriefData;
// [PROBE] One-shot HTTP reachability check using the app's own libcurl,
// run on the first poll. Distinguishes "app can't reach anything (INTERNET
// permission / sandbox / CA bundle)" from "tracker-specific failure".
// No passkey is used — the tracker probe hits only the bare https://host/.
static size_t HttpProbeDiscard(void *, size_t sz, size_t nm, void *) { return sz * nm; }

static void HttpProbeFetch(const char *label, const char *url) {
  // C7 (codex): ensure libcurl is globally initialized before the first
  // curl_easy_init on this detached probe thread.
  ensureCurlGlobalInit();
  CURL *c = curl_easy_init();
  if (!c) {
    OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG,
                 "[PROBE] %{public}s curl_easy_init FAILED", label);
    return;
  }
  char errbuf[CURL_ERROR_SIZE] = {0};
  char effip[64] = {0};
  double ct = 0;
  curl_easy_setopt(c, CURLOPT_URL, url);
  curl_easy_setopt(c, CURLOPT_WRITEFUNCTION, HttpProbeDiscard);
  curl_easy_setopt(c, CURLOPT_ERRORBUFFER, errbuf);
  curl_easy_setopt(c, CURLOPT_CONNECTTIMEOUT, 5L);
  curl_easy_setopt(c, CURLOPT_TIMEOUT, 8L);
  curl_easy_setopt(c, CURLOPT_SSL_VERIFYPEER, 1L);
  curl_easy_setopt(c, CURLOPT_USERAGENT, "transmissionbtm-probe");
  CURLcode rc = curl_easy_perform(c);
  curl_easy_getinfo(c, CURLINFO_PRIMARY_IP, effip);
  curl_easy_getinfo(c, CURLINFO_CONNECT_TIME, &ct);
  OH_LOG_Print(LOG_APP, rc == CURLE_OK ? LOG_INFO : LOG_WARN, LOG_DOMAIN, LOG_TAG,
               "[PROBE] %{public}s url=%{public}s rc=%{public}d ip=%{public}s connect=%.3fs err='%{public}s'",
               label, url, (int)rc, effip, ct, errbuf);
  curl_easy_cleanup(c);
}

static void HttpProbeOnce() {
  HttpProbeFetch("control", "https://example.com/");
  HttpProbeFetch("tracker", "https://tracker.m-team.cc/");
}

static void *torrentStatBriefFunc(tr_session *s, void *d, Err *err) {
  (void)err;
  static bool s_probe_done = false;
  if (!s_probe_done) {
    s_probe_done = true;
    // C1 (codex P1): the two synchronous curl probes block the session event
    // thread for up to ~16s on the first stats poll, stalling torrent ops and
    // the first UI refresh. Fire them on a detached thread; the first poll now
    // returns immediately. Probes are diagnostic-only (logged, never fatal).
    std::thread(HttpProbeOnce).detach();
  }
  auto *sb = (StatBriefData *) d;
  int n = (int)s->torrents().size();
  int sl = n * 10;
  if (!sb->stat || sl != sb->statLen) {
    int64_t *newStat = (int64_t *) malloc(sizeof(int64_t) * sl);
    if (!newStat) { sb->statLen = 0; return nullptr; }
    if (sb->alloc) free(sb->stat);
    sb->stat = newStat;
    sb->statLen = sl;
    sb->alloc = true;
  }
  int i = -10;
  for (auto tor : s->torrents()) {
    i += 10;
    auto st = tor->activity();
    sb->stat[i] = tr_torrentId(tor);
    sb->stat[i + 3] = tor->size_when_done();
    sb->stat[i + 4] = tor->left_until_done();
    // 4.1: bytes_uploaded_ is private. Use tr_torrentStat()->uploadedEver
    sb->stat[i + 5] = (int64_t)getUploadedEver(tor);
    if (tor->error().error_type() != TR_STAT_LOCAL_ERROR) {
      switch (st) {
        case TR_STATUS_STOPPED:
          sb->stat[i+1]=0;
          sb->stat[i+2]=(int64_t)(getPercentDone(tor)*100);
          // P1 fix (codex review): the old `continue` skipped writing the
          // stat[i+6..i+9] slots below, leaving uninitialized heap memory
          // exposed in the ArrayBuffer. Break so they get written as 0.
          break;
        case TR_STATUS_CHECK_WAIT:
        case TR_STATUS_CHECK:
          sb->stat[i+1]=1;
          sb->stat[i+2]=(int64_t)(getVerifyProgress(tor)*100);
          break;
        case TR_STATUS_DOWNLOAD_WAIT:
        case TR_STATUS_DOWNLOAD:
          sb->stat[i+1]=2;
          sb->stat[i+2]=(int64_t)(getPercentDone(tor)*100);
          break;
        case TR_STATUS_SEED_WAIT:
        case TR_STATUS_SEED:
          sb->stat[i+1]=3;
          sb->stat[i+2]=(int64_t)(getPercentDone(tor)*100);
          break;
      }
    } else {
      sb->stat[i+1]=4;
      sb->stat[i+2]=0;
    }
    // 4.1: swarm is private. Use tr_torrentStat() for peer info.
    auto stat = tr_torrentStat(tor);
    sb->stat[i+6] = stat->peersGettingFromUs;
    sb->stat[i+7] = stat->peersSendingToUs + stat->webseedsSendingToUs;
    sb->stat[i+8] = (int64_t)stat->pieceUploadSpeed_KBps;
    sb->stat[i+9] = (int64_t)stat->pieceDownloadSpeed_KBps;

    { // [DBG] live engine state per poll — expanded for the "downloads but
      // 0 bytes" investigation. dl_peers = peers SENDING us data (what we can
      // download from); ul_peers = peers GETTING data from us. Encr: 0=TOLERATED,
      // 1=PREFERRED, 2=REQUIRED (see tr_encryption_mode).
      auto dirq = tor->queue_direction();
      auto errs = std::string(tor->error().errmsg());
      auto const& scfg = s->settings();
      long long haveValid = (long long)tor->size_when_done() - (long long)tor->left_until_done();
      // Tracker announce state via tr_tracker_view. Only 'host' (${host}:${port})
      // and result/peer-int counters are printed — the full 'announce' URL may
      // embed a PT passkey and is deliberately NOT logged.
      std::string trk_cstr;
      size_t trk_n = tr_torrentTrackerCount(tor);
      for (size_t k = 0; k < trk_n; ++k) {
        auto tv = tr_torrentTracker(tor, k);
        if (k) trk_cstr += " | ";
        char tbuf[320];
        snprintf(tbuf, sizeof(tbuf),
                 "%s st=%d peers=%zu seed=%lld leech=%lld ok=%d to=%d res='%s'",
                 tv.host_and_port, (int)tv.announceState, tv.lastAnnouncePeerCount,
                 (long long)tv.seederCount, (long long)tv.leecherCount,
                 tv.lastAnnounceSucceeded?1:0, tv.lastAnnounceTimedOut?1:0,
                 tv.lastAnnounceResult);
        trk_cstr += tbuf;
      }
      OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                   "[DBG] stat id=%{public}d act=%{public}d run=%{public}d queued=%{public}d "
                   "total=%{public}lld have=%{public}lld left=%{public}lld "
                   "dl_peers=%{public}d ul_peers=%{public}d webseed=%{public}d "
                   "dlspeed=%{public}lld upspeed=%{public}lld "
                   "dht=%{public}d pex=%{public}d utp=%{public}d tcp=%{public}d pfw=%{public}d "
                   "encr=%{public}d dllim=%{public}d dllimKB=%{public}lld ullim=%{public}d ullimKB=%{public}lld "
                   "priv=%{public}d tdht=%{public}d tpex=%{public}d trk=%{public}lld "
                   "trkdbg='%{public}s' localerr=%{public}d err='%{public}s'",
                   tr_torrentId(tor), (int)st, tor->is_running()?1:0, tor->is_queued(dirq)?1:0,
                   (long long)tor->size_when_done(), haveValid,
                   (long long)tor->left_until_done(),
                   (int)stat->peersSendingToUs, (int)stat->peersGettingFromUs,
                   (int)stat->webseedsSendingToUs,
                   (long long)stat->pieceDownloadSpeed_KBps,
                   (long long)stat->pieceUploadSpeed_KBps,
                   scfg.dht_enabled?1:0, scfg.pex_enabled?1:0, scfg.utp_enabled?1:0,
                   scfg.tcp_enabled?1:0, scfg.port_forwarding_enabled?1:0,
                   (int)scfg.encryption_mode,
                   s->is_speed_limited(TR_DOWN)?1:0, (long long)scfg.speed_limit_down,
                   s->is_speed_limited(TR_UP)?1:0, (long long)scfg.speed_limit_up,
                   tor->is_private()?1:0, tor->allows_dht()?1:0, tor->allows_pex()?1:0,
                   (long long)tor->announce_list().size(),
                   trk_cstr.c_str(),
                   tor->error().error_type() == TR_STAT_LOCAL_ERROR?1:0, errs.c_str());
    }
  }
  return nullptr;
}
static napi_value TorrentStatBrief(napi_env env, napi_callback_info info) {
  size_t argc = 2; napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  StatBriefData d = {nullptr, 0, false};
  runInTransmissionThread(__FILE__, __LINE__, env, args[0], torrentStatBriefFunc, &d);
  // Empty session (0 torrents) and allocation-failure both end with statLen==0 /
  // stat==null. Return a 0-length buffer (not null) so the value is always a
  // valid ArrayBuffer — this matches the ArkTS-side contract (native.ts mock
  // torrentStatBrief → new ArrayBuffer(0)). The app's applyStatBrief guards
  // `byteLength < 80`, so a 0-length buffer is safe and skips the merge.
  if (d.stat == nullptr || d.statLen <= 0) {
    napi_value r; void *out;
    napi_create_arraybuffer(env, 0, &out, &r);
    if (d.alloc) free(d.stat); // malloc(0) returned a non-null ptr — release it
    return r;
  }
  size_t bytes = (size_t)d.statLen * sizeof(int64_t);
  napi_value r; void *out;
  napi_create_arraybuffer(env, bytes, &out, &r);
  memcpy(out, d.stat, bytes);
  if (d.alloc) free(d.stat);
  return r;
}

// ── torrentGetError ─────────────────────────────────────────────────
static void *torrentGetErrorFunc(tr_session *s, void *d, Err *err) {
  tr_torrent *tor = findTorrentById(s, (int)(intptr_t)d, err);
  // 4.1: tor->error().errmsg() returns a tr_interned_string (string_view-compatible)
  return tor ? strdup(std::string(tor->error().errmsg()).c_str()) : nullptr;
}
static napi_value TorrentGetError(napi_env env, napi_callback_info info) {
  size_t argc = 2; napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int32_t tid = getInt32Napi(env, args[1]);
  char *errStr = (char *) runInTransmissionThread(__FILE__, __LINE__, env, args[0],
      torrentGetErrorFunc, (void *)(intptr_t)tid);
  if (!errStr) { napi_value r; napi_get_null(env, &r); return r; }
  napi_value r = newStringUtf8(env, errStr); free(errStr); return r;
}

// ── torrentState (diagnostic: live engine state) ────────────────────
static void *torrentStateFunc(tr_session *s, void *d, Err *err) {
  tr_torrent *tor = findTorrentById(s, (int)(intptr_t)d, err);
  if (!tor) return strdup("notfound");
  auto dir = tor->queue_direction();
  auto errs = std::string(tor->error().errmsg());
  char buf[256];
  snprintf(buf, sizeof(buf),
           "act=%d run=%d queued=%d dir=%d total=%lld left=%lld localerr=%d err='%s'",
           (int)tor->activity(), tor->is_running()?1:0, tor->is_queued(dir)?1:0, (int)dir,
           (long long)tor->size_when_done(), (long long)tor->left_until_done(),
           tor->error().error_type() == TR_STAT_LOCAL_ERROR?1:0, errs.c_str());
  return strdup(buf);
}
static napi_value TorrentState(napi_env env, napi_callback_info info) {
  size_t argc = 2; napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int32_t tid = getInt32Napi(env, args[1]);
  char *state = (char *) runInTransmissionThread(__FILE__, __LINE__, env, args[0],
      torrentStateFunc, (void *)(intptr_t)tid);
  if (!state) { napi_value r; napi_get_null(env, &r); return r; }
  napi_value r = newStringUtf8(env, state); free(state); return r;
}

// ── torrentSetDnd ───────────────────────────────────────────────────
typedef struct { bool dnd; int32_t id; tr_file_index_t *files; tr_file_index_t count; } SetDndData;
static void *torrentSetDndFunc(tr_session *s, void *d, Err *err) {
  auto *sd = (SetDndData *) d;
  tr_torrent *tor = findTorrentById(s, sd->id, err);
  if (tor) {
    tr_torrentSetFileDLs(tor, sd->files, sd->count, !sd->dnd);
  }
  return nullptr;
}
static napi_value TorrentSetDnd(napi_env env, napi_callback_info info) {
  size_t argc = 4; napi_value args[4];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  SetDndData d;
  d.id = getInt32Napi(env, args[1]);
  d.dnd = getBoolNapi(env, args[3]);
  void *idxData = nullptr; size_t idxByteLen = 0;
  // P1 fix (codex review): require a well-formed int32 array buffer.
  napi_get_arraybuffer_info(env, args[2], &idxData, &idxByteLen);
  if (idxData == nullptr || idxByteLen % sizeof(int32_t) != 0) {
    napi_throw_error(env, nullptr, "Invalid file index array buffer");
    return nullptr;
  }
  d.count = (tr_file_index_t)(idxByteLen / sizeof(int32_t));
  d.files = (tr_file_index_t *) malloc(d.count * sizeof(tr_file_index_t));
  if (!d.files) {
    d.count = 0;
  } else if (d.count > 0) {
    int32_t *src = (int32_t *) idxData;
    for (tr_file_index_t i = 0; i < d.count; i++)
      d.files[i] = (tr_file_index_t) src[i];
  }
  runInTransmissionThread(__FILE__, __LINE__, env, args[0], torrentSetDndFunc, &d);
  free(d.files);
  napi_value r; napi_get_undefined(env, &r); return r;
}

// ── torrentSetLocation ──────────────────────────────────────────────
typedef struct { int32_t id; const char *path; } SetLocationData;
static void *torrentSetLocationFunc(tr_session *s, void *d, Err *err) {
  auto *sl = (SetLocationData *) d;
  tr_torrent *tor = findTorrentById(s, sl->id, err);
  if (tor) tr_torrentSetLocation(tor, sl->path, true, nullptr);
  return nullptr;
}
static napi_value TorrentSetLocation(napi_env env, napi_callback_info info) {
  size_t argc = 3; napi_value args[3];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  char *path = getStringUtf8(env, args[2]);
  if (path == nullptr) {
    napi_throw_error(env, nullptr, "Destination path must be a non-empty string");
    return nullptr;
  }
  // C9 (codex): validate the relocate path like curl.cc — prevent a
  // user-supplied path from being non-absolute or escaping via "..".
  if (path[0] != '/' || strstr(path, "..") != nullptr) {
    free(path);
    napi_throw_error(env, ERR_IO, "Destination path must be absolute, no traversal");
    return nullptr;
  }
  SetLocationData d = {getInt32Napi(env, args[1]), path};
  runInTransmissionThread(__FILE__, __LINE__, env, args[0], torrentSetLocationFunc, &d);
  free((void *) d.path);
  napi_value r; napi_get_undefined(env, &r); return r;
}

// ── torrentReannounce (tr_torrentManualUpdate) ───────────────────────
typedef struct { int32_t id; } ReannounceData;
static void *torrentReannounceFunc(tr_session *s, void *d, Err *err) {
  auto *rd = (ReannounceData *) d;
  tr_torrent *tor = findTorrentById(s, rd->id, err);
  if (tor) tr_torrentManualUpdate(tor);
  return nullptr;
}
static napi_value TorrentReannounce(napi_env env, napi_callback_info info) {
  size_t argc = 2; napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  ReannounceData d = {getInt32Napi(env, args[1])};
  runInTransmissionThread(__FILE__, __LINE__, env, args[0], torrentReannounceFunc, &d);
  napi_value r; napi_get_undefined(env, &r); return r;
}

// ── Module registration ─────────────────────────────────────────────
void RegisterTorrent(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
    {"torrentAdd",               nullptr, TorrentAdd,               nullptr, nullptr, nullptr, napi_default, nullptr},
    {"torrentRemove",            nullptr, TorrentRemove,            nullptr, nullptr, nullptr, napi_default, nullptr},
    {"torrentStart",             nullptr, TorrentStart,             nullptr, nullptr, nullptr, napi_default, nullptr},
    {"torrentStop",              nullptr, TorrentStop,              nullptr, nullptr, nullptr, napi_default, nullptr},
    {"torrentVerify",            nullptr, TorrentVerify,            nullptr, nullptr, nullptr, napi_default, nullptr},
    {"torrentListFilesFromFile", nullptr, TorrentListFilesFromFile, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"torrentListFiles",         nullptr, TorrentListFiles,         nullptr, nullptr, nullptr, napi_default, nullptr},
    {"torrentFindByHash",        nullptr, TorrentFindByHash,        nullptr, nullptr, nullptr, napi_default, nullptr},
    {"torrentGetName",           nullptr, TorrentGetName,           nullptr, nullptr, nullptr, napi_default, nullptr},
    {"torrentGetHash",           nullptr, TorrentGetHash,           nullptr, nullptr, nullptr, napi_default, nullptr},
    {"torrentGetPieceHash",      nullptr, TorrentGetPieceHash,      nullptr, nullptr, nullptr, napi_default, nullptr},
    {"torrentSetPiecesHiPri",    nullptr, TorrentSetPiecesHiPri,    nullptr, nullptr, nullptr, napi_default, nullptr},
    {"torrentFindFile",          nullptr, TorrentFindFile,          nullptr, nullptr, nullptr, napi_default, nullptr},
    {"torrentGetFileName",       nullptr, TorrentGetFileName,       nullptr, nullptr, nullptr, napi_default, nullptr},
    {"torrentGetFileStat",       nullptr, TorrentGetFileStat,       nullptr, nullptr, nullptr, napi_default, nullptr},
    {"torrentGetPiece",          nullptr, TorrentGetPiece,          nullptr, nullptr, nullptr, napi_default, nullptr},
    {"torrentStatBrief",         nullptr, TorrentStatBrief,         nullptr, nullptr, nullptr, napi_default, nullptr},
    {"torrentGetError",          nullptr, TorrentGetError,          nullptr, nullptr, nullptr, napi_default, nullptr},
    {"torrentState",             nullptr, TorrentState,             nullptr, nullptr, nullptr, napi_default, nullptr},
    {"torrentSetDnd",            nullptr, TorrentSetDnd,            nullptr, nullptr, nullptr, napi_default, nullptr},
    {"torrentSetLocation",       nullptr, TorrentSetLocation,       nullptr, nullptr, nullptr, napi_default, nullptr},
    {"torrentReannounce",        nullptr, TorrentReannounce,        nullptr, nullptr, nullptr, napi_default, nullptr}
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}

} // extern "C"
