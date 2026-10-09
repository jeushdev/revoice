"""Offline, review-only per-stream VAD tests; no model inference or SDK adoption.

Compiles both exact patched core translation units with real pinned dependency
headers, fake ORT/resampler/debug implementations and a test-only model stub.
Optional Android object builds do NOT link/repack libmoonshine or an AAR.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
APPROVED = Path(os.environ["LOCALAPPDATA"]) / "Temp/opencode/devj-moonshine-sdk-fix"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source-root", type=Path, default=APPROVED / "cross-session-inputs")
    p.add_argument("--run-name", default="cross-session-r1")
    p.add_argument("--host-cxx", type=Path, default=Path(r"C:\msys64\mingw64\bin\g++.exe"))
    p.add_argument("--ndk", type=Path,
                   default=Path(os.environ["LOCALAPPDATA"]) / "Android/Sdk/ndk/28.2.13676358")
    p.add_argument("--android-objects", action="store_true")
    p.add_argument("--mutations", action="store_true",
                   help="Require regressions to reject shared history and incomplete resets")
    a = p.parse_args()
    if sys.flags.optimize:
        p.error("Run without -O/PYTHONOPTIMIZE")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", a.run_name):
        p.error("run-name must be a single directory name")
    out = APPROVED / a.run_name
    out.mkdir()  # Never overwrite a prior result.
    pins = json.loads((HERE / "core-inputs.json").read_text())
    results = {"scope": "REVIEW ONLY; FAKE ORT; NOT LINKED OR ADOPTED",
               "source_commit": pins["commit"], "inputs": {}, "outputs": {}, "commands": []}
    env = dict(os.environ)
    env["PATH"] = str(a.host_cxx.parent) + os.pathsep + env["PATH"]
    env["TEMP"] = env["TMP"] = str(out)

    def run(args, label, cwd=out, expected_assertion=None):
        args = list(map(str, args))
        result = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True)
        (out / (label + ".log")).write_text(result.stdout + result.stderr, encoding="utf-8")
        results["commands"].append({"argv": args, "exit": result.returncode, "log": label + ".log"})
        print(label, "exit", result.returncode, flush=True)
        if expected_assertion is not None:
            if not result.returncode or expected_assertion not in result.stdout + result.stderr:
                raise SystemExit("Mutation did not fail the intended assertion: " + label)
            return "Expected regression assertion observed"
        if result.returncode:
            print(result.stdout + result.stderr)
            raise SystemExit(result.returncode)
        return result.stdout

    try:
        patch = HERE / "0004-per-stream-vad-state.patch"
        for f in [Path(__file__), HERE / "core-inputs.json", patch,
                  HERE / "vad_state_test.cpp", HERE / "vad_test_support/silero-vad-model-data.h"]:
            results["inputs"][str(f.relative_to(HERE))] = digest(f.read_bytes())
        source = out / "patched"
        for rel, h in pins["files"].items():
            data = (a.source_root / rel).read_bytes()
            if digest(data) != h:
                raise SystemExit("Source mismatch: " + rel)
            target = source / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            results["inputs"][rel] = h
        run(["git", "apply", "--check", patch], "core-patch-check", source)
        run(["git", "apply", patch], "core-patch-apply", source)
        core = source / "core"
        sources = [core / "silero-vad.cpp", core / "voice-activity-detector.cpp"]
        for f in [*sources, core / "silero-vad.h", core / "voice-activity-detector.h"]:
            results["outputs"][str(f.relative_to(source))] = digest(f.read_bytes())
        includes = ["-I" + str(d) for d in [core, core / "ort-utils", core / "moonshine-utils",
                    core / "third-party/onnxruntime/include", HERE / "vad_test_support"]]
        exe = out / "vad-state-test.exe"
        run([a.host_cxx, "--version"], "host-compiler")
        run([a.host_cxx, "-std=c++20", "-Wall", "-Wextra", "-Werror", "-O2",
             "-D_GLIBCXX_ASSERTIONS", "-pthread", *includes, *sources,
             HERE / "vad_state_test.cpp", "-o", exe], "host-core-compile")
        print(run([exe], "host-core-test"))
        print(run([exe, "singleton-retry"], "host-singleton-retry"))
        results["outputs"][exe.name] = digest(exe.read_bytes())
        if a.mutations:
            text = sources[1].read_text()
            mutations = {
                "no-history-reset": ("  silero_state.reset();", "  // reset deliberately removed",
                                      "zero(a.silero_state.recurrent)"),
                "resize-not-clear": (".assign(", ".resize(",
                                     "zero(a.probability_window)"),
                "shared-history": ("silero_vad->predict(audio_vec, silero_state,",
                                   "silero_vad->predict(audio_vec, shared_history,",
                                   "v.silero_state.recurrent[0] == 1.0f"),
            }
            for name, (before, after, assertion) in mutations.items():
                assert before in text
                mutated = text.replace(before, after)
                if name == "shared-history":
                    mutated = mutated.replace("std::mutex vad_mutex;",
                                              "std::mutex vad_mutex;\nSileroVad::State shared_history;")
                mutant = out / (name + ".cpp")
                mutant.write_text(mutated)
                mutant_exe = out / (name + ".exe")
                run([a.host_cxx, "-std=c++20", "-Wall", "-Wextra", "-Werror", "-O2",
                     "-D_GLIBCXX_ASSERTIONS", "-pthread", *includes, sources[0], mutant,
                     HERE / "vad_state_test.cpp", "-o", mutant_exe], name + "-compile")
                run([mutant_exe], name + "-rejected", expected_assertion=assertion)
        if a.android_objects:
            results["inputs"]["ndk-inputs.json"] = digest((HERE / "ndk-inputs.json").read_bytes())
            for rel, h in json.loads((HERE / "ndk-inputs.json").read_text()).items():
                if digest((a.ndk / rel).read_bytes()) != h:
                    raise SystemExit("NDK dependency mismatch: " + rel)
                results["inputs"]["NDK/" + rel] = h
            llvm = a.ndk / "toolchains/llvm/prebuilt/windows-x86_64/bin"
            for abi, target in {"arm64-v8a": "aarch64-linux-android26",
                                "armeabi-v7a": "armv7a-linux-androideabi26",
                                "x86_64": "x86_64-linux-android26"}.items():
                for f in sources:
                    obj = out / (abi + "-" + f.stem + ".o")
                    run([llvm / "clang++.exe", "--target=" + target,
                         "--sysroot=" + str(llvm.parent / "sysroot"), "-std=c++20",
                         "-DANDROID", "-Wall", "-Wextra", "-Werror", "-O2", "-fPIC",
                         *includes, "-c", f, "-o", obj], abi + "-" + f.stem)
                    results["outputs"][obj.name] = digest(obj.read_bytes())
    finally:
        (out / "results.json").write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
