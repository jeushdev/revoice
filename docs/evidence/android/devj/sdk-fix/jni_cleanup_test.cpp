// Compile the EXACT patched streaming-add function extracted by review.py.
// Real JDK JNI table/types; fake core and table functions. No JVM/ART/inference.
#include <jni.h>
#include <memory>
#include <stdexcept>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include "moonshine-c-api.h"

static int acquire_count, release_count, length_count, core_count, log_count;
static int status, throw_kind, release_mode;
static bool pending, length_exception, acquire_null, acquire_exception;
static jsize length_value;
static float samples[8];
static std::vector<int> order;

static void check(bool ok, const char *why) {
  if (!ok) { std::fprintf(stderr, "FAIL %s\n", why); std::exit(1); }
}
static jboolean JNICALL exception_check(JNIEnv *) { return pending ? JNI_TRUE : JNI_FALSE; }
static jsize JNICALL get_length(JNIEnv *, jarray) {
  length_count++; order.push_back(1);
  if (length_exception) pending = true;
  return length_value;
}
static jfloat *JNICALL get_elements(JNIEnv *, jfloatArray, jboolean *) {
  acquire_count++; order.push_back(2);
  if (acquire_exception) pending = true;
  return acquire_null ? nullptr : samples;
}
static void JNICALL release_elements(JNIEnv *, jfloatArray array, jfloat *ptr, jint mode) {
  check(array != nullptr && ptr == samples, "wrong release args");
  release_count++; release_mode = mode; order.push_back(4);
}
extern "C" int32_t moonshine_transcribe_add_audio_to_stream(
    int32_t, int32_t, const float *ptr, uint64_t count, int32_t rate, uint32_t) {
  core_count++; order.push_back(3);
  check(ptr == samples && count == 8 && rate == 16000, "wrong core args");
  if (throw_kind == 1) throw std::runtime_error("fixture");
  if (throw_kind == 2) throw 17;
  return status;
}
#define ALOGE(...) ((void)++log_count)
#include "streaming-add.inc"

static void reset() {
  acquire_count = release_count = length_count = core_count = log_count = 0;
  status = throw_kind = 0; release_mode = -99; length_value = 8;
  pending = length_exception = acquire_null = acquire_exception = false;
  order.clear();
}
int main() {
  JNINativeInterface_ table{};
  table.ExceptionCheck = exception_check;
  table.GetArrayLength = get_length;
  table.GetFloatArrayElements = get_elements;
  table.ReleaseFloatArrayElements = release_elements;
  JNIEnv_ env{&table};
  auto array = reinterpret_cast<jfloatArray>(static_cast<uintptr_t>(1));
  auto call = [&](jfloatArray a = nullptr, int rate = 16000) {
    return Java_ai_moonshine_voice_JNI_moonshineAddAudioToStream(&env, nullptr, 1, 1, a, rate, 0);
  };
  for (int s : {0, -1, -2, -3, -4}) {
    reset(); status = s;
    check(call(array) == s, "status changed");
    check(release_count == 1 && release_mode == JNI_ABORT, "normal/error cleanup");
    check(order == std::vector<int>({1, 2, 3, 4}), "release before/after core order");
  }
  for (int kind : {1, 2}) {
    reset(); throw_kind = kind;
    check(call(array) == MOONSHINE_ERROR_UNKNOWN, "exception escaped/status");
    check(release_count == 1 && release_mode == JNI_ABORT && log_count == 1, "exception cleanup");
    check(order == std::vector<int>({1, 2, 3, 4}), "exception release order");
  }
  reset(); check(call() == MOONSHINE_ERROR_INVALID_ARGUMENT, "null input");
  check(length_count == 0 && acquire_count == 0, "null acquired");
  reset(); check(call(array, 0) == MOONSHINE_ERROR_INVALID_ARGUMENT, "invalid rate");
  check(acquire_count == 0, "invalid rate acquired");
  for (jsize n : {0, -1}) {
    reset(); length_value = n;
    check(call(array) == MOONSHINE_ERROR_INVALID_ARGUMENT && acquire_count == 0, "invalid length");
  }
  reset(); pending = true;
  check(call(array) == MOONSHINE_ERROR_UNKNOWN && pending && length_count == 0, "preexisting exception");
  reset(); length_exception = true;
  check(call(array) == MOONSHINE_ERROR_UNKNOWN && pending && acquire_count == 0, "length exception");
  for (bool oom : {false, true}) {
    reset(); acquire_null = true; acquire_exception = oom;
    check(call(array) == MOONSHINE_ERROR_UNKNOWN && core_count == 0 && release_count == 0, "null acquisition");
    check(pending == oom, "pending OOM cleared");
  }
  reset(); acquire_exception = true;
  check(call(array) == MOONSHINE_ERROR_UNKNOWN && core_count == 0, "exception after acquisition");
  check(pending && release_count == 1 && release_mode == JNI_ABORT, "pending exception cleanup");
  std::puts("PASS 16 JNI scenarios: success/status/exception cleanup, null/OOM/rate/length/pending exceptions");
}
