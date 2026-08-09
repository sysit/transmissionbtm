// transmissionhm — C++ native test entry point
// Runs all registered tests and reports results.
//
// Integration: compiled into a .so loaded by ohosTest test runner.
// When gtest is available, replace with:
//   #include <gtest/gtest.h>
//   int main(int argc, char **argv) {
//     ::testing::InitGoogleTest(&argc, argv);
//     return RUN_ALL_TESTS();
//   }
#include "test_utils.h"
#include <cstdio>

// Called by ohosTest ArkTS runner via N-API to execute all tests.
extern "C" int run_native_tests() {
  printf("\n=== transmissionhm C++ Native Tests ===\n\n");

  // Test registration happens via static initializers (TEST macro).
  // Each test_*.cc file's registrars run before this function.

  int result = print_test_results();
  printf("\n=== Done ===\n");
  return result;
}
