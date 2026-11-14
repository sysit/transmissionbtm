# transmissionbtm — Native build configuration
# M1: full 40-method N-API bridge with all third-party libraries.
# M0 → M1 switch completed 2026-06-28.
# Third-party sub-deps cross-compiled 2026-06-28.

cmake_minimum_required(VERSION 3.16)
project(transmissionbtm_napi)

# MUST be 17 — the engine (scripts/build-third-party.sh) is built with
# -std=gnu++17, and fmt's empty `alloc_` member is only collapsed by
# [[no_unique_address]] under C++20. Same headers, different standard →
# sizeof(tr_config_dir_lock) 4144 (engine) vs 4136 (bridge) → every tr_session
# member after config_dir_ shifts 8 bytes → session_thread_ read as
# blocklist_dir_'s data pointer → SIGSEGV in am_in_session_thread().
# Only surfaced with 4.1.4, which added config_dir_lock_ to tr_session.
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── Compiler flags ────────────────────────────────────────────
add_compile_options(-Wall -Wextra -Wpedantic -Werror=return-type)

# ── OH SDK libraries ──────────────────────────────────────────
find_library(NAPI_LIB ace_napi.z)
find_library(HILOG_LIB hilog_ndk.z)
find_library(ZLIB_LIB z)

# ── Third-party dir (cross-compiled static .a for OH arm64-v8a) ─
set(THIRD_PARTY ${CMAKE_SOURCE_DIR}/third_party)

# ── Source files (full bridge) ─────────────────────────────
set(SOURCES
    napi_init.cpp commons.cc transmission.cc torrent.cc
    native_to_arkts.cc curl.cc
)

# ── Build target ──────────────────────────────────────────────
add_library(transmissionbtm_napi SHARED ${SOURCES})

# ── Compile defs ──────────────────────────────────────────────
target_compile_definitions(transmissionbtm_napi PRIVATE
    M1_FULL_BRIDGE
    __TRANSMISSION__
    # The engine is built with -DWITH_CRYPTO=openssl, which CMake turns into
    # WITH_OPENSSL only for the engine's own translation units. The bridge
    # needs the same define or crypto-utils.h hits its `#error no crypto
    # library specified`. This used to be a hand-edited `#define WITH_OPENSSL`
    # pasted into third_party/.../crypto-utils.h — reinstalling headers wiped
    # it and the bridge stopped compiling (2026-11-09). Keep it here instead.
    WITH_OPENSSL=1
)

# 3.1 uses C++17/cable headers with no std::ranges, so the C++20 oh-compat.h
# force-include (4.2.0-only) is removed. The bridge builds as C++17 (see the
# CMAKE_CXX_STANDARD note above — this is an ABI requirement, not a style
# choice) and the 4.1.x transmission headers are C++17-clean.

# fmt is HEADER-ONLY in the bridge but its symbols live inside
# libtransmission.a. The vendored headers MUST be the same version the engine
# was built with (12.1.0, copied from .build-third-party/probe-410). A version
# mismatch compiles cleanly and corrupts the heap the first time the bridge
# constructs an engine class with fmt members (e.g. tr_torrent_metainfo):
# v9 inline ctor/dtor against a v12 object layout = SIGSEGV on the engine
# thread later. Verified 2026-11-08 (225/225 ohosTest after aligning).
target_include_directories(transmissionbtm_napi PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${THIRD_PARTY}/fmt/include
    ${THIRD_PARTY}/dht/include
    ${THIRD_PARTY}/openssl/include
    ${THIRD_PARTY}/curl/include
    ${THIRD_PARTY}/libevent/include
    ${THIRD_PARTY}/transmission/include
    ${THIRD_PARTY}/transmission/include/sigslot
    ${THIRD_PARTY}/psl/include
    ${THIRD_PARTY}/small/include
)

# ── M1 link: OH system libs + all cross-compiled static libs ──
# Order: own sources → transmission → sub-deps → curl → libevent → openssl → system
target_link_libraries(transmissionbtm_napi
    ${NAPI_LIB}
    ${HILOG_LIB}
    ${ZLIB_LIB}
    ${THIRD_PARTY}/transmission/lib/libtransmission.a
    ${THIRD_PARTY}/dht/lib/libdht.a
    ${THIRD_PARTY}/b64/lib/libb64.a
    ${THIRD_PARTY}/natpmp/lib/libnatpmp.a
    ${THIRD_PARTY}/miniupnpc/lib/libminiupnpc.a
    ${THIRD_PARTY}/utp/lib/libutp.a
    ${THIRD_PARTY}/psl/lib/libpsl.a
    # 4.1.1+ switched the engine's CRC to madler-crcany (#8529); 4.1.0 used
    # Google crc32c. Link the one the vendored engine was built against.
    ${THIRD_PARTY}/crcany/lib/libMadlerCrcany.a
    ${THIRD_PARTY}/deflate/lib/libdeflate.a
    ${THIRD_PARTY}/wildmat/lib/libwildmat.a
    ${THIRD_PARTY}/curl/lib/libcurl.a
    ${THIRD_PARTY}/libevent/lib/libevent_openssl.a
    ${THIRD_PARTY}/libevent/lib/libevent.a
    ${THIRD_PARTY}/libevent/lib/libevent_pthreads.a
    ${THIRD_PARTY}/openssl/lib/libssl.a
    ${THIRD_PARTY}/openssl/lib/libcrypto.a
)
