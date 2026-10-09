"""Offline ELF audit of review-only full native builds. Not packaging approval.

Checks actual ABI, SONAME/NEEDED, all JNI exports and their Moonshine imports,
against the hash-recorded full build. Never strips, repacks or adopts libraries.
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
    p.add_argument("--run-name", required=True)
    p.add_argument("--source-root", type=Path, required=True)
    p.add_argument("--audit-name", default="elf-audit")
    p.add_argument("--ndk", type=Path, default=Path(os.environ["LOCALAPPDATA"]) / "Android/Sdk/ndk/28.2.13676358")
    a = p.parse_args()
    for name in [a.run_name, a.audit_name]:
        if not re.fullmatch(r"[A-Za-z0-9_-]+", name):
            p.error("Names must be single directory names")
    run = APPROVED / a.run_name
    result = json.loads((run / "results.json").read_text())
    pins = json.loads((HERE / "full-core-inputs.json").read_text())
    if not result["complete"] or result["source_commit"] != pins["commit"]:
        raise RuntimeError("Build did not complete at the pinned revision")
    jni_rel = "language-bindings/android/moonshine-jni/moonshine-jni.cpp"
    if sha(a.source_root / jni_rel) != pins["patched_files"][jni_rel]:
        raise RuntimeError("JNI source hash mismatch")
    expected = set(re.findall(r"Java_ai_moonshine_voice_JNI_\w+", (a.source_root / jni_rel).read_text()))
    tool_rel = "toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-readelf.exe"
    readelf = a.ndk / tool_rel
    tools = json.loads((HERE / "full-core-toolchain-inputs.json").read_text())
    if sha(readelf) != tools["ndk_extra"][tool_rel]:
        raise RuntimeError("ELF tool hash mismatch")
    out = run / a.audit_name
    out.mkdir()
    summary = {"scope": "REVIEW ONLY; ELF STRUCTURAL CHECKS; NOT ANDROID LOAD OR ADOPTION",
               "complete": False, "input_results_sha256": sha(run / "results.json"),
               "audit_script_sha256": sha(Path(__file__)), "readelf_sha256": sha(readelf), "abis": {}}
    machines = {"arm64-v8a": "AArch64", "armeabi-v7a": "ARM", "x86_64": "Advanced Micro Devices X86-64"}
    try:
        for abi, machine in machines.items():
            libraries = {}
            for name in ["libmoonshine.so", "libmoonshine-jni.so"]:
                paths = list((run / abi).rglob(name))
                if len(paths) != 1:
                    raise RuntimeError("Ambiguous/missing library: " + abi + "/" + name)
                path = paths[0]
                if sha(path) != result["outputs"].get(path.relative_to(run).as_posix()):
                    raise RuntimeError("Library changed since build: " + str(path))
                r = subprocess.run([str(readelf), "--wide", "--file-header", "--dynamic", "--dyn-syms", str(path)],
                                   capture_output=True, text=True, check=True)
                text = r.stdout + r.stderr
                (out / (abi + "-" + name + ".txt")).write_text(text)
                defined, undefined = set(), set()
                for line in text.splitlines():
                    parts = line.split()
                    if len(parts) >= 8 and parts[0].rstrip(":").isdigit() and parts[4] in ["GLOBAL", "WEAK"]:
                        (undefined if parts[6] == "UND" else defined).add(parts[7])
                actual_machine = re.search(r"Machine:\s+(.+)", text)[1]
                soname = re.findall(r"\(SONAME\)\s+Library soname: \[([^]]+)\]", text)
                if actual_machine != machine or soname != [name]:
                    raise RuntimeError("Unexpected ABI/SONAME: " + abi + "/" + name)
                libraries[name] = {"sha256": sha(path), "size": path.stat().st_size, "machine": actual_machine,
                                   "soname": soname[0], "needed": re.findall(r"\(NEEDED\)\s+Shared library: \[([^]]+)\]", text),
                                   "defined": defined, "undefined": undefined}
            jni, core = libraries["libmoonshine-jni.so"], libraries["libmoonshine.so"]
            actual = {x for x in jni["defined"] if x.startswith("Java_")}
            imports = {x for x in jni["undefined"] if x.startswith("moonshine_")}
            if actual != expected or not imports <= core["defined"]:
                raise RuntimeError("JNI export / core import mismatch: " + abi)
            if "libmoonshine.so" not in jni["needed"] or "libonnxruntime.so" not in core["needed"]:
                raise RuntimeError("Missing core/ORT dependency: " + abi)
            if any("libc++_shared" in x for lib in libraries.values() for x in lib["needed"]):
                raise RuntimeError("Unexpected shared libc++ dependency: " + abi)
            for lib in libraries.values():
                del lib["defined"]
                del lib["undefined"]
            summary["abis"][abi] = {"libraries": libraries, "jni_exports": len(actual), "jni_core_imports_resolved": len(imports)}
            print(abi, "PASS", len(actual), "JNI exports;", len(imports), "JNI core imports resolved")
        summary["complete"] = True
    finally:
        (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    main()
