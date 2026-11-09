#!/usr/bin/env node
// transmissionbtm — static defect audit.
//
// Each check encodes one assumption that has already been broken in this repo
// or that silently degrades a shipped build. They are the classes a human
// reading a diff reliably misses and a script catches every time.
//
//   node scripts/audit.mjs          # blocking findings only
//   node scripts/audit.mjs --strict # list advisories too
//
// Exit 1 on any blocking finding (or any advisory with --strict).

import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const ROOT = new URL('..', import.meta.url).pathname;
const STRICT = process.argv.includes('--strict');
const findings = [];
const add = (level, check, file, line, msg) =>
  findings.push({ level, check, file: relative(ROOT, file), line, msg });

// ── helpers ─────────────────────────────────────────────────────────

function walk(dir, ext, out = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) {
      if (name === 'node_modules' || name === 'build' || name.startsWith('.')) continue;
      walk(p, ext, out);
    } else if (name.endsWith(ext)) {
      out.push(p);
    }
  }
  return out;
}

const read = (p) => readFileSync(p, 'utf8');
const ETS = () => walk(join(ROOT, 'entry/src/main/ets'), '.ets');
const CPP = () => walk(join(ROOT, 'entry/src/main/cpp'), '.cc')
  .concat(walk(join(ROOT, 'entry/src/main/cpp'), '.cpp'));

