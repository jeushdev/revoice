// Compile the exact patched Silero/VAD translation units against real ORT API
// declarations, with fake ORT, resampling and debug implementations below.
#include <algorithm>
#include <array>
#include <atomic>
#include <cassert>
#include <chrono>
#include <cmath>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <limits>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>
// Observe buffers without adding production test hooks. Standard headers above
// must be loaded before changing access on these two first-party classes.
#define private public
#include "voice-activity-detector.h"
#undef private
#include "ort-utils.h"
#include "resampler.h"

struct OrtEnv {};
struct OrtSessionOptions {};
struct OrtSession {};
struct OrtMemoryInfo {};
struct OrtStatus {};
struct OrtValue {
  void *data;
  std::vector<float> owned;
};

namespace {
std::atomic<int> operations{0}, fail_at{0}, values{0}, resources{0}, statuses{0};
std::atomic<int> session_loads{0};
bool partial = false;
int missing_output = -1, missing_data = -1, data_calls = 0;
OrtApi api{};
OrtAllocator allocator{};
int groups = 0;

OrtStatus *fault() {
  if (++operations == fail_at) {
    ++statuses;
    return new OrtStatus;
  }
  return nullptr;
}
template <class T> T *resource() { ++resources; return new T; }
template <class T> void release_resource(T *p) { assert(p); --resources; delete p; }
OrtValue *tensor(void *data) { ++values; return new OrtValue{data, {}}; }
OrtValue *owned_tensor(size_t n) {
  OrtValue *v = tensor(nullptr);
  v->owned.resize(n);
  v->data = v->owned.data();
  return v;
}
void mode(int fail = 0, bool return_partial = false) {
  operations = 0; fail_at = fail; partial = return_partial;
  missing_output = missing_data = -1; data_calls = 0;
}

OrtStatus *ORT_API_CALL create_options(OrtSessionOptions **out) noexcept {
  auto s = fault(); if (!s || partial) *out = resource<OrtSessionOptions>(); return s;
}
OrtStatus *ORT_API_CALL set_threads(OrtSessionOptions *, int) noexcept { return fault(); }
OrtStatus *ORT_API_CALL set_graph(OrtSessionOptions *, GraphOptimizationLevel) noexcept { return fault(); }
OrtStatus *ORT_API_CALL create_memory(OrtAllocatorType, OrtMemType, OrtMemoryInfo **out) noexcept {
  auto s = fault(); if (!s || partial) *out = resource<OrtMemoryInfo>(); return s;
}
OrtStatus *ORT_API_CALL get_allocator(OrtAllocator **out) noexcept {
  auto s = fault(); if (!s) *out = &allocator; return s;
}
OrtStatus *ORT_API_CALL create_tensor(const OrtMemoryInfo *, void *data, size_t,
                                     const int64_t *, size_t,
                                     ONNXTensorElementDataType, OrtValue **out) noexcept {
  auto s = fault(); if (!s || partial) *out = tensor(data); return s;
}
OrtStatus *ORT_API_CALL run_model(OrtSession *, const OrtRunOptions *, const char *const *,
                                const OrtValue *const *in, size_t n,
                                const char *const *, size_t m, OrtValue **out) noexcept {
  assert(n == 3 && m == 2);
  auto s = fault();
  if (!s || partial) {
    auto input = static_cast<float *>(in[0]->data);
    auto history = static_cast<float *>(in[1]->data);
    for (int i = 0; i < 2; ++i) {
      if (missing_output != i) out[i] = owned_tensor(i == 0 ? 1 : 256);
    }
    if (out[0]) {
      out[0]->owned[0] = (input[64] > 0.0f ? 0.9f : 0.1f)
                         + 0.001f * history[0] + 0.001f * input[0];
    }
    if (out[1]) {
      for (int i = 0; i < 256; ++i) out[1]->owned[i] = history[i] * 0.5f + input[64 + i];
    }
    // Adversarial fake: mutate the recurrent input even on a failed Run.
    if (s) history[0] = 999.0f;
  }
  return s;
}
OrtStatus *ORT_API_CALL get_data(OrtValue *v, void **out) noexcept {
  const int index = data_calls++;
  auto s = fault(); if (!s) *out = missing_data == index ? nullptr : v->data; return s;
}
void ORT_API_CALL release_value(OrtValue *v) { assert(v); --values; delete v; }
void ORT_API_CALL release_status(OrtStatus *s) { assert(s); --statuses; delete s; }
const OrtApi *ORT_API_CALL get_api(uint32_t version) noexcept {
  assert(version == ORT_API_VERSION); return &api;
}
const char *ORT_API_CALL version() noexcept { return "fake"; }
OrtApiBase base{get_api, version};

void setup() {
  api.CreateSessionOptions = create_options;
  api.SetIntraOpNumThreads = api.SetInterOpNumThreads = set_threads;
  api.SetSessionGraphOptimizationLevel = set_graph;
  api.CreateCpuMemoryInfo = create_memory;
  api.GetAllocatorWithDefaultOptions = get_allocator;
  api.CreateTensorWithDataAsOrtValue = create_tensor;
  api.Run = run_model;
  api.GetTensorMutableData = get_data;
  api.ReleaseValue = release_value;
  api.ReleaseStatus = release_status;
  api.ReleaseSession = release_resource<OrtSession>;
  api.ReleaseSessionOptions = release_resource<OrtSessionOptions>;
  api.ReleaseEnv = release_resource<OrtEnv>;
  api.ReleaseMemoryInfo = release_resource<OrtMemoryInfo>;
}
template <class C> bool zero(const C &c) {
  return std::all_of(c.begin(), c.end(), [](float x) { return x == 0.0f; });
}
bool same(const SileroVad::State &a, const SileroVad::State &b) {
  return a.recurrent == b.recurrent && a.context == b.context;
}
void feed(VoiceActivityDetector &v, float value, size_t count = 512) {
  std::vector<float> audio(count, value);
  v.process_audio(audio.data(), audio.size(), 16000);
}
void equal(const VoiceActivityDetector &a, const VoiceActivityDetector &b) {
  assert(same(a.silero_state, b.silero_state));
  assert(a.probability_window == b.probability_window);
  assert(a.look_behind_audio_buffer == b.look_behind_audio_buffer);
  assert(a.processing_remainder_audio_buffer == b.processing_remainder_audio_buffer);
  assert(a.samples_processed_count == b.samples_processed_count);
  assert(a.previous_is_voice == b.previous_is_voice);
  const auto &x = *a.get_segments(), &y = *b.get_segments();
  assert(x.size() == y.size());
  for (size_t i = 0; i < x.size(); ++i) {
    assert(x[i].audio_data == y[i].audio_data);
    assert(x[i].start_time == y[i].start_time && x[i].end_time == y[i].end_time);
    assert(x[i].is_complete == y[i].is_complete && x[i].just_updated == y[i].just_updated);
  }
}
void clean_values() { assert(values == 0 && statuses == 0); }

void constructor_faults() {
  for (bool p : {false, true}) {
    for (int i = 1; i <= 8; ++i) {
      mode(i, p);
      bool threw = false;
      try { SileroVad model; } catch (const std::runtime_error &) { threw = true; }
      assert(threw && resources == 0); clean_values();
    }
  }
  mode();
  { SileroVad model; assert(model.is_loaded()); }
  assert(resources == 0); ++groups;
}

void prediction_faults() {
  mode();
  SileroVad model;
  SileroVad::State state;
  state.recurrent.fill(3.0f); state.context.fill(2.0f);
  const auto before = state;
  std::vector<float> chunk(512, 1.0f);
  for (bool p : {false, true}) {
    for (int i = 1; i <= 6; ++i) {
      mode(i, p);
      float prob = -7.0f; int flag = -7;
      bool threw = false;
      try { model.predict(chunk, state, &prob, &flag); }
      catch (const std::runtime_error &) { threw = true; }
      assert(threw && same(state, before) && prob == -7.0f && flag == -7);
      clean_values();
    }
  }
  for (int i = 0; i < 2; ++i) {
    for (bool data : {false, true}) {
      mode();
      if (data) missing_data = i; else missing_output = i;
      bool threw = false;
      try { model.predict(chunk, state, nullptr, nullptr); }
      catch (const std::runtime_error &) { threw = true; }
      assert(threw && same(state, before)); clean_values();
    }
  }
  for (size_t n : {0, 511, 513}) {
    mode(); bool threw = false;
    try { model.predict(std::vector<float>(n), state, nullptr, nullptr); }
    catch (const std::invalid_argument &) { threw = true; }
    assert(threw && operations == 0 && same(state, before)); clean_values();
  }
  mode(); model.predict(chunk, state, nullptr, nullptr);
  assert(!same(state, before)); clean_values(); ++groups;
}

void singleton_construction() {
  // First use is concurrent; each thread operates only on its own detector.
  mode(); const int loads = session_loads;
  std::atomic<int> ready{0}; std::atomic<bool> go{false};
  std::vector<std::thread> threads;
  for (int i = 0; i < 24; ++i) threads.emplace_back([&] {
    ++ready; while (!go) std::this_thread::yield();
    VoiceActivityDetector v; v.start(); feed(v, 1.0f);
    assert(v.silero_state.recurrent[0] == 1.0f);
  });
  while (ready != 24) std::this_thread::yield();
  go = true;
  for (auto &t : threads) t.join();
  assert(session_loads == loads + 1); clean_values(); ++groups;
}

void lifecycle_tests() {
  mode();
  VoiceActivityDetector a(0.5f, 2), b(0.5f, 2);
  a.start(); b.start();
  for (int i = 0; i < 24; ++i) feed(a, i < 10 ? 1.0f : 0.0f);
  auto a_before = a.silero_state;
  // New session B cannot inherit A or reset A.
  b.start(); assert(same(a.silero_state, a_before));
  assert(zero(b.silero_state.recurrent) && zero(b.silero_state.context));
  feed(b, 0.0f); assert(b.get_segments()->empty());
  ++groups;

  for (int i = 0; i < 100; ++i) {
    feed(a, 1.0f, 1536); feed(a, 0.25f, 17);
    assert(!a.processing_remainder_audio_buffer.empty());
    a.stop(); a.start();
    VoiceActivityDetector fresh(0.5f, 2); fresh.start();
    assert(zero(a.silero_state.recurrent) && zero(a.silero_state.context));
    assert(zero(a.probability_window) && zero(a.look_behind_audio_buffer));
    assert(a.processing_remainder_audio_buffer.empty() && a.get_segments()->empty());
    for (float x : {0.0f, 0.0f, 1.0f, 1.0f, 0.0f, 0.0f}) { feed(a, x); feed(fresh, x); equal(a, fresh); }
  }
  ++groups;

  VoiceActivityDetector x(0.5f, 2), y(0.5f, 2), rx(0.5f, 2), ry(0.5f, 2);
  x.start(); y.start(); rx.start(); ry.start();
  const std::vector<float> xs{1, 1, 0, 0, 0, 1, 1, 0}, ys{0, 0, 1, 1, 1, 0, 0, 1};
  for (float v : xs) feed(rx, v);
  for (float v : ys) feed(ry, v);
  for (size_t i = 0; i < xs.size(); ++i) { feed(x, xs[i]); feed(y, ys[i]); }
  equal(x, rx); equal(y, ry); ++groups;

  auto keep = y.silero_state;
  x.stop(); x.start(); assert(same(y.silero_state, keep));
  feed(y, 1); feed(ry, 1); equal(y, ry); ++groups;

  // A capture-only pause is no VAD lifecycle call: simply delay the next feed.
  // A 17-sample accepted tail survives the gap and joins the next 495 samples.
  feed(y, 1, 17); feed(ry, 1, 17);
  auto history = y.silero_state;
  assert(!zero(history.recurrent));
  feed(y, 1, 495); feed(ry, 1, 495); equal(y, ry); ++groups;

  VoiceActivityDetector end(0.5f, 1); end.start(); feed(end, 1); feed(end, 0);
  assert(end.get_segments()->back().is_complete);
  assert(zero(end.look_behind_audio_buffer));
  // Utterance end must clear look-behind, not Silero history.
  assert(!zero(end.silero_state.recurrent)); ++groups;

  // Inference failure escapes the detector; it cannot fabricate a voice result.
  // Audio accounting/look-behind already advanced: caller must fail terminally,
  // not retry this append. Recurrent state and probability/segments stay intact.
  for (int i = 1; i <= 6; ++i) {
    mode(); VoiceActivityDetector failed(0.5f, 1); failed.start();
    mode(i, true); bool threw = false;
    try { feed(failed, 1); } catch (const std::runtime_error &) { threw = true; }
    assert(threw && failed.get_segments()->empty());
    assert(zero(failed.silero_state.recurrent) && zero(failed.silero_state.context));
    assert(zero(failed.probability_window)); clean_values();
  }
  mode(); ++groups;
}
}  // namespace

