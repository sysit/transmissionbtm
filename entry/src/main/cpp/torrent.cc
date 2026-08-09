// transmissionhm — Torrent CRUD + statistics (N-API)
// Adapted from transmissionbtc torrent.cc (JNI → N-API)
// Updated for Transmission 4.1 C++ API (2026-07-12)
// 20 exported functions
//
// Key 4.0.6→4.1 changes:
//   metainfo_ is private → use tor->info_hash(), tor->file_count(), etc.
//   completion_ is private → use tor->size_when_done(), tor->has_piece(), etc.
//   swarm is private → use tr_torrentStat() for peer counts and speeds
//   bytes_uploaded_ is private → use tr_torrentStat().uploaded_ever
//   cache is internal → read_block() removed; torrentGetPiece stubbed
//   tr_file_view → still exists, tr_torrentFile() unchanged
//   tor->error / tor->error_string → tor->error().is_local_error() / tor->error().errmsg()

#include "commons.h"
#include <libtransmission/transmission.h>
#include <libtransmission/peer-common.h>   // tr_swarm_stats, tr_swarmGetStats
#include <libtransmission/torrent.h>
#include <libtransmission/session.h>
#include <cstring>
#include <cstdlib>
#include <fcntl.h>
#include <unistd.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x0001
#define LOG_TAG "transmissionhm"

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
  return stat.uploaded_ever;
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
    if (ad->paused) {
      tr_torrentStop(tor);
    }
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
          !tr_ctorSetMetainfoFromMagnetLink(ctor, magnetUri, nullptr)) {
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
    tr_ctorSetDownloadDir(ctor, TR_FORCE, downloadDir);
    free(downloadDir);
  }

  bool setDelete = getBoolNapi(env, args[3]);
  bool sequential = getBoolNapi(env, args[4]);
  (void)sequential;
  bool paused = (argc >= 8) ? getBoolNapi(env, args[7]) : false;

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
  if (tor) tr_torrentRemove(tor, rd->removeData);
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
DEF_TORRENT_OP(TorrentStart,  tr_torrentStart)
DEF_TORRENT_OP(TorrentStop,   tr_torrentStop)
DEF_TORRENT_OP(TorrentVerify, tr_torrentVerify)

