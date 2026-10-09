"""Offline, review-only full pinned Moonshine rebuild. No AAR or app adoption.

Requires prepare_full_core.py output; verifies every prepared input again.
Android builds the upstream moonshine-jni target AND its full native dependency
graph (including the changed C++ consumers). Host builds the full static core and
a linked real inference fixture. No fake ORT, model stub, or binary overlay.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
APPROVED = Path(os.environ["LOCALAPPDATA"]) / "Temp/opencode/devj-moonshine-sdk-fix"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source-root", type=Path, required=True)
    p.add_argument("--run-name", required=True)
    p.add_argument("--android", action="store_true")
    p.add_argument("--host", action="store_true")
    p.add_argument("--abis", nargs="+", default=["arm64-v8a", "armeabi-v7a", "x86_64"],
                   choices=["arm64-v8a", "armeabi-v7a", "x86_64"])
    p.add_argument("--jobs", type=int, default=4)
    p.add_argument("--cmake", type=Path, default=Path(os.environ["LOCALAPPDATA"]) / "Android/Sdk/cmake/3.22.1/bin/cmake.exe")
    p.add_argument("--ndk", type=Path, default=Path(os.environ["LOCALAPPDATA"]) / "Android/Sdk/ndk/28.2.13676358")
    p.add_argument("--msvc-bin", type=Path, default=Path(r"C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC\14.29.30133\bin\Hostx64\x64"))
    p.add_argument("--assets", type=Path, help="Optional existing revise asset root for real C API speech checks")
    a = p.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_-]+", a.run_name) or a.jobs < 1:
        p.error("Invalid run name or job count")
    if not (a.host or a.android):
        p.error("Select --host and/or --android")
    out = APPROVED / a.run_name
    out.mkdir()
    result = {"scope": "REVIEW ONLY; FULL CORE; REAL EMBEDDED SILERO; NO ADOPTION",
              "commands": [], "inputs": {}, "outputs": {}, "complete": False}
    env = dict(os.environ)
    env["TEMP"] = env["TMP"] = str(out)

    def record(path, label):
        result["inputs"][label] = sha(path)

    def verify_tools(root, entries, prefix):
        for rel, expected in entries.items():
            if sha(root / rel) != expected:
                raise RuntimeError("Toolchain hash mismatch: " + rel)
            result["inputs"][prefix + rel] = expected

    def run(args, label):
        args = list(map(str, args))
        r = subprocess.run(args, cwd=out, env=env, capture_output=True, text=True, errors="replace")
        (out / (label + ".log")).write_text(r.stdout + r.stderr, encoding="utf-8")
        result["commands"].append({"argv": args, "exit": r.returncode, "log": label + ".log"})
        print(label, "exit", r.returncode, flush=True)
        if r.returncode:
            print((r.stdout + r.stderr)[-12000:])
            raise RuntimeError("Failed: " + label)

    try:
        preparation = json.loads((a.source_root / "preparation.json").read_text())
        pins = json.loads((HERE / "full-core-inputs.json").read_text())
        if not preparation.get("complete") or preparation["commit"] != pins["commit"] or preparation["archive_sha256"] != pins["archive"]["sha256"]:
            raise RuntimeError("Unverified preparation")
        manifest_hash = hashlib.sha256(json.dumps(preparation["files"], sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        if manifest_hash != pins["prepared_files_manifest_sha256"] or preparation["patched_files"] != pins["patched_files"]:
            raise RuntimeError("Prepared file manifest does not match pinned scope")
        result["source_commit"] = pins["commit"]
        record(a.source_root / "preparation.json", "preparation.json")
        for rel, entry in preparation["files"].items():
            expected = preparation["patched_files"].get(rel, entry["sha256"])
            path = a.source_root / rel
            if sha(path) != expected:
                raise RuntimeError("Prepared source mismatch: " + rel)
            result["inputs"]["source/" + rel] = expected
        for name, expected in preparation["patches"].items():
            if sha(HERE / name) != expected:
                raise RuntimeError("Patch changed since preparation: " + name)
            record(HERE / name, name)
        for name in ["full-core-inputs.json", "full-core-lfs-pointers.json", "prepare_full_core.py", "review_full_core.py",
                     "full-core-toolchain-inputs.json", "full-core-review/CMakeLists.txt", "real_vad_test.cpp"]:
            record(HERE / name, name)
        tools = json.loads((HERE / "full-core-toolchain-inputs.json").read_text())
        verify_tools(a.cmake.parent, tools["cmake"], "CMake/")
        record(a.cmake, "cmake.exe")
        run([a.cmake, "--version"], "cmake-version")
        common = ["-S", HERE / "full-core-review", "-DPINNED_SOURCE=" + a.source_root.as_posix(),
                  "-DMOONSHINE_TTS_BUILD_ONNX=ON"]
        if a.android:
            verify_tools(a.ndk, tools["ndk_extra"], "NDK/")
            for rel, h in json.loads((HERE / "ndk-inputs.json").read_text()).items():
                if sha(a.ndk / rel) != h:
                    raise RuntimeError("NDK pin mismatch: " + rel)
                result["inputs"]["NDK/" + rel] = h
            record(HERE / "ndk-inputs.json", "ndk-inputs.json")
            ninja = a.cmake.parent / "ninja.exe"
            record(ninja, "ninja.exe")
            record(a.ndk / "build/cmake/android.toolchain.cmake", "android.toolchain.cmake")
            for abi in a.abis:
                build = out / abi
                run([a.cmake, *common, "-B", build, "-G", "Ninja", "-DCMAKE_MAKE_PROGRAM=" + ninja.as_posix(),
                     "-DCMAKE_TOOLCHAIN_FILE=" + (a.ndk / "build/cmake/android.toolchain.cmake").as_posix(),
                     "-DANDROID_ABI=" + abi, "-DANDROID_PLATFORM=android-26", "-DANDROID_STL=c++_static",
                     "-DCMAKE_BUILD_TYPE=RelWithDebInfo", "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"], abi + "-configure")
                commands = json.loads((build / "compile_commands.json").read_text())
                if any("vad_test_support" in c["command"] for c in commands):
                    raise RuntimeError("Test-only include leaked into full build")
                consumers = ["silero-vad.cpp", "voice-activity-detector.cpp", "transcriber.cpp",
                             "speech-clip.cpp", "clone-clip.cpp", "moonshine-c-api.cpp", "moonshine-jni.cpp"]
                for name in consumers:
                    matches = [c for c in commands if Path(c["file"]).name == name
                               and any(t in c["command"] for t in ["moonshine.dir", "moonshine-jni.dir"])]
                    if len(matches) != 1:
                        raise RuntimeError("Changed C++ consumers not rebuilt together: " + name)
                graph = {"reviewed_consumers": consumers,
                         "translation_units": {target: sum(target + ".dir" in c["command"] for c in commands)
                                               for target in ["moonshine", "moonshine-jni", "ort-utils", "moonshine-utils",
                                                              "bin-tokenizer", "moonshine_tts_utf8proc", "moonshine_tts_core", "moonshine_tts_ort"]}}
                (build / "reviewed-build-graph.json").write_text(json.dumps(graph, indent=2) + "\n")
                result["outputs"][(build / "reviewed-build-graph.json").relative_to(out).as_posix()] = sha(build / "reviewed-build-graph.json")
                run([a.cmake, "--build", build, "--target", "moonshine-jni", "--parallel", a.jobs], abi + "-full-link")
                for path in build.rglob("*.so"):
                    result["outputs"][path.relative_to(out).as_posix()] = sha(path)
                    run([a.ndk / "toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-readelf.exe",
                         "--file-header", "--dynamic", "--dyn-syms", path], abi + "-" + path.stem + "-elf")
                for name in ["compile_commands.json", "CMakeCache.txt", "build.ninja"]:
                    result["outputs"][(build / name).relative_to(out).as_posix()] = sha(build / name)
        if a.host:
            verify_tools(a.msvc_bin, tools["msvc_14.29.30133"], "MSVC/")
            build = out / "host"
            run([a.cmake, *common, "-B", build, "-G", "Visual Studio 16 2019", "-A", "x64",
                 "-T", "version=14.29.30133", "-DCMAKE_SYSTEM_VERSION=10.0.26100.0",
                 "-DREVIEW_FIXTURE=" + (HERE / "real_vad_test.cpp").as_posix()], "host-configure")
            run([a.cmake, "--build", build, "--config", "RelWithDebInfo", "--target", "real-vad-review", "--parallel", a.jobs], "host-full-link")
            for path in build.rglob("*"):
                if path.suffix in [".lib", ".dll", ".exe"] and path.is_file():
                    result["outputs"][path.relative_to(out).as_posix()] = sha(path)
            result["outputs"]["host/CMakeCache.txt"] = sha(build / "CMakeCache.txt")
            exe = build / "RelWithDebInfo/real-vad-review.exe"
            args = [exe, a.source_root / "test-assets/two_cities_16k.wav", a.source_root / "test-assets/beckett.wav"]
            if a.assets:
                manifest = json.loads((a.assets / "model-manifest.json").read_text())
                record(a.assets / "model-manifest.json", "existing-model-manifest.json")
                for entry in manifest["files"]:
                    if entry["group"] != "stt":
                        continue
                    path = a.assets / entry["path"]
                    if path.stat().st_size != entry["sizeBytes"] or sha(path) != entry["sha256"]:
                        raise RuntimeError("Existing speech asset mismatch: " + entry["path"])
                    result["inputs"]["existing-assets/" + entry["path"]] = entry["sha256"]
                args.append(a.assets / "models/stt")
            run(args, "host-real-inference")
        result["complete"] = True
    except Exception as e:
        result["failure"] = str(e)
        raise
    finally:
        (out / "results.json").write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
