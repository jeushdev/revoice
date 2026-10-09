// Review-only fixture linked against the complete rebuilt core and real ORT.
// No fake helpers, private-state overrides, embedded-model substitute, or mic.
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <future>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

#include "debug-utils.h"
#include "moonshine-c-api.h"
#include "resampler.h"
#include "voice-activity-detector.h"

namespace {
void require(bool condition, const char *message) {
  if (!condition) throw std::runtime_error(message);
}
void close(float a, float b) { require(std::fabs(a - b) <= 1e-6f, "Float mismatch"); }

std::vector<float> audio(const char *path) {
  float *data = nullptr;
  size_t count = 0;
  int32_t rate = 0;
  require(load_wav_data(path, &data, &count, &rate), "WAV load failed");
  std::vector<float> samples(data, data + count);
  std::free(data);
  samples = resample_audio(samples, static_cast<float>(rate), 16000.0f);
  require(samples.size() >= 16000, "WAV too short");
  samples.resize(std::min(samples.size(), size_t{160000}));
  samples.resize((samples.size() / 512) * 512);
  samples.insert(samples.end(), 64 * 512, 0.0f);  // Exact hops, not a Stop-tail fix.
  return samples;
}

using Segments = std::vector<VoiceActivitySegment>;
void same(const Segments &a, const Segments &b) {
  require(a.size() == b.size(), "Segment count mismatch");
  for (size_t i = 0; i < a.size(); ++i) {
    close(a[i].start_time, b[i].start_time);
    close(a[i].end_time, b[i].end_time);
    require(a[i].is_complete == b[i].is_complete && a[i].just_updated == b[i].just_updated,
            "Segment flags mismatch");
    require(a[i].audio_data == b[i].audio_data, "Segment audio mismatch");
  }
}
std::vector<Segments> reference(const std::vector<float> &samples) {
  VoiceActivityDetector v;
  v.start();
  std::vector<Segments> result;
  for (size_t i = 0; i < samples.size(); i += 512) {
    v.process_audio(samples.data() + i, 512, 16000);
    result.push_back(*v.get_segments());
  }
  require(!result.back().empty(), "No real speech detected");
  return result;
}
void check_run(VoiceActivityDetector &v, const std::vector<float> &samples,
               const std::vector<Segments> &expected) {
  v.start();
  for (size_t i = 0; i < samples.size(); i += 512) {
    v.process_audio(samples.data() + i, 512, 16000);
    same(*v.get_segments(), expected[i / 512]);
  }
  v.stop();
}

struct Prediction { float probability; int flag; SileroVad::State state; };
std::vector<Prediction> predictions(SileroVad &model, const std::vector<float> &samples) {
  SileroVad::State state;
  std::vector<Prediction> result;
  for (size_t i = 0; i < samples.size(); i += 512) {
    std::vector<float> chunk(samples.begin() + i, samples.begin() + i + 512);
    float probability = -1;
    int flag = -1;
    model.predict(chunk, state, &probability, &flag);
    require(std::isfinite(probability) && probability >= 0 && probability <= 1,
            "Invalid real-model probability");
    result.push_back({probability, flag, state});
  }
  require(std::any_of(result.begin(), result.end(), [](const Prediction &p) { return p.probability > 0.5f; }),
          "Real model did not recognize speech");
  return result;
}
void same(const Prediction &a, const Prediction &b) {
  close(a.probability, b.probability);
  require(a.flag == b.flag && a.state.context == b.state.context, "Prediction context mismatch");
  for (size_t j = 0; j < a.state.recurrent.size(); ++j) close(a.state.recurrent[j], b.state.recurrent[j]);
}

void vad_checks(const std::vector<float> &a, const std::vector<float> &b) {
  // First use really is concurrent, before any detector has initialized the singleton.
  std::vector<std::future<Segments>> futures;
  for (int i = 0; i < 8; ++i) futures.push_back(std::async(std::launch::async, [&a] {
    VoiceActivityDetector v;
    v.start();
    v.process_audio(a.data(), 160 * 512, 16000);
    return *v.get_segments();
  }));
  const Segments first = futures.front().get();
  for (size_t i = 1; i < futures.size(); ++i) same(first, futures[i].get());
  std::cout << "PASS concurrent first use: 8 real detectors\n";

  SileroVad model;
  require(model.is_loaded(), "Real model not loaded");
  const auto pa = predictions(model, a), pb = predictions(model, b);
  SileroVad::State sa, sb;
  for (size_t i = 0; i < std::max(pa.size(), pb.size()); ++i) {
    for (int which = 0; which < 2; ++which) {
      const auto &samples = which == 0 ? a : b;
      const auto &expected = which == 0 ? pa : pb;
      auto &state = which == 0 ? sa : sb;
      if (i >= expected.size()) continue;
      std::vector<float> chunk(samples.begin() + i * 512, samples.begin() + (i + 1) * 512);
      float probability;
      int flag;
      model.predict(chunk, state, &probability, &flag);
      same({probability, flag, state}, expected[i]);
    }
  }
  sa.reset();
  float probability;
  int flag;
  model.predict(std::vector<float>(a.begin(), a.begin() + 512), sa, &probability, &flag);
  same({probability, flag, sa}, pa.front());
  const auto before = sa;
  bool failed = false;
  try { model.predict(std::vector<float>(256), sa, &probability, &flag); }
  catch (const std::invalid_argument &) { failed = true; }
  require(failed && sa.context == before.context && sa.recurrent == before.recurrent,
          "Invalid chunk failed to preserve history");
  std::cout << "PASS real probabilities/recurrent/context: isolated vs interleaved; reset; invalid chunk\n";

  const auto ra = reference(a), rb = reference(b);
  VoiceActivityDetector reused;
  for (int i = 0; i < 20; ++i) check_run(reused, a, ra);
  VoiceActivityDetector fresh_b;
  check_run(fresh_b, b, rb);
  std::cout << "PASS 20 reused stop/start sessions and fresh B after A\n";

  VoiceActivityDetector va, vb;
  va.start(); vb.start();
  for (size_t i = 0; i < std::max(ra.size(), rb.size()); ++i) {
    if (i < ra.size()) {
      va.process_audio(a.data() + i * 512, 512, 16000);
      same(*va.get_segments(), ra[i]);
    }
    if (i == 100) check_run(va, a, ra);  // Restart/replay A while B continues.
    // After the restart above, A is deliberately not fed its old session again.
    if (i < rb.size()) {
      vb.process_audio(b.data() + i * 512, 512, 16000);
      same(*vb.get_segments(), rb[i]);
    }
    if (i == 100) break;
  }
  for (size_t i = 101; i < rb.size(); ++i) {
    vb.process_audio(b.data() + i * 512, 512, 16000);
    same(*vb.get_segments(), rb[i]);
  }
  // A separate complete interleaved run, without a restart.
  va.start(); vb.start();
  for (size_t i = 0; i < std::max(ra.size(), rb.size()); ++i) {
    if (i < ra.size()) { va.process_audio(a.data() + i * 512, 512, 16000); same(*va.get_segments(), ra[i]); }
    if (i < rb.size()) { vb.process_audio(b.data() + i * 512, 512, 16000); same(*vb.get_segments(), rb[i]); }
  }
  std::cout << "PASS per-hop VAD segment/audio isolation and restarting A while B continues\n";

  VoiceActivityDetector gap, contiguous;
  gap.start(); contiguous.start();
  gap.process_audio(a.data(), 777, 16000);
  check_run(va, b, rb);  // Gap in A feeding while another session runs; no start/stop A.
  gap.process_audio(a.data() + 777, a.size() - 777, 16000);
  contiguous.process_audio(a.data(), a.size(), 16000);
  same(*gap.get_segments(), *contiguous.get_segments());
  std::cout << "PASS capture-only gap with 265 pending samples; no Pause reset\n";
}

struct Line { std::string text; float start; float duration; bool complete; };
using Lines = std::vector<Line>;
Lines update(int32_t h, int32_t s) {
  transcript_t *t = nullptr;
  require(moonshine_transcribe_stream(h, s, MOONSHINE_FLAG_FORCE_UPDATE, &t) == 0 && t,
          "C API inference/update failed");
  Lines result;
  for (uint64_t i = 0; i < t->line_count; ++i) {
    const auto &l = t->lines[i];
    result.push_back({l.text ? l.text : "", l.start_time, l.duration, l.is_complete != 0});
  }
  return result;
}
void same(const Lines &a, const Lines &b) {
  require(a.size() == b.size(), "C API line count mismatch");
  for (size_t i = 0; i < a.size(); ++i) {
    require(a[i].text == b[i].text && a[i].complete == b[i].complete, "C API text/completion mismatch");
    close(a[i].start, b[i].start); close(a[i].duration, b[i].duration);
  }
}
void feed(int32_t h, int32_t s, const std::vector<float> &samples, size_t pos, size_t count) {
  require(moonshine_transcribe_add_audio_to_stream(h, s, samples.data() + pos, count, 16000, 0) == 0,
          "C API append failed");
}
std::vector<Lines> session(int32_t h, int32_t s, const std::vector<float> &samples) {
  require(moonshine_start_stream(h, s) == 0, "C API start failed");
  std::vector<Lines> result;
  for (size_t pos = 0; pos < samples.size(); pos += 32 * 512) {
    feed(h, s, samples, pos, std::min(size_t{32 * 512}, samples.size() - pos));
    result.push_back(update(h, s));
  }
  require(moonshine_stop_stream(h, s) == 0, "C API stop failed");
  result.push_back(update(h, s));
  require(!result.back().empty() && std::any_of(result.back().begin(), result.back().end(),
          [](const Line &l) { return !l.text.empty(); }), "C API produced no real text");
  return result;
}
void capi_checks(const char *models, const std::vector<float> &a, const std::vector<float> &b) {
  const moonshine_option_t options[] = {{"log_ort_run", "false"}, {"identify_speakers", "false"}};
  const int32_t h = moonshine_load_transcriber_from_files(models, MOONSHINE_MODEL_ARCH_TINY_STREAMING,
                                                         options, 2, MOONSHINE_HEADER_VERSION);
  require(h >= 0, "Real pinned speech model load failed");
  const int32_t s = moonshine_create_stream(h, 0), other = moonshine_create_stream(h, 0);
  require(s >= 0 && other >= 0, "C API stream creation failed");
  const auto ra = session(h, s, a), rb = session(h, other, b);
  for (int cycle = 0; cycle < 3; ++cycle) {
    const auto actual = session(h, s, a);
    require(actual.size() == ra.size(), "C API update count mismatch");
    for (size_t i = 0; i < ra.size(); ++i) same(actual[i], ra[i]);
  }
  require(moonshine_start_stream(h, s) == 0 && moonshine_start_stream(h, other) == 0, "C API interleaved start failed");
  for (size_t i = 0; i + 1 < std::max(ra.size(), rb.size()); ++i) {
    for (int which = 0; which < 2; ++which) {
      const auto &samples = which == 0 ? a : b;
      const auto &expected = which == 0 ? ra : rb;
      const int32_t stream = which == 0 ? s : other;
      const size_t pos = i * 32 * 512;
      if (pos >= samples.size()) continue;
      feed(h, stream, samples, pos, std::min(size_t{32 * 512}, samples.size() - pos));
      same(update(h, stream), expected[i]);
    }
  }
  require(moonshine_stop_stream(h, s) == 0 && moonshine_stop_stream(h, other) == 0, "C API interleaved stop failed");
  same(update(h, s), ra.back()); same(update(h, other), rb.back());
  std::cout << "PASS real C API tiny-streaming speech: three repeated sessions; interleaved per-update text/timing/completion\n";
  require(moonshine_free_stream(h, s) == 0 && moonshine_free_stream(h, other) == 0, "C API free failed");
  moonshine_free_transcriber(h);

  // Real core exception, not fault-injected ORT: unsupported 256-sample hop.
  const moonshine_option_t bad[] = {{"vad_hop_size", "256"}, {"log_ort_run", "false"}};
  const int32_t broken = moonshine_load_transcriber_from_files(models, MOONSHINE_MODEL_ARCH_TINY_STREAMING,
                                                              bad, 2, MOONSHINE_HEADER_VERSION);
  require(broken >= 0, "Negative-test transcriber load failed");
  const int32_t bs = moonshine_create_stream(broken, 0);
  require(bs >= 0 && moonshine_start_stream(broken, bs) == 0, "Negative-test start failed");
  feed(broken, bs, a, 0, 512);
  transcript_t *t = nullptr;
  require(moonshine_transcribe_stream(broken, bs, MOONSHINE_FLAG_FORCE_UPDATE, &t) == MOONSHINE_ERROR_UNKNOWN && !t,
          "Core exception did not become C API failure");
  // Terminal operation: never replay the accepted audio or report a successful final.
  require(moonshine_free_stream(broken, bs) == 0, "Failed stream cleanup failed");
  moonshine_free_transcriber(broken);
  std::cout << "PASS real VAD exception -> C API UNKNOWN with no transcript; terminal free, no replay\n";
}
}  // namespace

int main(int argc, char **argv) {
  try {
    require(argc == 3 || argc == 4, "Expected two pinned WAVs and optional existing speech model directory");
    const auto a = audio(argv[1]), b = audio(argv[2]);
    std::cout << "Real ORT " << OrtGetApiBase()->GetVersionString() << "; audio samples " << a.size() << ", " << b.size() << std::endl;
    vad_checks(a, b);
    if (argc == 4) capi_checks(argv[3], a, b);
    else std::cout << "NOT RUN C API speech: existing pinned STT assets not supplied\n";
    std::cout << "PASS review-only real inference; not Android runtime/microphone/adoption evidence\n";
    return 0;
  } catch (const std::exception &e) {
    std::cerr << "FAIL real inference review: " << e.what() << std::endl;
    return 1;
  }
}
