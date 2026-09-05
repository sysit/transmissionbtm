#!/usr/bin/env bash
# transmissionbtm — Cross-compile third-party libraries for OH arm64-v8a
#
# Build order:
#   1. OpenSSL 3.0.15 (LTS) — dependency for curl, libevent, transmission
#   2. libcurl 8.5.0 — dependency for transmission
#   3. libevent 2.1.12 — dependency for transmission
#   4. transmission fork + sub-deps (dht, b64, natpmp, miniupnpc, utp, etc.)
#
# All output lands in third_party/<lib>/{lib,include}/
#
# Usage: ./scripts/build-third-party.sh [openssl|curl|libevent|transmission|all]

set -euo pipefail

# ═══════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Libraries must be installed to entry/src/main/cpp/third_party/ —
# that's where CMakeLists.txt (THIRD_PARTY = ${CMAKE_SOURCE_DIR}/third_party) looks.
THIRD_PARTY="${PROJECT_ROOT}/entry/src/main/cpp/third_party"
BUILD_DIR="${PROJECT_ROOT}/.build-third-party"
DL_DIR="${BUILD_DIR}/downloads"

DEVECO="/Applications/DevEco-Studio.app/Contents"
OH_NDK="${DEVECO}/tools/sdk/default/openharmony/native"
OH_SYSROOT="${OH_NDK}/sysroot"
OH_LLVM_BIN="${OH_NDK}/llvm/bin"
OH_CMAKE_TOOLCHAIN="${OH_NDK}/build/cmake/ohos.toolchain.cmake"
OH_CMAKE="${OH_NDK}/build-tools/cmake/bin/cmake"

TARGET="aarch64-unknown-linux-ohos"
NPROC=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)

# Toolchain
export CC="${OH_LLVM_BIN}/clang"
export CXX="${OH_LLVM_BIN}/clang++"
export AR="${OH_LLVM_BIN}/llvm-ar"
export RANLIB="${OH_LLVM_BIN}/llvm-ranlib"
export STRIP="${OH_LLVM_BIN}/llvm-strip"

COMMON_FLAGS="--target=${TARGET} --sysroot=${OH_SYSROOT} -D__MUSL__ -fPIC"
COMMON_FLAGS+=" -fdata-sections -ffunction-sections -fstack-protector-strong"
# OH NDK ships clang 15.0.4 with incomplete C++20 libc++.
# Instead of replacing headers, we force-include oh-compat.h which provides
# shims for the missing features (std::ranges algorithms, views::keys/values,
# lexicographical_compare_three_way). A pre-build Python script replaces
# std::ranges::* → tr::* in the transmission source tree.
export CFLAGS="${COMMON_FLAGS} -O2"
export CXXFLAGS="${COMMON_FLAGS} -O2"
export LDFLAGS="-fuse-ld=lld --sysroot=${OH_SYSROOT} -Wl,--build-id=sha1 -Wl,-z,noexecstack -lhilog_ndk.z"

# Versions
OPENSSL_VERSION="3.0.15"
CURL_VERSION="8.5.0"
LIBEVENT_VERSION="2.1.12-stable"

echo "=== transmissionbtm third-party build ==="
echo "  Target:   ${TARGET}"
echo "  Sysroot:  ${OH_SYSROOT}"
echo "  CC:       ${CC}"
echo "  Jobs:     ${NPROC}"
echo "  Output:   ${THIRD_PARTY}"

mkdir -p "${THIRD_PARTY}" "${BUILD_DIR}" "${DL_DIR}"

# Add NDK bin to PATH so cmake finds clang
export PATH="${OH_LLVM_BIN}:${OH_CMAKE}:${PATH}"

TARGET_STEP="${1:-all}"

# ═══════════════════════════════════════════════════════════════════
# Utility: download if missing
# ═══════════════════════════════════════════════════════════════════

# Proxy for GitHub access
CURL_PROXY="--proxy socks5://172.16.1.254:1080"