// ── torrentListFilesFromFile ────────────────────────────────────────
static napi_value TorrentListFilesFromFile(napi_env env, napi_callback_info info) {
  size_t argc = 1; napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  char *path = getStringUtf8(env, args[0]);
  if (path == nullptr) return nullptr;

  tr_ctor *ctor = tr_ctorNew(nullptr);
  if (!tr_ctorSetMetainfoFromFile(ctor, path)) {
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
  void *data; size_t len;
  napi_get_arraybuffer_info(env, args[1], &data, &len);
  if (len < SHA_DIGEST_LENGTH) {
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
  void *hashBuf; size_t hashBufLen;
  napi_get_arraybuffer_info(env, args[2], &hashBuf, &hashBufLen);
  if (hashBufLen < SHA_DIGEST_LENGTH) {
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
  if (tor && ph->idx < (int64_t)tor->piece_count()) {
    // 4.1: tor->piece_hash(idx) is public
    auto const &pieceHash = tor->piece_hash((tr_piece_index_t)ph->idx);
    memcpy(ph->hash, std::data(pieceHash), SHA_DIGEST_LENGTH);
  }
  return nullptr;
}
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
  bool changed = false;
  tr_piece_index_t pc = tor->piece_count();
  tr_piece_index_t first = (tr_piece_index_t)sp->first;
  tr_piece_index_t last = (tr_piece_index_t)sp->last;
  if (last >= pc) last = pc - 1;
  for (tr_piece_index_t i = first; i <= last && i < pc; i++) {
    auto prio = tor->bandwidth().get_priority();
    if (prio != TR_PRI_HIGH) {
      // FIXME: need 4.1 API to set piece priority per-piece
      changed = true;
    }
  }
  if (changed) { /* set_dirty() is private in 4.1 */ }
  return nullptr;
}
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
  if (sl > (int32_t)(SIZE_MAX / sizeof(int64_t))) return nullptr;
  int64_t *bf = fs->bf;
  if (!bf) { bf = fs->bf = (int64_t *) malloc(sizeof(int64_t) * (size_t)sl); fs->alloc = true; }
  if (!bf) return nullptr;
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
  napi_value r; void *out;
  napi_create_arraybuffer(env, d.bfLen * sizeof(int64_t), &out, &r);
  memcpy(out, d.bf, d.bfLen * sizeof(int64_t));
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
static napi_value TorrentGetPiece(napi_env env, napi_callback_info info) {
  size_t argc = 6; napi_value args[6];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  void *dst; size_t dstLen;
  napi_get_arraybuffer_info(env, args[3], &dst, &dstLen);
  int32_t len = getInt32Napi(env, args[5]);
  // P1 fix (codex review): reject a destination buffer smaller than the
  // requested length before the native func writes into it.
  if (dst == nullptr || len < 0 || dstLen < (size_t)len) {
    napi_throw_error(env, nullptr, "Destination buffer too small for piece data");
    return nullptr;
  }
  GetPieceData d = {getInt32Napi(env, args[1]), getInt32Napi(env, args[4]),
                    len, getInt64FromBigInt(env, args[2]),
                    (uint8_t *) dst};
  runInTransmissionThread(__FILE__, __LINE__, env, args[0], torrentGetPieceFunc, &d);
  napi_value r; napi_get_undefined(env, &r); return r;
}

// ── torrentStatBrief (10 int64 per torrent) ─────────────────────────
typedef struct { int64_t *stat; int32_t statLen; bool alloc; } StatBriefData;
static void *torrentStatBriefFunc(tr_session *s, void *d, Err *err) {
  (void)err;
  auto *sb = (StatBriefData *) d;
  int n = (int)s->torrents().size();
  int sl = n * 10;
  if (!sb->stat || sl != sb->statLen) {
    sb->stat = (int64_t *) malloc(sizeof(int64_t) * sl);
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
    // 4.1: bytes_uploaded_ is private. Use tr_torrentStat().uploaded_ever
    sb->stat[i + 5] = (int64_t)getUploadedEver(tor);
    if (!tor->error().is_local_error()) {
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
    sb->stat[i+6] = stat.peers_getting_from_us;
    sb->stat[i+7] = stat.peers_sending_to_us + stat.webseeds_sending_to_us;
    sb->stat[i+8] = (int64_t)stat.piece_upload_speed.base_quantity();
    sb->stat[i+9] = (int64_t)stat.piece_download_speed.base_quantity();
  }
  return nullptr;
}
static napi_value TorrentStatBrief(napi_env env, napi_callback_info info) {
  size_t argc = 2; napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  StatBriefData d = {nullptr, 0, false};
  runInTransmissionThread(__FILE__, __LINE__, env, args[0], torrentStatBriefFunc, &d);
  napi_value r; void *out;
  napi_create_arraybuffer(env, d.statLen * sizeof(int64_t), &out, &r);
  memcpy(out, d.stat, d.statLen * sizeof(int64_t));
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

// ── torrentSetDnd ───────────────────────────────────────────────────
typedef struct { bool dnd; int32_t id; tr_file_index_t *files; tr_file_index_t count; } SetDndData;
static void *torrentSetDndFunc(tr_session *s, void *d, Err *err) {
  auto *sd = (SetDndData *) d;
  tr_torrent *tor = findTorrentById(s, sd->id, err);
  if (tor) tr_torrentSetFileDLs(tor, sd->files, sd->count, !sd->dnd);
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
  if (d.files && d.count > 0) {
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
  SetLocationData d = {getInt32Napi(env, args[1]), getStringUtf8(env, args[2])};
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
    {"torrentSetDnd",            nullptr, TorrentSetDnd,            nullptr, nullptr, nullptr, napi_default, nullptr},
    {"torrentSetLocation",       nullptr, TorrentSetLocation,       nullptr, nullptr, nullptr, napi_default, nullptr},
    {"torrentReannounce",        nullptr, TorrentReannounce,        nullptr, nullptr, nullptr, napi_default, nullptr}
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}

} // extern "C"