// ── B1: error masking ───────────────────────────────────────────────
// A catch that reports an error must expose WHY. `String(err)` on an ArkTS
// BusinessError renders "[object Object]" — exactly how the URL-download
// failure hid a TLS error behind a useless toast. Acceptable: errText(),
// .message, or a comment stating the silent fallback is deliberate.
function checkErrorMasking() {
  for (const file of ETS()) {
    const lines = read(file).split('\n');
    lines.forEach((line, i) => {
      if (!/\}\s*catch\s*(\([^)]*\))?\s*\{/.test(line)) return;
      // Seed with the catch line itself: `catch (e) { /* ignore */ }` states
      // its intent on the same line as the brace.
      let depth = 1;
      const body = [line];
      for (let j = i + 1; j < Math.min(lines.length, i + 40) && depth > 0; j++) {
        depth += (lines[j].match(/\{/g) || []).length - (lines[j].match(/\}/g) || []).length;
        body.push(lines[j]);
      }
      const text = body.join('\n');
      // noteError() is PreferencesManager's single error sink — it calls
      // errText() and records the reason for the UI (D1). Recognizing it keeps
      // the rule "errors are reported through one named path" intact.
      const handles = /errText\s*\(|noteError\s*\(|\.message|\.code/.test(text);
      if (!handles && /\/\/|\/\*/.test(text))
        add('ADVISORY', 'error-masking', file, i + 1, 'silent catch (comment only) — confirm the fallback is safe');
      else if (!handles)
        add('BLOCKING', 'error-masking', file, i + 1, 'catch swallows the error (no .message/errText, no comment)');
    });
  }
}

// ── B2: N-API three-way drift ───────────────────────────────────────
// registered in C++ ↔ declared in .d.ts ↔ called from ArkTS. Drift means a
// method exists but is unreachable, or a call type-checks but throws at runtime.
function checkNapiDrift() {
  const registered = new Set();
  for (const f of CPP())
    for (const m of read(f).matchAll(/\{\s*"([A-Za-z_]\w*)"\s*,\s*nullptr\s*,/g)) registered.add(m[1]);

  const dtsFile = join(ROOT, 'entry/src/main/cpp/types/libtransmissionbtm_napi/Index.d.ts');
  const declared = new Set([...read(dtsFile).matchAll(/function\s+([A-Za-z_]\w*)\s*\(/g)].map((m) => m[1]));

  const called = new Set();
  for (const f of ETS())
    for (const m of read(f).matchAll(/native\.([A-Za-z_]\w*)\s*\(/g)) called.add(m[1]);

  for (const n of registered) if (!declared.has(n))
    add('BLOCKING', 'napi-drift', dtsFile, 0, `${n} registered in C++ but missing from Index.d.ts`);
  for (const n of declared) if (!registered.has(n))
    add('BLOCKING', 'napi-drift', dtsFile, 0, `${n} declared in Index.d.ts but not registered in C++`);
  for (const n of called) if (!registered.has(n))
    add('BLOCKING', 'napi-drift', join(ROOT, 'entry/src/main/ets'), 0, `${n} called from ArkTS but not registered in C++`);
  for (const n of declared) if (!called.has(n))
    add('ADVISORY', 'napi-drift', dtsFile, 0, `${n} declared but never called from ArkTS`);
}

// ── B3: $r resource coverage ────────────────────────────────────────
// A key missing from one locale renders as a raw key (or blank) only on
// devices set to that locale — invisible to whoever tests in one language.
function checkResourceCoverage() {
  const used = new Set();
  for (const f of ETS())
    for (const m of read(f).matchAll(/\$r\('app\.string\.([A-Za-z0-9_]+)'/g)) used.add(m[1]);

  for (const locale of ['base', 'zh_CN']) {
    const file = join(ROOT, `entry/src/main/resources/${locale}/element/string.json`);
    const defined = new Set(JSON.parse(read(file)).string.map((s) => s.name));
    for (const k of used) if (!defined.has(k))
      add('BLOCKING', 'rstring', file, 0, `$r('app.string.${k}') used but not defined in ${locale}`);
  }
}

// ── B4: build-config invariants ─────────────────────────────────────
function checkBuildConfig() {
  const file = join(ROOT, 'build-profile.json5');
  const text = read(file);
  const api = (k) => Number((text.match(new RegExp(`"${k}"\\s*:\\s*"[^"]*?(\\d+)\\)"`)) || [])[1] || 0);

  const compatible = api('compatibleSdkVersion');
  const target = api('targetSdkVersion');
  if (compatible && target && compatible > target)
    add('BLOCKING', 'build-config', file, 0, `compatibleSdkVersion(${compatible}) > targetSdkVersion(${target}) — hvigor fails 00303015`);

  // A debug build signed with the release cert is rejected by a real device
  // (9568322) — and an emulator happily installs it, so the mistake ships.
  for (const m of text.matchAll(/"signingConfig"\s*:\s*"([^"]+)"/g)) {
    if (m[1] !== 'default')
      add('BLOCKING', 'build-config', file, 0, `product signingConfig is "${m[1]}" — debug builds become uninstallable (9568322)`);
  }
}

// ── B4b: fmt header ABI must match the engine build tree ────────────
// The bridge compiles header-only against fmt, but the fmt symbols live in
// libtransmission.a. A version mismatch compiles cleanly and corrupts the heap
// the first time bridge code constructs an engine class with fmt members
// (tr_torrent_metainfo) — an engine-thread SIGSEGV later (2026-11-08: fmt 9
// headers vs a fmt 12.1.0 library). Skipped when no local engine tree exists
// (fresh clone); the CMakeLists comment carries the requirement there.
function checkFmtAbi() {
  const vendored = join(ROOT, 'entry/src/main/cpp/third_party/fmt/include/fmt/base.h');
  if (!existsSync(vendored)) return;
  const version = (p) => Number((read(p).match(/#define FMT_VERSION (\d+)/) || [])[1] || 0);
  const vendoredVer = version(vendored);
  if (!vendoredVer) return;

  const trees = join(ROOT, '.build-third-party');
  if (!existsSync(trees)) return;
  for (const d of readdirSync(trees, { withFileTypes: true })) {
    if (!d.isDirectory()) continue;
    const engineFmt = join(trees, d.name, 'third-party/fmt/include/fmt/base.h');
    if (!existsSync(engineFmt)) continue;
    const engineVer = version(engineFmt);
    if (engineVer && engineVer !== vendoredVer)
      add('BLOCKING', 'fmt-abi', vendored, 0,
        `vendored fmt ${vendoredVer} != engine tree fmt ${engineVer} (${relative(ROOT, engineFmt)}) — heap corruption when the bridge constructs engine classes`);
  }
}

// ── B5: hardcoded UI text ───────────────────────────────────────────
function checkHardcodedText() {
  for (const file of ETS()) {
    read(file).split('\n').forEach((line, i) => {
      const code = line.replace(/\/\/.*$/, '').replace(/\/\*.*?\*\//g, '');
      if (/['"`][^'"`]*[一-鿿][^'"`]*['"`]/.test(code))
        add('BLOCKING', 'hardcoded-text', file, i + 1, 'hardcoded CJK literal in the UI layer — move to resources');
    });
  }
}

// ── B6: stateStyles on a node that owns no gesture ──────────────────
// ArkUI binds `pressed` to the node that receives the touch. Putting
// stateStyles on a decorative child (e.g. the icon Text) whose parent holds
// the onClick silently never fires — the style exists but nothing triggers it.
function checkStateStyles() {
  for (const file of ETS()) {
    const lines = read(file).split('\n');
    lines.forEach((line, i) => {
      if (!/\.stateStyles\s*\(/.test(line)) return;
      // The attribute chain is delimited by the previous statement end and the
      // next ';'. Collect it, then require an interaction handler inside.
      let start = i;
      while (start > 0 && !/[;}]$/.test(lines[start - 1].trim()) && !/^\s*$/.test(lines[start - 1])) start--;
      let end = i;
      while (end < lines.length - 1 && !lines[end].trim().endsWith(';')) end++;
      const chain = lines.slice(start, end + 1).join('\n');
      if (!/\.(onClick|onTouch|gesture|onKeyEvent|onMouse|onHover)\s*\(/.test(chain)) {
        add('BLOCKING', 'state-styles', file, i + 1,
          'stateStyles on a node with no interaction handler — `pressed` will never fire');
      }
    });
  }
}

// ── B7: C++ args[] read before an argc guard ───────────────────────
// `napi_get_cb_info` only writes the slots the JS caller supplied. A bare
// `napi_value args[N];` therefore holds uninitialized stack in the tail, and
// every getter dereferences the handle it is handed — reading args[1] on a
// one-argument call is undefined behaviour that presents as a crash.
// Zero-initialized arrays (`= {nullptr, ...}`) are exempt: null is a safe read.
function checkArgsGuarded() {
  for (const file of CPP()) {
    const lines = read(file).split('\n');
    lines.forEach((line, i) => {
      if (!/napi_value\s+args\[\d+\]\s*;/.test(line)) return;
      let end = i + 1;
      while (end < lines.length - 1) {
        const t = lines[end].trim();
        if (t === '}' || /^(static\s+)?napi_value\s+\w+\s*\(/.test(t)) break;
        end++;
      }
      const body = lines.slice(i + 1, end);
      const firstUse = body.findIndex((l) => /\bargs\[/.test(l));
      if (firstUse < 0) return;
      const guard = body.findIndex((l) => /requireArgs\s*\(|argc\s*[<>=]/.test(l));
      if (guard < 0 || guard > firstUse) {
        add('BLOCKING', 'args-uninit', file, i + 1,
          'args[] read before an argc guard — short call reads uninitialized stack');
      }
    });
  }
}

// ── B8: acquire without a release in the same file ──────────────────
// Every listed acquisition has exactly one counterpart. A file that starts a
// timer / installs the native callback but never stops it leaks on every page
// visit: the stale callback keeps firing against a destroyed component.
const PAIRS = [
  { acq: /\bsetInterval\s*\(/, rel: /\bclearInterval\s*\(/, level: 'BLOCKING', what: 'setInterval' },
  { acq: /\bnativeToArktsInit\s*\(/, rel: /\bnativeToArktsRelease\s*\(/, level: 'BLOCKING', what: 'nativeToArktsInit' },
  { acq: /\bsetTimeout\s*\(/, rel: /\bclearTimeout\s*\(/, level: 'ADVISORY', what: 'setTimeout (one-shot is fine — confirm none outlive the page)' },
];

function checkResourcePairing() {
  for (const file of ETS()) {
    const text = read(file);
    for (const p of PAIRS) {
      if (p.acq.test(text) && !p.rel.test(text))
        add(p.level, 'resource-pairing', file, 0, `${p.what} without its release`);
    }
  }
}

// ── A1: discarded napi_status on argument reads (advisory) ──────────
// Only the calls that READ the JS caller's data matter: an ignored failure
// there means a garbage or default value flows into the engine. napi_create_*
// failures are OOM and unrecoverable — flagging them is noise, so they're out.
const READ_CALL = /\bnapi_(get_value_[a-z0-9_]+|get_buffer_info|get_arraybuffer_info|get_array_length|get_cb_info|get_typedarray_info)\s*\(/;

function checkNapiStatus() {
  // D11: `napi_create_arraybuffer`'s output buffer is written to immediately,
  // so an unchecked create is a null-pointer write on OOM (unlike other
  // napi_create_* results, which are simply returned to the caller).
  const CREATE_BUF_CALL = /\bnapi_create_arraybuffer\s*\(/;
  for (const file of CPP()) {
    read(file).split('\n').forEach((line, i) => {
      if (/^\s*(\/\/|\*)/.test(line)) return;
      const m = line.match(READ_CALL) || line.match(CREATE_BUF_CALL);
      if (!m) return;
      const before = line.slice(0, m.index);
      if (/=\s*$|\bif\s*\(|\bwhile\s*\(|\breturn\b|\(\s*$/.test(before)) return;
      add('ADVISORY', 'napi-status', file, i + 1, `${m[1] || 'napi_create_arraybuffer'} result discarded — caller-supplied data may be silently defaulted`);
    });
  }
}

// ── run ─────────────────────────────────────────────────────────────

for (const c of [checkErrorMasking, checkNapiDrift, checkResourceCoverage,
  checkBuildConfig, checkFmtAbi, checkHardcodedText, checkStateStyles,
  checkArgsGuarded, checkResourcePairing, checkNapiStatus]) {
  try { c(); } catch (e) { add('BLOCKING', 'audit-crash', ROOT, 0, `${c.name}: ${e.message}`); }
}

const blocking = findings.filter((f) => f.level === 'BLOCKING');
const advisory = findings.filter((f) => f.level === 'ADVISORY');

if (blocking.length === 0) {
  console.log('BLOCKING (0) — OK');
} else {
  console.log(`\nBLOCKING (${blocking.length})`);
  for (const f of blocking) console.log(`  ${f.file}:${f.line}  [${f.check}] ${f.msg}`);
}

if (STRICT) {
  if (advisory.length) {
    console.log(`\nADVISORY (${advisory.length})`);
    for (const f of advisory) console.log(`  ${f.file}:${f.line}  [${f.check}] ${f.msg}`);
  }
} else {
  console.log(`\n(${advisory.length} advisory — rerun with --strict to list)`);
}

process.exit(blocking.length || (STRICT && advisory.length) ? 1 : 0);