download() {
  local url="$1" dest="$2" name="$3"
  if [ -f "${dest}" ]; then
    echo "  [skip] ${name} already downloaded"
  else
    echo "  Downloading ${name} ..."
    # Try with proxy first (for GitHub), fall back to direct
    curl -sSL ${CURL_PROXY} --retry 3 -o "${dest}" "${url}" 2>/dev/null || \
    curl -sSL --retry 3 --connect-timeout 30 -o "${dest}" "${url}" || {
      echo "  ERROR: Download failed for ${name}"
      echo "  URL: ${url}"
      echo "  Place the tarball manually at: ${dest}"
      exit 1
    }
  fi
}

# ═══════════════════════════════════════════════════════════════════
# 1. OpenSSL 3.0.15
# ═══════════════════════════════════════════════════════════════════

build_openssl() {
  local name="openssl-${OPENSSL_VERSION}"
  local tarball="${name}.tar.gz"
  local src_dir="${BUILD_DIR}/${name}"
  local prefix="${THIRD_PARTY}/openssl"
  local url="https://github.com/openssl/openssl/releases/download/${name}/${tarball}"

  echo ""
  echo "=== OpenSSL ${OPENSSL_VERSION} ==="

  if [ -f "${prefix}/lib/libssl.a" ] && [ -f "${prefix}/lib/libcrypto.a" ]; then
    echo "  Already built, skipping."
    return 0
  fi

  download "${url}" "${DL_DIR}/${tarball}" "OpenSSL"
  rm -rf "${src_dir}"
  tar xzf "${DL_DIR}/${tarball}" -C "${BUILD_DIR}"
  cd "${src_dir}"

  # Minimal static build — no engines, no legacy, no deprecated
  perl Configure linux-aarch64 \
    --prefix="${prefix}" \
    --openssldir="${prefix}/ssl" \
    no-shared \
    no-idea no-camellia no-seed no-bf no-cast no-rc2 \
    no-md2 no-md4 \
    no-engine no-tests no-dso no-dynamic-engine \
    no-afalgeng no-aria no-blake2 no-chacha no-cmac \
    no-cms no-comp no-ct no-des no-dh no-dsa no-ec2m \
    no-gost no-legacy no-mdc2 no-ocb no-poly1305 \
    no-rc4 no-rc5 no-rmd160 no-scrypt no-siphash \
    no-sm2 no-sm3 no-sm4 no-whirlpool no-zlib \
    -D__MUSL__ -DOPENSSL_NO_ASYNC -DOPENSSL_NO_COMP

  # OpenSSL Configure ignores CC/CXX for linux-aarch64; override in generated Makefile
  sed -i '' "s|^CC=.*|CC=${CC}|" Makefile
  sed -i '' "s|^CXX=.*|CXX=${CXX}|" Makefile
  sed -i '' "s|^AR=.*|AR=${AR}|" Makefile
  sed -i '' "s|^RANLIB=.*|RANLIB=${RANLIB}|" Makefile

  make -j${NPROC} build_sw 2>&1 | tail -20
  make install_sw 2>&1 | tail -5

  echo "  -> OpenSSL installed to ${prefix}"
  ls -lh "${prefix}/lib/libssl.a" "${prefix}/lib/libcrypto.a"
}

# ═══════════════════════════════════════════════════════════════════
# 2. libcurl 8.5.0
# ═══════════════════════════════════════════════════════════════════

