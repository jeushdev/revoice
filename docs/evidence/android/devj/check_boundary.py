"""Small offline M0 checks: pinned Java wrapper/fake JNI and conditional VAD math.

Requires an existing text-source checkout, Python and a JDK. Downloads nothing;
compiles only inside a temporary directory. Not an Android or inference test.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


HERE = Path(__file__).resolve().parent

STUBS = {
    "android/content/res/AssetManager.java": """
package android.content.res;
public class AssetManager {
  public java.io.InputStream open(String path) throws java.io.IOException {
    throw new java.io.IOException("fake assets are unavailable");
  }
}
""",
    "android/util/Log.java": "package android.util; public class Log {}",
    "androidx/appcompat/app/AppCompatActivity.java": """
package androidx.appcompat.app;
public class AppCompatActivity {
  public android.content.res.AssetManager getAssets() {
    return new android.content.res.AssetManager();
  }
}
""",
    "ai/moonshine/voice/JNI.java": """
package ai.moonshine.voice;
public class JNI {
  public static final int MOONSHINE_MODEL_ARCH_TINY_STREAMING = 2;
  public static final int MOONSHINE_FLAG_FORCE_UPDATE = 1;
  public static final int MOONSHINE_ERROR_NONE = 0;
  public static int startStatus, addStatus, stopStatus;
  public static int startCalls, addCalls, stopCalls, transcribeCalls, lastFlags;
  public static Transcript nextTranscript;
  public static void reset() {
    startStatus = addStatus = stopStatus = 0;
    startCalls = addCalls = stopCalls = transcribeCalls = lastFlags = 0;
    nextTranscript = new Transcript();
    nextTranscript.lines = java.util.List.of();
  }
  public static void setLastPass(Transcriber t, double seconds) {
    t.lastPassSeconds.put(1, seconds);
  }
  public static void ensureLibraryLoaded() {}
  public static String moonshineGetSttDependencies(String s, Object[] o) { return "{}"; }
  public static String moonshineGetDiarizationDependencies() { return "{}"; }
  public static int moonshineLoadTranscriberFromFiles(String p, int a, Object[] o) { return 1; }
  public static int moonshineLoadTranscriberFromMemory(byte[] e, byte[] d, byte[] t,
      byte[] s, int a, Object[] o) { return 1; }
  public static int moonshineLoadTranscriberFromMemoryFiles(String[] f, byte[][] b,
      int a, Object[] o) { return 1; }
  public static void moonshineFreeTranscriber(int t) {}
  public static int moonshineCreateStream(int t, int f) { return 1; }
  public static int moonshineFreeStream(int t, int s) { return 0; }
  public static int moonshineStartStream(int t, int s) { startCalls++; return startStatus; }
  public static int moonshineStopStream(int t, int s) { stopCalls++; return stopStatus; }
  public static int moonshineAddAudioToStream(int t, int s, float[] a, int r, int f) {
    addCalls++; return addStatus;
  }
  public static Transcript moonshineTranscribeStream(int t, int s, int f) {
    transcribeCalls++; lastFlags = f; return nextTranscript;
  }
  public static Transcript moonshineTranscribeWithoutStreaming(int t, float[] a,
      int r, int f) { return nextTranscript; }
  public static int moonshineTranscriberSetKeyterms(int t, String s) { return 0; }
  public static int moonshineTranscriberSetContext(int t, String s, int m) { return 0; }
  public static String moonshineErrorToString(int e) { return "fake error"; }
}
""",
}


class ConditionalVadMath(unittest.TestCase):
    """Probability fixtures, NOT Silero predictions or compiled SDK VAD."""

    def test_pinned_window_and_chunk(self):
        window = math.ceil(0.5 * 16000 / 512)
        self.assertEqual(window, 16)
        self.assertEqual(window * 512, 8192)
        self.assertEqual(window * 512 / 16000, 0.512)

    def test_zero_probabilities_close_worst_full_window(self):
        values = [1.0] * 16
        # Match source's strict smoothed_probability > threshold predicate.
        for i in range(8):
            values[i] = 0.0
        self.assertFalse(sum(values) / len(values) > 0.5)

    def test_silence_has_no_unconditional_model_bound(self):
        values = [0.6] * 16
        for i in range(100):
            values[i % 16] = 0.6  # Counterexample probability, not a prediction.
        self.assertTrue(sum(values) / len(values) > 0.5)

    def test_gate_can_exceed_proposed_silence_cap(self):
        java_gate = min(max(0.5, 100.0), 0.5 * 10)
        self.assertEqual(java_gate, 5.0)
        self.assertLess(4 * 8192 / 16000, java_gate)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--scratch-root", type=Path,
                        default=Path(tempfile.gettempdir()) / "opencode")
    args = parser.parse_args()
    pins = json.loads((HERE / "source-pins.json").read_text(encoding="utf-8"))
    for relative, expected in pins["files"].items():
        actual = hashlib.sha256((args.source_root / relative).read_bytes()).hexdigest()
        if actual != expected:
            raise SystemExit(f"Source hash mismatch: {relative}")
    print(f"PASS {len(pins['files'])} pinned source hashes", flush=True)
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(ConditionalVadMath)
    if not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful():
        raise SystemExit(1)
    if not shutil.which("javac") or not shutil.which("java"):
        raise SystemExit("JDK java/javac required; no installation attempted")
    if not args.scratch_root.is_dir():
        raise SystemExit("Existing --scratch-root directory required")
    with tempfile.TemporaryDirectory(prefix="devj-moonshine-wrapper-",
                                     dir=args.scratch_root) as temporary:
        root = Path(temporary)
        java_files = []
        for relative in pins["files"]:
            if relative.endswith(".java"):
                target = root / "ai/moonshine/voice" / Path(relative).name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(args.source_root / relative, target)
                java_files.append(str(target))
        for relative, content in STUBS.items():
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8")
            java_files.append(str(target))
        java_files.append(str(HERE / "WrapperBoundaryCheck.java"))
        classes = root / "classes"
        classes.mkdir()
        subprocess.run(["javac", "--release", "11", "-d", str(classes), *java_files], check=True)
        subprocess.run(["java", "-cp", str(classes),
                        "com.larpcode.revise.m0.WrapperBoundaryCheck"], check=True)
    print("No native library, model inference, microphone or Android device exercised.")


if __name__ == "__main__":
    main()
