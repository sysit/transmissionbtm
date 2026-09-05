# transmissionbtm — Native build configuration
# M1: full 40-method N-API bridge with all third-party libraries.
# M0 → M1 switch completed 2026-06-28.
# Third-party sub-deps cross-compiled 2026-06-28.

cmake_minimum_required(VERSION 3.16)
project(transmissionbtm_napi)

set(CMAKE_CXX_STANDARD 20)
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
)

# 3.1 uses C++17/cable headers with no std::ranges, so the C++20 oh-compat.h
# force-include (4.2.0-only) is removed. The bridge builds as C++20 but the
# 4.1.0 transmission headers are C++17-clean and need no compat shim.

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
    ${THIRD_PARTY}/crc32c/lib/libcrc32c.a
    ${THIRD_PARTY}/deflate/lib/libdeflate.a
    ${THIRD_PARTY}/wildmat/lib/libwildmat.a
    ${THIRD_PARTY}/curl/lib/libcurl.a
    ${THIRD_PARTY}/libevent/lib/libevent_openssl.a
    ${THIRD_PARTY}/libevent/lib/libevent.a
    ${THIRD_PARTY}/libevent/lib/libevent_pthreads.a
    ${THIRD_PARTY}/openssl/lib/libssl.a
    ${THIRD_PARTY}/openssl/lib/libcrypto.a
)