extern "C" const OrtApiBase *ORT_API_CALL OrtGetApiBase(void) noexcept { return &base; }
OrtStatus *ort_create_env(const OrtApi *, OrtLoggingLevel, const char *, OrtEnv **out) {
  auto s = fault(); if (!s || partial) *out = resource<OrtEnv>(); return s;
}
int ort_session_from_memory(const OrtApi *, OrtEnv *, OrtSessionOptions *,
                            const uint8_t *, size_t, OrtSession **out) {
  ++session_loads;
  auto s = fault(); if (!s || partial) *out = resource<OrtSession>();
  if (s) { release_status(s); return -1; } return 0;
}
const std::vector<float> resample_audio(const std::vector<float> &a, float in, float out) {
  assert(in == 16000 && out == 16000); return a;
}
std::string float_vector_stats_to_string(const std::vector<float> &) { return "fake"; }

int main(int argc, char **argv) {
  setup();
  if (argc == 2 && std::string(argv[1]) == "singleton-retry") {
    mode(8, true);
    bool threw = false;
    try { VoiceActivityDetector v; } catch (const std::runtime_error &) { threw = true; }
    assert(threw && resources == 0); clean_values();
    mode(); VoiceActivityDetector v; v.start(); feed(v, 1);
    assert(v.silero_state.recurrent[0] == 1 && session_loads == 2);
    std::cout << "singleton initialization retry passed\n";
    return 0;
  }
  constructor_faults(); prediction_faults(); assert(resources == 0);
  singleton_construction(); lifecycle_tests(); clean_values();
  // Exactly one intentionally retained shared model (env/options/memory/session).
  assert(resources == 4);
  std::cout << groups << " VAD state/fault/concurrency groups passed\n";
}
