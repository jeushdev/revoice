// Exact patched loader/converter/stream entry point, real JNI types, fake table/core.
// Fault injection is host control-flow proof, not CheckJNI, ART or inference.
#include <jni.h>
#include <algorithm>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <limits>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>
#include "moonshine-c-api.h"
#include "utf8.h"

static void check(bool ok, const char *why) {
  if (!ok) { std::fprintf(stderr, "FAIL %s\n", why); std::exit(1); }
}
struct Object {
  std::string type, text;
  std::map<std::string, jobject> fields;
  std::map<std::string, double> scalars;
  std::vector<jobject> members;
  std::vector<float> audio;
};
static std::vector<std::unique_ptr<Object>> objects;
static std::vector<std::unique_ptr<std::string>> ids;
static std::vector<std::vector<jobject>> frames;
static std::map<const char *, jstring> acquired;
static int operations, fault_at, fault_mode, core_calls, utf_gets, releases, peak_refs;
static int core_status, core_throw, logs;
static bool pending, null_native_transcript;
static std::vector<std::string> trace;
static jobject options;
static jstring path;
static transcript_t transcript;
static transcript_line_t line;
static speaker_span_t span;
static transcript_word_t word;
static float samples[] = {0.25f, -0.5f};

static Object *obj(jobject ref) { check(ref != nullptr, "null dereference"); return reinterpret_cast<Object *>(ref); }
static int refs() { int n = 0; for (const auto &frame : frames) n += static_cast<int>(frame.size()); return n; }
static jobject local(jobject ref) {
  if (ref != nullptr) {
    frames.back().push_back(ref);
    peak_refs = std::max(peak_refs, refs());
  }
  return ref;
}
static jobject make(const std::string &type, bool is_local = true) {
  auto value = std::make_unique<Object>(); value->type = type;
  auto ref = reinterpret_cast<jobject>(value.get()); objects.push_back(std::move(value));
  return is_local ? local(ref) : ref;
}
static jstring string(const std::string &text, bool is_local = true) {
  jobject ref = make("string", is_local); obj(ref)->text = text;
  return reinterpret_cast<jstring>(ref);
}
static bool step(const char *operation) {
  check(!pending, "ordinary JNI call with pending exception");
  trace.emplace_back(operation); ++operations;
  if (operations != fault_at) return true;
  if (fault_mode != 0) pending = true;
  return fault_mode == 2; // Also return a non-null value with pending exception.
}
static const std::string &id_name(jfieldID id) { return *reinterpret_cast<std::string *>(id); }
static jboolean JNICALL exception_check(JNIEnv *) { return pending ? JNI_TRUE : JNI_FALSE; }
static jint JNICALL push_frame(JNIEnv *, jint capacity) {
  check(capacity >= 8, "frame capacity");
  if (!step("PushLocalFrame")) return -1;
  frames.emplace_back(); return 0;
}
static jobject JNICALL pop_frame(JNIEnv *, jobject result) {
  check(frames.size() > 1, "unbalanced PopLocalFrame");
  frames.pop_back(); return local(result); // Legal during pending exception.
}
static void JNICALL delete_ref(JNIEnv *, jobject ref) {
  for (auto i = frames.rbegin(); i != frames.rend(); ++i) {
    auto found = std::find(i->begin(), i->end(), ref);
    if (found != i->end()) { i->erase(found); return; }
  }
  check(false, "deleted unknown local reference");
}
static jclass JNICALL find_class(JNIEnv *, const char *name) {
  if (!step("FindClass")) return nullptr;
  return reinterpret_cast<jclass>(make(name));
}
static jfieldID JNICALL field_id(JNIEnv *, jclass type, const char *name, const char *) {
  check(type != nullptr, "field class null");
  if (!step("GetFieldID")) return nullptr;
  ids.push_back(std::make_unique<std::string>(name));
  return reinterpret_cast<jfieldID>(ids.back().get());
}
static jmethodID JNICALL method_id(JNIEnv *, jclass type, const char *name, const char *) {
  check(type != nullptr, "method class null");
  if (!step("GetMethodID")) return nullptr;
  ids.push_back(std::make_unique<std::string>(name));
  return reinterpret_cast<jmethodID>(ids.back().get());
}
static jobject JNICALL new_object(JNIEnv *, jclass type, jmethodID method, va_list) {
  check(method != nullptr, "constructor null");
  if (!step("NewObject")) return nullptr;
  return make(obj(type)->type);
}
static jstring JNICALL new_string(JNIEnv *, const char *value) {
  check(value != nullptr, "NewStringUTF null");
  if (!step("NewStringUTF")) return nullptr;
  return string(value);
}
static jfloatArray JNICALL new_floats(JNIEnv *, jsize count) {
  check(count >= 0, "negative audio length");
  if (!step("NewFloatArray")) return nullptr;
  jobject ref = make("floats"); obj(ref)->audio.resize(count);
  return reinterpret_cast<jfloatArray>(ref);
}
static void JNICALL set_audio(JNIEnv *, jfloatArray ref, jsize start, jsize count, const jfloat *data) {
  check(ref != nullptr && data != nullptr && start == 0 && count > 0, "bad audio region");
  if (step("SetFloatArrayRegion")) std::copy(data, data + count, obj(ref)->audio.begin());
}
static void JNICALL set_object(JNIEnv *, jobject ref, jfieldID field, jobject value) {
  check(ref != nullptr && field != nullptr && value != nullptr, "bad object setter");
  if (step("SetObjectField")) obj(ref)->fields[id_name(field)] = value;
}
static void scalar(jobject ref, jfieldID field, double value, const char *operation) {
  check(ref != nullptr && field != nullptr, "bad scalar setter");
  if (step(operation)) obj(ref)->scalars[id_name(field)] = value;
}
static void JNICALL set_float(JNIEnv *, jobject ref, jfieldID field, jfloat v) { scalar(ref, field, v, "SetFloatField"); }
static void JNICALL set_long(JNIEnv *, jobject ref, jfieldID field, jlong v) { scalar(ref, field, static_cast<double>(v), "SetLongField"); }
static void JNICALL set_int(JNIEnv *, jobject ref, jfieldID field, jint v) { scalar(ref, field, v, "SetIntField"); }
static void JNICALL set_bool(JNIEnv *, jobject ref, jfieldID field, jboolean v) { scalar(ref, field, v, "SetBooleanField"); }
static jboolean JNICALL add(JNIEnv *, jobject ref, jmethodID method, va_list args) {
  check(method != nullptr && ref != nullptr, "bad list add");
  jobject member = va_arg(args, jobject); check(member != nullptr, "null list member");
  if (!step("CallBooleanMethod")) return JNI_FALSE;
  obj(ref)->members.push_back(member); return JNI_TRUE;
}
static jsize JNICALL length(JNIEnv *, jarray ref) {
  check(ref != nullptr, "length null");
  if (!step("GetArrayLength")) return 0;
  return static_cast<jsize>(obj(ref)->members.size());
}
static jobject JNICALL element(JNIEnv *, jobjectArray ref, jsize index) {
  if (!step("GetObjectArrayElement")) return nullptr;
  return local(obj(ref)->members.at(index));
}
static jobject JNICALL get_object(JNIEnv *, jobject ref, jfieldID field) {
  if (!step("GetObjectField")) return nullptr;
  return local(obj(ref)->fields[id_name(field)]);
}
static const char *JNICALL get_utf(JNIEnv *, jstring ref, jboolean *) {
  check(ref != nullptr, "UTF null"); ++utf_gets;
  if (!step("GetStringUTFChars")) return nullptr;
  const char *ptr = obj(ref)->text.c_str();
  check(acquired.emplace(ptr, ref).second, "duplicate acquisition"); return ptr;
}
static void JNICALL release_utf(JNIEnv *, jstring ref, const char *ptr) {
  check(ref != nullptr && ptr != nullptr, "release null UTF");
  auto found = acquired.find(ptr);
  check(found != acquired.end() && found->second == ref, "unowned/double UTF release");
  acquired.erase(found); ++releases;
}
static void core_failure() {
  check(!pending, "core called with pending exception"); ++core_calls;
  if (core_throw == 1) throw std::runtime_error("fixture");
  if (core_throw == 2) throw 17;
}
extern "C" int32_t moonshine_load_transcriber_from_files(
    const char *p, uint32_t arch, const moonshine_option_t *opts, uint64_t count, int32_t version) {
  core_failure();
  check((p == nullptr) == (path == nullptr), "path null changed");
  if (p != nullptr) check(std::string(p) == "fixture/models", "path content");
  check(arch == 2 && version == MOONSHINE_HEADER_VERSION, "loader arguments");
  check(count == (options == nullptr ? 0 : obj(options)->members.size()), "option count");
  for (uint64_t i = 0; i < count; ++i) {
    check(std::string(opts[i].name) == "option" + std::to_string(i), "option name dangling/order");
    check(std::string(opts[i].value) == "value" + std::to_string(i), "option value dangling/order");
  }
  // All option UTF pointers have already been released; owned copies stay valid.
  check(acquired.size() == (path == nullptr ? 0 : 1), "option UTF retained during core call");
  return core_status;
}
extern "C" int32_t moonshine_transcribe_stream(int32_t, int32_t, uint32_t, transcript_t **out) {
  core_failure(); *out = null_native_transcript ? nullptr : &transcript; return core_status;
}
#define ALOGE(...) ((void)++logs)
#define ALOGD(...) ((void)0)
#include "required-converter.inc"
#include "required-loader.inc"
#include "required-stream.inc"