build_curl() {
  local name="curl-${CURL_VERSION}"
  local tarball="${name}.tar.xz"
  local src_dir="${BUILD_DIR}/${name}"
  local prefix="${THIRD_PARTY}/curl"
  local url="https://curl.se/download/${tarball}"

  echo ""
  echo "=== libcurl ${CURL_VERSION} ==="

  if [ -f "${prefix}/lib/libcurl.a" ]; then
    echo "  Already built, skipping."
    return 0
  fi

  # curl needs OpenSSL built first
  if [ ! -f "${THIRD_PARTY}/openssl/lib/libssl.a" ]; then
    echo "  OpenSSL not built yet — building prerequisite..."
    build_openssl
  fi

  download "${url}" "${DL_DIR}/${tarball}" "libcurl"

  rm -rf "${src_dir}" "${BUILD_DIR}/curl-build"
  tar xf "${DL_DIR}/${tarball}" -C "${BUILD_DIR}"
  mkdir -p "${BUILD_DIR}/curl-build"
  cd "${BUILD_DIR}/curl-build"

  "${OH_CMAKE}" "${src_dir}" \
    -DCMAKE_TOOLCHAIN_FILE="${OH_CMAKE_TOOLCHAIN}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${prefix}" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_CURL_EXE=OFF \
    -DCURL_DISABLE_LDAP=ON \
    -DCURL_DISABLE_LDAPS=ON \
    -DCURL_DISABLE_NTLM=ON \
    -DCURL_USE_LIBSSH2=OFF \
    -DCURL_USE_LIBPSL=OFF \
    -DCURL_ZLIB=OFF \
    -DCURL_BROTLI=OFF \
    -DCURL_ZSTD=OFF \
    -DUSE_NGHTTP2=OFF \
    -DHTTP_ONLY=ON \
    -DENABLE_IPV6=ON \
    -DOPENSSL_ROOT_DIR="${THIRD_PARTY}/openssl" \
    -DOPENSSL_INCLUDE_DIR="${THIRD_PARTY}/openssl/include" \
    -DOPENSSL_CRYPTO_LIBRARY="${THIRD_PARTY}/openssl/lib/libcrypto.a" \
    -DOPENSSL_SSL_LIBRARY="${THIRD_PARTY}/openssl/lib/libssl.a" \
    -DCMAKE_C_FLAGS="${CFLAGS}" \
    -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
    -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
    2>&1 | tail -10

  make -j${NPROC} 2>&1 | tail -10
  make install 2>&1 | tail -5

  echo "  -> libcurl installed to ${prefix}"
  ls -lh "${prefix}/lib/libcurl.a"
}

# ═══════════════════════════════════════════════════════════════════
# 3. libevent 2.1.12-stable
# ═══════════════════════════════════════════════════════════════════

