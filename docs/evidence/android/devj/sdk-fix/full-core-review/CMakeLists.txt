cmake_minimum_required(VERSION 3.22.1)
project(revoice_full_core_review LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
if(MSVC)
  # VS2019 otherwise gives constexpr internal linkage despite a preceding
  # extern declaration in upstream's generated Spanish Unicode tables.
  # Enable standard-conforming linkage; do not alter generated source/data.
  add_compile_options("$<$<COMPILE_LANGUAGE:CXX>:/Zc:externConstexpr>")
endif()
add_subdirectory("${PINNED_SOURCE}/core" "${CMAKE_BINARY_DIR}/core")
if(NOT ANDROID)
  add_executable(real-vad-review "${REVIEW_FIXTURE}")
  target_include_directories(real-vad-review PRIVATE
    "${PINNED_SOURCE}/core"
    "${PINNED_SOURCE}/core/ort-utils"
    "${PINNED_SOURCE}/core/third-party/onnxruntime/include")
  target_link_libraries(real-vad-review PRIVATE moonshine moonshine-utils)
  if(MSVC)
    target_compile_options(real-vad-review PRIVATE /W4 /WX /utf-8)
  else()
    target_compile_options(real-vad-review PRIVATE -Wall -Wextra -Werror)
  endif()
  copy_onnxruntime_dll(real-vad-review)
endif()
