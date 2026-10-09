"""Review-only offline SDK patch, tests and optional JNI cross-build/repack.

Does not install, resolve app dependencies, modify pins, or access a device.
Requires pre-fetched hash-pinned text sources/artifacts; downloads nothing.
Outputs only to a NEW directory within the approved scratch workspace.
"""
import argparse
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import zipfile

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
APPROVED = Path(os.environ["LOCALAPPDATA"]) / "Temp/opencode/devj-moonshine-sdk-fix"
PINS = json.loads((HERE / "inputs.json").read_text())


def digest(data):
    return hashlib.sha256(data).hexdigest()


def run(args, cwd, label, results, env=None):
    args = list(map(str, args))
    effective_env = dict(os.environ if env is None else env)
    effective_env["TEMP"] = effective_env["TMP"] = str(cwd)
    p = subprocess.run(args, cwd=cwd, env=effective_env, capture_output=True, text=True)
    (cwd / (label + ".log")).write_text(p.stdout + p.stderr, encoding="utf-8")
    results["commands"].append({"argv": args, "exit": p.returncode, "log": label + ".log"})
    print(label, "exit", p.returncode, flush=True)
    if p.returncode:
        print(p.stdout + p.stderr)
        raise SystemExit(p.returncode)
    return p.stdout


def unpack_selected(z, destination, names):
    for name in names:
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(z.read(name))


