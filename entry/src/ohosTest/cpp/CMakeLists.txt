# transmissionhm — C++ native test build
# Compiles unit tests against commons.cc utilities (hash, helpers).
# N-API-dependent tests (NapiTest fixture) require gtest — deferred to M7.
# Integrated via entry/build-profile.json5 nativeLib config for ohosTest.

cmake_minimum_required(VERSION 3.16)
project(transmissionhm_napi_test)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
add_compile_options(-Wall -Wextra)

find_library(NAPI_LIB ace_napi.z)
find_library(HILOG_LIB hilog_ndk.z)

set(MAIN_CPP_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp)

add_library(transmissionhm_napi_test SHARED
    test_main.cc
    test_hash.cc
    ${MAIN_CPP_DIR}/commons.cc
)
target_include_directories(transmissionhm_napi_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${MAIN_CPP_DIR}
    ${MAIN_CPP_DIR}/third_party/transmission/include
    ${MAIN_CPP_DIR}/third_party/fmt/include
)
target_link_libraries(transmissionhm_napi_test
    ${NAPI_LIB}
    ${HILOG_LIB}
)