build_libevent() {
  local name="libevent-${LIBEVENT_VERSION}"
  local tarball="${name}.tar.gz"
  local src_dir="${BUILD_DIR}/${name}"
  local prefix="${THIRD_PARTY}/libevent"
  local url="https://github.com/libevent/libevent/releases/download/release-${LIBEVENT_VERSION}/${tarball}"

  echo ""
  echo "=== libevent ${LIBEVENT_VERSION} ==="

  if [ -f "${prefix}/lib/libevent.a" ]; then
    echo "  Already built, skipping."
    return 0
  fi

  if [ ! -f "${THIRD_PARTY}/openssl/lib/libssl.a" ]; then
    echo "  OpenSSL not built yet — building prerequisite..."
    build_openssl
  fi

  download "${url}" "${DL_DIR}/${tarball}" "libevent"

  rm -rf "${src_dir}" "${BUILD_DIR}/libevent-build"
  tar xzf "${DL_DIR}/${tarball}" -C "${BUILD_DIR}"
  mkdir -p "${BUILD_DIR}/libevent-build"
  cd "${BUILD_DIR}/libevent-build"

  "${OH_CMAKE}" "${src_dir}" \
    -DCMAKE_TOOLCHAIN_FILE="${OH_CMAKE_TOOLCHAIN}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${prefix}" \
    -DEVENT__DISABLE_BENCHMARK=ON \
    -DEVENT__DISABLE_TESTS=ON \
    -DEVENT__DISABLE_REGRESS=ON \
    -DEVENT__DISABLE_SAMPLES=ON \
    -DEVENT__LIBRARY_TYPE=STATIC \
    -DEVENT__DISABLE_OPENSSL=OFF \
    -DOPENSSL_ROOT_DIR="${THIRD_PARTY}/openssl" \
    -DOPENSSL_INCLUDE_DIR="${THIRD_PARTY}/openssl/include" \
    -DOPENSSL_CRYPTO_LIBRARY="${THIRD_PARTY}/openssl/lib/libcrypto.a" \
    -DOPENSSL_SSL_LIBRARY="${THIRD_PARTY}/openssl/lib/libssl.a" \
    -DCMAKE_C_FLAGS="${CFLAGS}" \
    -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
    -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
    2>&1 | tail -10

  make -j${NPROC} 2>&1 | tail -10
  make install 2>&1 | tail -5

  echo "  -> libevent installed to ${prefix}"
  ls -lh "${prefix}/lib/libevent.a" "${prefix}/lib/libevent_core.a" \
         "${prefix}/lib/libevent_extra.a" "${prefix}/lib/libevent_openssl.a" \
         "${prefix}/lib/libevent_pthreads.a" 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════════
# 4. transmission 4.1.0 (stable tag) + 18 submodules
#
# Built from the real 4.1.0 release tag (not a version-masked 4.2.0-dev).
# Transmission 4.1.0 is C++17 and does NOT use std::ranges, so the C++20
# compat machinery (oh-compat.h force-include, ranges->tr:: replacement) is
# NOT needed here — it existed only for the 4.2.x C++20 codebase.
# ═══════════════════════════════════════════════════════════════════

build_transmission() {
  echo ""
  echo "=== transmission 4.1.0 (stable) ==="

  local prefix="${THIRD_PARTY}/transmission"

  if [ -f "${prefix}/lib/libtransmission.a" ]; then
    echo "  Already built, skipping."
    return 0
  fi

  # Ensure prerequisites
  for lib in openssl curl libevent; do
    local check="${THIRD_PARTY}/${lib}/lib"
    if [ ! -d "${check}" ]; then
      echo "  ${lib} not built — building prerequisite..."
      "build_${lib}"
    fi
  done

  # Reuse the verified 4.1.0 clone already on disk (probe-410) instead of
  # re-cloning: the main clone fetch'd early-EOF'd over the proxy during the
  # attempted re-clone. probe-410 is the same `4.1.0` tag (2724011).
  local src_dir="${BUILD_DIR}/probe-410"
  local build_dir="${BUILD_DIR}/transmission-main-build"

  # Clone transmission 4.1.0 stable (shallow for speed)
  if [ ! -d "${src_dir}" ]; then
    echo "  Cloning transmission 4.1.0 stable..."
    git clone --depth 1 --branch 4.1.0 \
      https://github.com/transmission/transmission.git "${src_dir}" 2>&1 | tail -3
    cd "${src_dir}"
    echo "  Initializing submodules (18 total, via proxy)..."
    git submodule update --init --recursive --depth 1 2>&1 | tail -5
  else
    echo "  Using existing clone at ${src_dir}"
    # Ensure submodules are up to date
    cd "${src_dir}"
    if [ ! -f "${src_dir}/third-party/libpsl/CMakeLists.txt" ]; then
      echo "  Submodules not initialized — running git submodule update..."
      git submodule update --init --recursive --depth 1 2>&1 | tail -5
    fi
  fi

  # Patch variant.h: add non-template overload of try_emplace for tr_variant&&
  # Clang 15.0.4 has a template substitution failure when Val=tr_variant (move-only type)
  # in the generic template. A non-template exact-match overload avoids the issue.
  echo "  Patching variant.h: add non-template try_emplace(tr_quark, tr_variant&&)..."
  python3 -c '
with open("'"${src_dir}"'/libtransmission/variant.h", "r") as f:
    content = f.read()

# Already patched?
if "Non-template overload for tr_variant&&" in content:
    print("  variant.h already patched, skipping")
    exit(0)

old = """        template<typename Val>
        std::pair<tr_variant&, bool> try_emplace(tr_quark const key, Val&& val)
        {
            if (auto iter = find(key); iter != end())
            {
                return { iter->second, false };
            }

            return { vec_.emplace_back(key, tr_variant{ std::forward<Val>(val) }).second, true };
        }"""

new = """        // Non-template overload for tr_variant&& (avoids clang 15 template
        // substitution failure when Val=tr_variant, a move-only type)
        std::pair<tr_variant&, bool> try_emplace(tr_quark const key, tr_variant&& val)
        {
            if (auto iter = find(key); iter != end())
            {
                return { iter->second, false };
            }

            return { vec_.emplace_back(key, std::move(val)).second, true };
        }

        template<typename Val>
        std::pair<tr_variant&, bool> try_emplace(tr_quark const key, Val&& val)
        {
            if (auto iter = find(key); iter != end())
            {
                return { iter->second, false };
            }

            return { vec_.emplace_back(key, tr_variant{ std::forward<Val>(val) }).second, true };
        }"""

assert old in content, "variant.h: try_emplace template not found for patching"
content = content.replace(old, new, 1)
with open("'"${src_dir}"'/libtransmission/variant.h", "w") as f:
    f.write(content)
print("  variant.h patched successfully")
'

  # Patch rpcimpl.cc: register the tr_encryption_mode serializer in the SAME
  # translation unit that reads it. The `encryption` session-get field is the only
  # getter routed through Converters::serialize<tr_encryption_mode>(), which reads a
  # lazily-populated static-inline `converter_storage<T>` registry. If that TU
  # hasn't had ensure_default_converters() run, serialize<T>() falls through to its
  # "no serializer registered" branch and emits `"encryption"` with no value →
  # the web client's JSON.parse fails. (FIXED + on-device verified 2026-09-05.)
  echo "  Patching rpcimpl.cc: ensure_default_converters() in sessionGet..."
  python3 -c '
src = "'"${src_dir}"'/libtransmission/rpcimpl.cc"
with open(src, "r") as f:
    content = f.read()

if "Converters::ensure_default_converters" in content:
    print("  rpcimpl.cc already patched, skipping")
    exit(0)

# Anchor on sessionGet() so we hit ITS accessors line, not the other callers.
sig = "sessionGet("
sig_idx = content.find(sig)
assert sig_idx != -1, "rpcimpl.cc: sessionGet signature not found"
anchor = "auto const& accessors = session_accessors();"
idx = content.find(anchor, sig_idx)
assert idx != -1, "rpcimpl.cc: sessionGet accessors line not found"
eol = content.find("\n", idx)
insert_at = eol + 1
marker = "\n    libtransmission::serializer::Converters::ensure_default_converters();\n"
content = content[:insert_at] + marker + content[insert_at:]

with open(src, "w") as f:
    f.write(content)
print("  rpcimpl.cc patched successfully")
'

  # Replace std::ranges::* / std::views::* / std::lexicographical_compare_three_way
  # with tr::* equivalents. The oh-compat.h header (force-included below) provides
  # C++17-based implementations of these missing C++20 features.
  #
  # IMPORTANT: std::ranges::begin/end/cbegin/cend/rbegin/rend DO work in OH libc++
  # and are NOT in this list. std::ranges::subrange and std::ranges::reverse_view
  # are TYPES that also work in OH libc++ — NOT replaced.
  #
  # View adaptor replacements:
  #   std::views::keys/values  → tr::keys_of/values_of
  #   std::views::reverse      → tr::reverse_of
  #   std::views::take         → tr::take_of
  #   std::views::drop         → tr::drop_of
  echo "  Replacing C++20 patterns with tr:: compatibility shims..."
  python3 -c '
import os, sys

src = "'"${src_dir}"'"
replacements = {
    # ── View adaptors (must come first — algorithm names contain substrings) ──
    "std::views::keys(":             "tr::keys_of(",
    "std::views::values(":           "tr::values_of(",
    "std::views::reverse":           "tr::reverse_of",
    "std::ranges::reverse_view(":     "tr::reverse_of(",
    "std::views::take(":             "tr::take_of(",
    "std::views::drop(":             "tr::drop_of(",
    # ── 0-arg algorithms ──
    "std::ranges::adjacent_find(":   "tr::adjacent_find(",
    "std::ranges::max_element(":     "tr::max_element(",
    # ── 1-arg algorithms ──
    "std::ranges::all_of(":          "tr::all_of(",
    "std::ranges::any_of(":          "tr::any_of(",
    "std::ranges::none_of(":         "tr::none_of(",
    "std::ranges::count_if(":        "tr::count_if(",
    "std::ranges::find_if_not(":     "tr::find_if_not(",
    "std::ranges::for_each(":        "tr::for_each(",
    "std::ranges::partition(":       "tr::partition(",
    "std::ranges::stable_partition(":"tr::stable_partition(",
    "std::ranges::shuffle(":         "tr::shuffle(",
    # ── 2-arg algorithms (value/predicate) ──
    "std::ranges::find(":            "tr::find(",
    "std::ranges::find_if(":         "tr::find_if(",
    "std::ranges::binary_search(":   "tr::binary_search(",
    "std::ranges::sort(":            "tr::sort(",
    "std::ranges::copy_if(":         "tr::copy_if(",
    # ── Special multi-arg ──
    "std::ranges::partial_sort(":    "tr::partial_sort(",
    "std::ranges::partial_sort_copy(":"tr::partial_sort_copy(",
    "std::ranges::equal_range(":     "tr::equal_range(",
    "std::ranges::lower_bound(":     "tr::lower_bound(",
    "std::ranges::search(":          "tr::search(",
    "std::ranges::remove(":          "tr::remove(",
    "std::ranges::unique(":          "tr::unique(",
    "std::ranges::copy(":            "tr::copy(",
    "std::ranges::transform(":       "tr::transform(",
    "std::ranges::set_difference(":  "tr::set_difference(",
    "std::ranges::unique_copy(":     "tr::unique_copy(",
    "std::ranges::equal(":           "tr::equal(",
    # ── ranges::distance / rbegin / rend / cbegin / cend — use classic std:: versions ──
    "std::ranges::distance(":         "std::distance(",
    "std::ranges::rbegin(":           "std::rbegin(",
    "std::ranges::rend(":             "std::rend(",
    "std::ranges::cbegin(":           "std::cbegin(",
    "std::ranges::cend(":             "std::cend(",
    # ── lexicographical_compare_three_way ──
    "std::lexicographical_compare_three_way(": "tr::lexicographical_compare_three_way(",
}

count = 0
for root, dirs, files in os.walk(os.path.join(src, "libtransmission")):
    # skip third-party submodules
    dirs[:] = [d for d in dirs if d not in ("third-party", ".git")]
    for fn in files:
        if not (fn.endswith(".cc") or fn.endswith(".h") or fn.endswith(".cpp")):
            continue
        fpath = os.path.join(root, fn)
        with open(fpath, "r") as f:
            content = f.read()
        changed = False
        for old, new in replacements.items():
            if old in content:
                content = content.replace(old, new)
                changed = True
        if changed:
            with open(fpath, "w") as f:
                f.write(content)
            count += 1

print(f"  Patched {count} files with compat shims")
'
  # Transmission 4.1.0 is C++17 (per its own CMakeLists) and uses no std::ranges,
  # so the C++20 oh-compat.h shim is not needed and is not present in the 4.1.0
  # source tree. Keep the source dir on the include path for the local headers.
  CXXFLAGS+=" -I${src_dir}/libtransmission"

  rm -rf "${build_dir}"
  mkdir -p "${build_dir}"
  cd "${build_dir}"

  echo "  Running CMake configure..."

  # Transmission 4.1 uses C++20 and 18 submodules.
  # We use the OH toolchain with explicit paths for prebuilt OpenSSL, curl, libevent.
  # The OH toolchain sets CMAKE_FIND_ROOT_PATH_MODE=ONLY, so find_path/find_library
  # ONLY search CMAKE_FIND_ROOT_PATH (not CMAKE_PREFIX_PATH). Add the third-party base
  # to FIND_ROOT_PATH so find_package(CURL/OpenSSL/libevent) locates our prebuilt libs.
  #
  # NOTE: comment lines must NOT sit inside the backslash-continued cmake argument
  # list — a `#` ends the logical line and silently drops every later -D flag. Keep
  # all prose above the command.
  #
  # 4.1.0 has NO ENABLE_WEB option (inert residue from the ancestor port). The
  # RPC/web server (libtransmission/rpc-server.cc) compiles unconditionally, so
  # only REBUILD_WEB/INSTALL_WEB matter (and only for asset install, which we
  # don't ship). Leave REBUILD_WEB=OFF; no public_html is packaged.
  "${OH_CMAKE}" "${src_dir}" \
    -DCMAKE_TOOLCHAIN_FILE="${OH_CMAKE_TOOLCHAIN}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${prefix}" \
    -DCMAKE_FIND_ROOT_PATH="${THIRD_PARTY}" \
    -DCMAKE_PREFIX_PATH="${THIRD_PARTY}/openssl;${THIRD_PARTY}/curl;${THIRD_PARTY}/libevent" \
    -DENABLE_DAEMON=OFF \
    -DENABLE_GTK=OFF \
    -DENABLE_QT=OFF \
    -DENABLE_CLI=OFF \
    -DENABLE_TESTS=OFF \
    -DENABLE_NLS=OFF \
    -DENABLE_MAC=OFF \
    -DENABLE_UTILS=OFF \
    -DINSTALL_DOC=OFF \
    -DINSTALL_LIB=ON \
    -DREBUILD_WEB=OFF \
    -DRUN_CLANG_TIDY=OFF \
    -DWITH_CRYPTO=openssl \
    -DWITH_INOTIFY=AUTO \
    -DWITH_KQUEUE=AUTO \
    -DUSE_SYSTEM_EVENT2=OFF \
    -DUSE_SYSTEM_DEFLATE=OFF \
    -DUSE_SYSTEM_DHT=OFF \
    -DUSE_SYSTEM_MINIUPNPC=OFF \
    -DUSE_SYSTEM_NATPMP=OFF \
    -DUSE_SYSTEM_B64=OFF \
    -DUSE_SYSTEM_UTP=OFF \
    -DUSE_SYSTEM_PSL=OFF \
    -DUSE_SYSTEM_FAST_FLOAT=OFF \
    -DUSE_SYSTEM_FMT=OFF \
    -DUSE_SYSTEM_SIGSLOT=OFF \
    -DUSE_SYSTEM_SMALL=OFF \
    -DUSE_SYSTEM_UTF8CPP=OFF \
    -DUSE_SYSTEM_WIDE_INTEGER=OFF \
    -DOPENSSL_ROOT_DIR="${THIRD_PARTY}/openssl" \
    -DOPENSSL_INCLUDE_DIR="${THIRD_PARTY}/openssl/include" \
    -DOPENSSL_CRYPTO_LIBRARY="${THIRD_PARTY}/openssl/lib/libcrypto.a" \
    -DOPENSSL_SSL_LIBRARY="${THIRD_PARTY}/openssl/lib/libssl.a" \
    -DCURL_INCLUDE_DIR="${THIRD_PARTY}/curl/include" \
    -DCURL_LIBRARY="${THIRD_PARTY}/curl/lib/libcurl.a" \
    -DCMAKE_C_FLAGS="${CFLAGS}" \
    -DCMAKE_CXX_FLAGS="${CXXFLAGS}" \
    -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
    -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
    2>&1 | tail -30

  echo "  Building libtransmission + sub-deps (${NPROC} jobs)..."
  make -j${NPROC} transmission 2>&1 | tail -30

  # Install: copy .a files + headers
  mkdir -p "${prefix}/lib" "${prefix}/include/transmission"

  # Main transmission library
  cp libtransmission/libtransmission.a "${prefix}/lib/" 2>/dev/null || true

  # Sub-dependency .a files from ExternalProject builds
  # These land in third-party/<name>.bld/pfx/lib/
  for pkg in deflate natpmp miniupnpc dht psl; do
    find "${build_dir}" -path "*/${pkg}*.bld/pfx/lib/*.a" -exec cp {} "${prefix}/lib/" \; 2>/dev/null || true
  done

  # Sub-dependency .a files from SUBPROJECT / direct builds
  # 4.1 vendors Google crc32c (crc32c::Extend), not madler-crcany
  for pkg in b64 utp wildmat crc32c; do
    find "${build_dir}" -name "lib${pkg}.a" -exec cp {} "${prefix}/lib/" \; 2>/dev/null || true
  done

  # Copy main transmission headers (preserve dir layout)
  cp -r "${src_dir}/libtransmission"/*.h "${prefix}/include/transmission/" 2>/dev/null || true

  echo "  -> transmission 4.1 installed to ${prefix}"
  echo "  .a files:"
  ls -lh "${prefix}/lib/"*.a 2>/dev/null || echo "  (no .a files found)"
}

# ═══════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════

case "${TARGET_STEP}" in
  openssl)     build_openssl ;;
  curl)        build_curl ;;
  libevent)    build_libevent ;;
  transmission) build_transmission ;;
  all)
    build_openssl
    build_curl
    build_libevent
    build_transmission
    ;;
  *)
    echo "Usage: $0 [openssl|curl|libevent|transmission|all]"
    exit 1
    ;;
esac

echo ""
echo "=== Done ==="
find "${THIRD_PARTY}" -name "*.a" -exec ls -lh {} \; 2>/dev/null || echo "(no .a files found)"
