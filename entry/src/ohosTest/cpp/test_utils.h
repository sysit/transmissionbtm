// transmissionhm — minimal C++ test helpers (no gtest dependency)
// Used for native unit tests that run on-device via ohosTest.
//
// When gtest is available: replace assert_* macros with EXPECT_*/ASSERT_*.
// For now, assert() with descriptive messages keeps tests lightweight.

#pragma once

#include <cstdio>
#include <cstdlib>
#include <cstring>

// ── Test result tracking ──────────────────────────────────────────
static int g_tests_run = 0;
static int g_tests_passed = 0;
static int g_tests_failed = 0;

#define TEST(name)                              \
  static void test_##name();                    \
  struct test_reg_##name {                      \
    test_reg_##name() {                         \
      run_test(#name, test_##name);            \
    }                                           \
  } static test_reg_##name##_inst;             \
  static void test_##name()

static void run_test(const char *name, void (*fn)()) {
  g_tests_run++;
  printf("  TEST %s ... ", name);
  fflush(stdout);
  fn();
  printf("PASSED\n");
  g_tests_passed++;
}

// ── Assertion macros ──────────────────────────────────────────────
#define ASSERT_TRUE(cond, msg)                        \
  do {                                                \
    if (!(cond)) {                                    \
      printf("FAILED\n    %s:%d: %s\n",              \
             __FILE__, __LINE__, msg);                \
      g_tests_failed++;                               \
      return;                                         \
    }                                                 \
  } while(0)

#define ASSERT_EQ(a, b, msg)                          \
  ASSERT_TRUE((a) == (b), msg)

#define ASSERT_NE(a, b, msg)                          \
  ASSERT_TRUE((a) != (b), msg)

#define ASSERT_STREQ(a, b, msg)                       \
  ASSERT_TRUE(strcmp((a), (b)) == 0, msg)

#define ASSERT_NULL(p, msg)                           \
  ASSERT_TRUE((p) == nullptr, msg)

#define ASSERT_NOT_NULL(p, msg)                       \
  ASSERT_TRUE((p) != nullptr, msg)

// ── Result reporting ──────────────────────────────────────────────
static inline int print_test_results() {
  printf("\nResults: %d/%d passed", g_tests_passed, g_tests_run);
  if (g_tests_failed > 0) {
    printf(", %d FAILED\n", g_tests_failed);
  } else {
    printf("\n");
  }
  return g_tests_failed > 0 ? 1 : 0;
}