def deterministic_zip(entries):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for name, data in sorted(entries.items()):
            item = zipfile.ZipInfo(name, date_time=(2026, 8, 24, 0, 0, 0))
            item.compress_type = zipfile.ZIP_DEFLATED
            item.external_attr = 0o100644 << 16
            z.writestr(item, data, compresslevel=9)
    return buffer.getvalue()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source-root", type=Path, default=APPROVED / "upstream")
    p.add_argument("--artifact-root", type=Path,
                   default=APPROVED.parent / "devj-sdk-artifact-review")
    p.add_argument("--run-name", default="candidate-r1")
    p.add_argument("--jdk", type=Path, default=Path(r"C:\Program Files\Java\jdk-26.0.2.1"))
    p.add_argument("--host-cxx", type=Path, default=Path(r"C:\msys64\mingw64\bin\g++.exe"))
    p.add_argument("--ndk", type=Path,
                   default=Path(os.environ["LOCALAPPDATA"]) / "Android/Sdk/ndk/28.2.13676358")
    p.add_argument("--cross-build", action="store_true")
    p.add_argument("--jni-syntax-check", action="store_true",
                   help="Compile-check the complete patched JNI translation unit for all three Android ABIs; no link/repack")
    a = p.parse_args()
    if sys.flags.optimize:
        p.error("Run without -O/PYTHONOPTIMIZE; preservation assertions must remain enabled")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", a.run_name):
        p.error("run-name must be a single directory name")
    out = APPROVED / a.run_name
    out.mkdir()  # Never overwrite or delete an existing probe.
    results = {"scope": "REVIEW ONLY; NOT ADOPTED OR DEVICE-TESTED", "commands": [],
                "source_commit": PINS["commit"], "inputs": {}, "outputs": {}}
    try:
        for name in ["review.py", "inputs.json", "ndk-inputs.json", "jni_cleanup_test.cpp",
                     "jni_required_path_test.cpp", "CheckedBoundaryTest.java", "StopLedgerFixture.java"]:
            results["inputs"]["review-harness/" + name] = digest((HERE / name).read_bytes())
        results["inputs"]["review-harness/check_boundary.py"] = digest(
            (HERE.parent / "check_boundary.py").read_bytes())
        if a.cross_build or a.jni_syntax_check:
            for rel, h in json.loads((HERE / "ndk-inputs.json").read_text()).items():
                if digest((a.ndk / rel).read_bytes()) != h:
                    raise SystemExit("NDK dependency mismatch: " + rel)
                results["inputs"]["NDK/" + rel] = h
        for rel, h in PINS["files"].items():
            b = (a.source_root / rel).read_bytes()
            if digest(b) != h:
                raise SystemExit("Source mismatch: " + rel)
            target = out / "patched" / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b)
            results["inputs"][rel] = h
        for name, h in PINS["artifacts"].items():
            if digest((a.artifact_root / name).read_bytes()) != h:
                raise SystemExit("Artifact mismatch: " + name)
            results["inputs"][name] = h
        for patch in sorted(HERE.glob("*.patch")):
            results["inputs"][patch.name] = digest(patch.read_bytes())
            run(["git", "apply", "--check", patch], out / "patched",
                patch.stem + "-check", results)
            run(["git", "apply", patch], out / "patched", patch.stem, results)

        source = out / "patched"
        cpp = source / "language-bindings/android/moonshine-jni/moonshine-jni.cpp"
        java = source / "language-bindings/android/java/main/java/ai/moonshine/voice/Transcriber.java"
        results["outputs"]["patched-jni-source"] = digest(cpp.read_bytes())
        results["outputs"]["patched-java-source"] = digest(java.read_bytes())
        text = cpp.read_text()
        start = text.index('extern "C" JNIEXPORT int JNICALL\nJava_ai_moonshine_voice_JNI_moonshineAddAudioToStream')
        end = text.index('\nextern "C" JNIEXPORT', start + 1)
        (out / "streaming-add.inc").write_text(text[start:end])
        guards_start = text.index('// Only the required file-loader')
        guards_end = text.index('\nstatic bool fill_moonshine_options', guards_start)
        (out / "required-converter.inc").write_text(text[guards_start:guards_end])
        for name, output in [("moonshineLoadTranscriberFromFiles", "required-loader.inc"),
                             ("moonshineTranscribeStream", "required-stream.inc")]:
            start = text.index('Java_ai_moonshine_voice_JNI_' + name + '(')
            start = text.rindex('extern "C" JNIEXPORT', 0, start)
            end = text.index('\nextern "C" JNIEXPORT', start + 1)
            # Loader is followed by shared memory-loader helpers, not another export.
            if name == "moonshineLoadTranscriberFromFiles":
                end = text.index('\n// Copies a jbyteArray', start)
            (out / output).write_text(text[start:end])
        host_env = dict(os.environ)
        host_env["PATH"] = str(a.host_cxx.parent) + os.pathsep + host_env["PATH"]
        run([a.host_cxx, "--version"], out, "host-compiler", results, host_env)
        run([a.host_cxx, "-std=c++20", "-Wall", "-Wextra", "-Werror", "-O2",
             "-I" + str(a.jdk / "include"), "-I" + str(a.jdk / "include/win32"),
             "-I" + str(source / "core"), "-I" + str(out),
             HERE / "jni_cleanup_test.cpp", "-o", out / "jni-cleanup-test.exe"],
            out, "host-jni-compile", results, host_env)
        print(run([out / "jni-cleanup-test.exe"], out, "host-jni-test", results, host_env))
        run([a.host_cxx, "-std=c++20", "-Wall", "-Wextra", "-Werror", "-O2",
             "-I" + str(a.jdk / "include"), "-I" + str(a.jdk / "include/win32"),
             "-I" + str(source / "core"),
             "-I" + str(source / "core/third-party/utf-8"), "-I" + str(out),
             HERE / "jni_required_path_test.cpp", "-o", out / "jni-required-path-test.exe"],
            out, "host-required-jni-compile", results, host_env)
        print(run([out / "jni-required-path-test.exe"], out, "host-required-jni-test", results, host_env))

        # Reuse only test signature stubs; do not import bytecode caches into repo.
        spec = importlib.util.spec_from_file_location("boundary", HERE.parent / "check_boundary.py")
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
        stubs = dict(m.STUBS)
        stubs["ai/moonshine/voice/JNI.java"] = stubs["ai/moonshine/voice/JNI.java"].replace(
            "public static Transcript nextTranscript;",
            "public static Transcript nextTranscript;\n  public static boolean addThrowsOom;\n"
            "  public static long addedSamples, newAudioSamples;\n  public static int lastAddLength;\n"
            "  public static boolean lastTranscribeHadNewAudio;\n"
            "  public static java.util.List<String> calls = new java.util.ArrayList<>();").replace(
            "moonshineGetSttDependencies(String s, Object[] o)",
            "moonshineGetSttDependencies(String s, TranscriberOption[] o)").replace(
            "startStatus = addStatus = stopStatus = 0;",
            "startStatus = addStatus = stopStatus = 0; addThrowsOom = false; addedSamples = newAudioSamples = 0; "
            "lastAddLength = 0; lastTranscribeHadNewAudio = false; calls.clear();").replace(
            "startCalls++; return startStatus;", 'startCalls++; calls.add("start"); return startStatus;').replace(
            "stopCalls++; return stopStatus;", 'stopCalls++; calls.add("stop"); return stopStatus;').replace(
            "addCalls++; return addStatus;",
            'addCalls++; calls.add("add:" + a.length); if (addThrowsOom) throw new OutOfMemoryError("fake JNI OOM"); '
            "lastAddLength = a.length; if (addStatus == 0) { addedSamples = Math.addExact(addedSamples, a.length); "
            "newAudioSamples = Math.addExact(newAudioSamples, a.length); } return addStatus;").replace(
            "transcribeCalls++; lastFlags = f; return nextTranscript;",
            'transcribeCalls++; lastFlags = f; lastTranscribeHadNewAudio = newAudioSamples != 0; '
            'calls.add(lastTranscribeHadNewAudio ? "transcribe:new" : "transcribe:cached"); '
            "newAudioSamples = 0; return nextTranscript;")
        stub_files = []
        for name, content in stubs.items():
            dst = out / "test-stubs" / name
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_text(content)
            stub_files.append(dst)
        java_files = [source / name for name in PINS["files"] if name.endswith(".java")]
        classes = out / "test-classes"
        classes.mkdir()
        run([a.jdk / "bin/javac.exe", "--release", "11", "-d", classes,
             *java_files, *stub_files, HERE / "CheckedBoundaryTest.java", HERE / "StopLedgerFixture.java"],
            out, "java-test-compile", results)
        print(run([a.jdk / "bin/java.exe", "-cp", classes, "ai.moonshine.voice.CheckedBoundaryTest"],
                  out, "java-test", results))
        if a.jni_syntax_check:
            llvm = a.ndk / "toolchains/llvm/prebuilt/windows-x86_64/bin"
            for abi, target in {"arm64-v8a": "aarch64-linux-android26",
                                "armeabi-v7a": "armv7a-linux-androideabi26",
                                "x86_64": "x86_64-linux-android26"}.items():
                run([llvm / "clang++.exe", "--target=" + target,
                     "--sysroot=" + str(llvm.parent / "sysroot"), "-std=c++20",
                     "-Wall", "-Wextra", "-Werror", "-fsyntax-only",
                     "-I" + str(source / "core"),
                     "-I" + str(source / "core/third-party/utf-8"), cpp],
                    out, abi + "-jni-syntax", results)
        if not a.cross_build:
            return

        # Compile Java against ORIGINAL published JNI/classes, NOT fake JNI.
        with zipfile.ZipFile(a.artifact_root / "moonshine-voice-0.1.5.aar") as aar:
            entries = {n: aar.read(n) for n in aar.namelist() if not n.endswith("/")}
        original_classes = out / "original-classes.jar"
        original_classes.write_bytes(entries["classes.jar"])
        signature_classes = out / "compile-signatures"
        signature_classes.mkdir()
        android_stubs = [f for f in stub_files if f.name != "JNI.java"]
        run([a.jdk / "bin/javac.exe", "--release", "11", "-d", signature_classes,
             *android_stubs], out, "signature-compile", results)
        candidate_classes = out / "candidate-classes"
        candidate_classes.mkdir()
        run([a.jdk / "bin/javac.exe", "--release", "11", "-classpath",
             str(original_classes) + os.pathsep + str(signature_classes), "-d", candidate_classes,
             java], out, "candidate-java-compile", results)
        with zipfile.ZipFile(io.BytesIO(entries["classes.jar"])) as z:
            class_entries = {n: z.read(n) for n in z.namelist() if not n.endswith("/")}
        changed_classes = list(candidate_classes.rglob("*.class"))
        assert [f.name for f in changed_classes] == ["Transcriber.class"]
        key = "ai/moonshine/voice/Transcriber.class"
        class_entries[key] = changed_classes[0].read_bytes()
        assert class_entries[key] == (classes / key).read_bytes(), "Tests must exercise identical candidate bytecode"
        entries["classes.jar"] = deterministic_zip(class_entries)
        results["outputs"]["Transcriber.class"] = digest(class_entries[key])
        llvm = a.ndk / "toolchains/llvm/prebuilt/windows-x86_64/bin"
        run([llvm / "clang++.exe", "--version"], out, "ndk-compiler", results)
        targets = {"arm64-v8a": "aarch64-linux-android26", "armeabi-v7a": "armv7a-linux-androideabi26",
                   "x86_64": "x86_64-linux-android26"}
        for abi, target in targets.items():
            libdir = out / "libs" / abi
            libdir.mkdir(parents=True)
            for name in ["libmoonshine.so", "libonnxruntime.so"]:
                b = entries["jni/" + abi + "/" + name]
                (libdir / name).write_bytes(b)
                results["inputs"][abi + "/" + name] = digest(b)
            built = libdir / "libmoonshine-jni.so"
            extra = ["-mthumb", "-march=armv7-a", "-mfpu=neon", "-mfloat-abi=softfp"] if abi == "armeabi-v7a" else []
            run([llvm / "clang++.exe", "--target=" + target,
                 "--sysroot=" + str(llvm.parent / "sysroot"), "-std=c++20", "-O2", "-DNDEBUG",
                 "-fPIC", "-fvisibility=hidden", "-fvisibility-inlines-hidden", "-shared",
                 "-static-libstdc++", "-Wall", "-Wextra", "-Werror", *extra,
                 "-I" + str(source / "core"), "-I" + str(source / "core/third-party/utf-8"),
                 cpp, "-L" + str(libdir), "-Wl,--no-undefined", "-Wl,--build-id=sha1",
                 "-Wl,-soname,libmoonshine-jni.so", "-Wl,-z,max-page-size=16384",
                 "-Wl,-z,relro", "-Wl,-z,now", "-lmoonshine", "-lonnxruntime", "-landroid", "-llog",
                 "-o", built], out, abi + "-jni-build", results)
            run([llvm / "llvm-readelf.exe", "-h", "-n", "-d", "-l", built],
                out, abi + "-elf", results)
            triple = ["--triple=thumbv7a-linux-android"] if abi == "armeabi-v7a" else []
            run([llvm / "llvm-objdump.exe", "-d", *triple,
                 "--disassemble-symbols=Java_ai_moonshine_voice_JNI_moonshineAddAudioToStream", built],
                out, abi + "-add-disassembly", results)
            entries["jni/" + abi + "/libmoonshine-jni.so"] = built.read_bytes()
            results["outputs"][abi + "/libmoonshine-jni.so"] = digest(built.read_bytes())
        candidate = out / "moonshine-voice-0.1.5-revise-review-required-path.aar"
        candidate.write_bytes(deterministic_zip(entries))
        results["outputs"][candidate.name] = digest(candidate.read_bytes())
        # Positive per-entry preservation proof; only four payload entries changed.
        with zipfile.ZipFile(a.artifact_root / "moonshine-voice-0.1.5.aar") as original:
            changed = [n for n in entries if entries[n] != original.read(n)]
        assert sorted(changed) == sorted(["classes.jar"] + ["jni/" + x + "/libmoonshine-jni.so" for x in targets])
        results["changed_aar_entries"] = changed
        print("REVIEW-ONLY candidate", candidate, results["outputs"][candidate.name])
    finally:
        (out / "results.json").write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
