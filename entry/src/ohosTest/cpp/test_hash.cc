// transmissionbtm — unit tests for hash utilities (tr_binary_to_hex, tr_hex_to_binary)
// These functions operate on byte arrays — no N-API dependency needed.
#include "test_utils.h"
#include <cstring>

// Forward declarations — defined in commons.cc
extern "C" {
void tr_binary_to_hex(void const *input, char *output, size_t byte_length);
bool tr_hex_to_binary(char const *input, void *output, size_t byte_length);
}

// ── tr_binary_to_hex ──────────────────────────────────────────────

TEST(bin_to_hex_empty) {
  char out[1];
  tr_binary_to_hex(nullptr, out, 0);
  ASSERT_EQ(out[0], '\0', "empty input should produce empty output");
}

TEST(bin_to_hex_single_zero) {
  uint8_t in[] = {0x00};
  char out[3];
  tr_binary_to_hex(in, out, 1);
  ASSERT_STREQ(out, "00", "0x00 should be '00'");
}

TEST(bin_to_hex_max_byte) {
  uint8_t in[] = {0xFF};
  char out[3];
  tr_binary_to_hex(in, out, 1);
  ASSERT_STREQ(out, "ff", "0xFF should be 'ff'");
}

TEST(bin_to_hex_sha1_length) {
  uint8_t in[20];
  for (int i = 0; i < 20; i++) in[i] = (uint8_t)(i * 13);
  char out[41];
  tr_binary_to_hex(in, out, 20);
  ASSERT_EQ(strlen(out), (size_t)40, "20 bytes -> 40 hex chars");
}

TEST(bin_to_hex_known_vector) {
  uint8_t in[] = {0xAB, 0xCD, 0xEF};
  char out[7];
  tr_binary_to_hex(in, out, 3);
  ASSERT_STREQ(out, "abcdef", "0xABCDEF should be 'abcdef'");
}

// ── tr_hex_to_binary ──────────────────────────────────────────────

TEST(hex_to_bin_empty) {
  uint8_t out[1] = {0xFF};
  tr_hex_to_binary("", out, 0);
  ASSERT_EQ(out[0], (uint8_t)0xFF, "empty input should not modify buffer");
}

TEST(hex_to_bin_single_byte) {
  char in[] = "ff";
  uint8_t out[1];
  tr_hex_to_binary(in, out, 1);
  ASSERT_EQ(out[0], (uint8_t)0xFF, "'ff' should be 0xFF");
}

TEST(hex_to_bin_zero) {
  char in[] = "00";
  uint8_t out[1];
  tr_hex_to_binary(in, out, 1);
  ASSERT_EQ(out[0], (uint8_t)0x00, "'00' should be 0x00");
}

TEST(hex_to_bin_known_vector) {
  char in[] = "deadbeef";
  uint8_t out[4];
  tr_hex_to_binary(in, out, 4);
  ASSERT_EQ(out[0], (uint8_t)0xDE, "byte 0 of deadbeef");
  ASSERT_EQ(out[1], (uint8_t)0xAD, "byte 1 of deadbeef");
  ASSERT_EQ(out[2], (uint8_t)0xBE, "byte 2 of deadbeef");
  ASSERT_EQ(out[3], (uint8_t)0xEF, "byte 3 of deadbeef");
}

// ── Round-trip ─────────────────────────────────────────────────────

TEST(round_trip) {
  uint8_t original[20];
  for (int i = 0; i < 20; i++) original[i] = (uint8_t)((i + 1) * 17);
  char hex[41];
  tr_binary_to_hex(original, hex, 20);

  uint8_t decoded[20];
  tr_hex_to_binary(hex, decoded, 20);

  ASSERT_TRUE(memcmp(original, decoded, 20) == 0,
              "bin->hex->bin round-trip should be identity");
}