static void reset(int option_count = 2) {
  objects.clear(); ids.clear(); frames.clear(); frames.emplace_back(); acquired.clear(); trace.clear();
  operations = fault_at = fault_mode = core_calls = utf_gets = releases = peak_refs = logs = 0;
  core_status = 7; core_throw = 0; pending = null_native_transcript = false;
  options = make("options", false);
  for (int i = 0; i < option_count; ++i) {
    jobject option = make("option", false);
    obj(option)->fields["name"] = string("option" + std::to_string(i), false);
    obj(option)->fields["value"] = string("value" + std::to_string(i), false);
    obj(options)->members.push_back(option);
  }
  path = string("fixture/models", false);
  span = {}; span.start_time = 0.1f; span.duration = 0.2f; span.speaker_id = -42; span.speaker_index = 2;
  word = {}; word.text = "fixture"; word.start = 0.1f; word.end = 0.3f; word.confidence = 0.8f;
  line = {}; line.text = "fixture"; line.audio_data = samples; line.audio_data_count = 2;
  line.id = 23; line.is_complete = true; line.start_time = 0.1f; line.duration = 0.2f;
  line.speaker_spans = &span; line.speaker_span_count = 1; line.words = &word; line.word_count = 1;
  transcript = {}; transcript.lines = &line; transcript.line_count = 1;
}
static void cleaned() {
  check(frames.size() == 1, "local frame leak");
  check(acquired.empty(), "UTF leak");
  check(refs() <= 1, "local reference leak");
}
static jint load(JNIEnv *env) {
  return Java_ai_moonshine_voice_JNI_moonshineLoadTranscriberFromFiles(
      env, nullptr, path, 2, reinterpret_cast<jobjectArray>(options));
}
static jobject transcribe(JNIEnv *env) {
  return Java_ai_moonshine_voice_JNI_moonshineTranscribeStream(env, nullptr, 1, 1, 0);
}
static void verify_transcript(jobject result) {
  check(result != nullptr, "transcript missing");
  auto list = obj(obj(result)->fields.at("lines")); check(list->members.size() == 1, "line count changed");
  auto jl = obj(list->members.front());
  check(obj(jl->fields.at("text"))->text == "fixture", "text changed");
  check(obj(jl->fields.at("audioData"))->audio == std::vector<float>({0.25f, -0.5f}), "audio changed");
  check(jl->scalars.at("id") == 23 && jl->scalars.at("isComplete") == 1, "line metadata changed");
  auto spans = obj(jl->fields.at("speakerSpans"));
  check(spans->members.size() == 1 && obj(spans->members[0])->scalars.at("speakerId") == -42, "speaker changed");
  auto words = obj(jl->fields.at("words"));
  check(words->members.size() == 1 && obj(obj(words->members[0])->fields.at("word"))->text == "fixture", "word changed");
}
int main() {
  JNINativeInterface_ t{};
  t.ExceptionCheck = exception_check; t.PushLocalFrame = push_frame; t.PopLocalFrame = pop_frame;
  t.DeleteLocalRef = delete_ref; t.FindClass = find_class; t.GetFieldID = field_id; t.GetMethodID = method_id;
  t.NewObjectV = new_object; t.NewStringUTF = new_string; t.NewFloatArray = new_floats;
  t.SetFloatArrayRegion = set_audio; t.SetObjectField = set_object; t.SetFloatField = set_float;
  t.SetLongField = set_long; t.SetIntField = set_int; t.SetBooleanField = set_bool;
  t.CallBooleanMethodV = add; t.GetArrayLength = length; t.GetObjectArrayElement = element;
  t.GetObjectField = get_object; t.GetStringUTFChars = get_utf; t.ReleaseStringUTFChars = release_utf;
  JNIEnv_ env{&t}; int cases = 0;
  reset(); check(load(&env) == 7, "loader success"); cleaned(); check(utf_gets == 5 && releases == 5, "loader release count"); ++cases;
  int loader_ops = operations;
  reset(); core_status = 0; verify_transcript(transcribe(&env)); cleaned(); ++cases;
  int converter_ops = operations;
  // At every ordinary JNI operation, inject a pending exception. Then repeat
  // with a non-null result alongside that exception to test ownership-before-check.
  for (int mode : {1, 2}) {
    for (int i = 1; i <= loader_ops; ++i) {
      reset(); fault_at = i; fault_mode = mode;
      check(load(&env) == MOONSHINE_ERROR_UNKNOWN && pending && core_calls == 0, "loader fault did not fail closed");
      cleaned(); ++cases;
    }
    for (int i = 1; i <= converter_ops; ++i) {
      reset(); core_status = 0; fault_at = i; fault_mode = mode;
      check(transcribe(&env) == nullptr && pending, "converter fault did not preserve exception");
      cleaned(); ++cases;
    }
  }
  // Null/error without a pending exception: lookup/allocation/acquisition must
  // still fail; scalar setters have no separate status in JNI.
  reset(); core_status = 0; transcribe(&env); auto converter_trace = trace;
  for (int i = 1; i <= converter_ops; ++i) {
    const auto &name = converter_trace[i - 1];
    if (name == "PushLocalFrame" || name == "FindClass" || name == "GetFieldID" ||
        name == "GetMethodID" || name == "NewObject" || name == "NewStringUTF" || name == "NewFloatArray") {
      reset(); core_status = 0; fault_at = i;
      check(transcribe(&env) == nullptr && !pending, "null converter result accepted"); cleaned(); ++cases;
    }
  }
  reset(); load(&env); auto loader_trace = trace;
  for (int i = 1; i <= loader_ops; ++i) {
    reset(); fault_at = i;
    if (loader_trace[i - 1] == "GetArrayLength") continue; // zero length is valid
    check(load(&env) < 0 && !pending && core_calls == 0, "null loader result accepted"); cleaned(); ++cases;
  }
  for (int kind : {1, 2}) {
    reset(); core_throw = kind; check(load(&env) == MOONSHINE_ERROR_UNKNOWN, "loader core throw escaped"); cleaned(); ++cases;
    reset(); core_throw = kind; check(transcribe(&env) == nullptr, "stream core throw escaped"); cleaned(); ++cases;
  }
  for (int status : {-1, -2, -3, -4}) {
    reset(); core_status = status; check(load(&env) == status, "loader core status changed"); cleaned(); ++cases;
    reset(); core_status = status; check(transcribe(&env) == nullptr && operations == 0, "conversion after core error"); cleaned(); ++cases;
  }
  reset(); pending = true; check(load(&env) < 0 && operations == 0 && core_calls == 0, "loader preexisting exception"); cleaned(); ++cases;
  reset(); pending = true; check(transcribe(&env) == nullptr && operations == 0 && core_calls == 0, "stream preexisting exception"); cleaned(); ++cases;
  reset(); options = nullptr; path = nullptr; check(load(&env) == 7 && utf_gets == 0, "null path/options compatibility"); cleaned(); ++cases;
  reset(); core_status = 0; line.text = nullptr; line.audio_data = nullptr; line.audio_data_count = 0;
  line.speaker_span_count = line.word_count = 0;
  auto result = transcribe(&env); check(result != nullptr, "empty audio/null text rejected");
  auto jl = obj(obj(obj(result)->fields.at("lines"))->members[0]);
  check(jl->fields.count("text") == 0 && obj(jl->fields.at("audioData"))->audio.empty(), "null text not preserved"); cleaned(); ++cases;
  reset(); core_status = 0; transcript.line_count = 0; transcript.lines = nullptr;
  check(transcribe(&env) != nullptr, "empty transcript rejected"); cleaned(); ++cases;
  reset(); core_status = 0; null_native_transcript = true;
  check(transcribe(&env) == nullptr, "null native transcript dereferenced"); cleaned(); ++cases;
  for (int invalid : {0, 1, 2, 3, 4, 5}) {
    reset(); core_status = 0;
    if (invalid == 0) transcript.lines = nullptr;
    if (invalid == 1) line.audio_data = nullptr;
    if (invalid == 2) line.audio_data_count = static_cast<uint64_t>(std::numeric_limits<jsize>::max()) + 1;
    if (invalid == 3) transcript.line_count = static_cast<uint64_t>(std::numeric_limits<jsize>::max()) + 1;
    if (invalid == 4) line.speaker_spans = nullptr;
    if (invalid == 5) line.words = nullptr;
    check(transcribe(&env) == nullptr, "invalid native buffer accepted"); cleaned(); ++cases;
  }
  // Large option arrays exercise vector moves and bounded local references.
  reset(300); check(load(&env) == 7 && peak_refs < 16, "large loader local growth/dangling strings"); cleaned(); ++cases;
  reset(); core_status = 0;
  std::vector<transcript_line_t> many_lines(300, line);
  transcript.lines = many_lines.data(); transcript.line_count = many_lines.size();
  check(transcribe(&env) != nullptr && peak_refs < 40, "many-line local reference growth"); cleaned(); ++cases;
  reset(); core_status = 0;
  std::vector<speaker_span_t> many_spans(300, span);
  std::vector<transcript_word_t> many_words(300, word);
  line.speaker_spans = many_spans.data(); line.speaker_span_count = many_spans.size();
  line.words = many_words.data(); line.word_count = many_words.size();
  check(transcribe(&env) != nullptr && peak_refs < 40, "many-span/word local reference growth"); cleaned(); ++cases;
  reset();
  for (int i = 0; i < 100; ++i) {
    core_status = 7; check(load(&env) == 7, "repeated load"); cleaned();
    core_status = 0; result = transcribe(&env); verify_transcript(result); cleaned();
    delete_ref(&env, result); check(refs() == 0, "repeated-call root reference leak"); ++cases;
  }
  std::printf("PASS %d required JNI cases; %d loader/%d converter fault sites; pending/null/core errors, UTF/local-frame cleanup, metadata, repeated calls\n",
              cases, loader_ops, converter_ops);
}
