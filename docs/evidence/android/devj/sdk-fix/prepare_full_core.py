"""Offline review-only source preparation; never extracts the test model stub.

Acquire the archive/tree URLs in full-core-inputs.json separately. Verifies their
SHA-256, selected files' Git blob IDs, existing source pins, and Android ORT from
the original pinned AAR (not the original Moonshine core). No network or adoption.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile
import zipfile

HERE = Path(__file__).resolve().parent
PATCHES = ["0001-streaming-jni-lifetime.patch",
           "0002-checked-java-and-explicit-update.patch",
           "0003-required-jni-path-safety.patch", "0004-per-stream-vad-state.patch"]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def checked(path, expected):
    data = path.read_bytes()
    if sha(data) != expected:
        raise RuntimeError("Hash mismatch: " + str(path))
    return data


def selected(rel):
    if rel.startswith("core/third-party/onnxruntime/lib/") and not any(
            rel.startswith("core/third-party/onnxruntime/lib/" + platform + "/")
            for platform in ["android", "windows"]):
        return False
    return (rel.startswith("core/") or rel.startswith("language-bindings/android/")
            or rel in ["LICENSE", ".gitattributes", "test-assets/beckett.wav",
                       "test-assets/two_cities_16k.wav"])


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--archive", type=Path, required=True)
    p.add_argument("--tree", type=Path, required=True)
    p.add_argument("--aar", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True, help="Must not exist")
    a = p.parse_args()
    pins = json.loads((HERE / "full-core-inputs.json").read_text())
    original = json.loads((HERE / "inputs.json").read_text())
    core = json.loads((HERE / "core-inputs.json").read_text())
    if not pins["commit"] == original["commit"] == core["commit"]:
        raise RuntimeError("Source revision pins disagree")
    checked(a.archive, pins["archive"]["sha256"])
    tree = json.loads(checked(a.tree, pins["tree"]["sha256"]))
    if tree["sha"] != pins["commit"] or tree["truncated"]:
        raise RuntimeError("Unexpected or truncated Git tree")
    checked(a.aar, original["artifacts"]["moonshine-voice-0.1.5.aar"])
    expected = {x["path"]: x for x in tree["tree"] if x["type"] == "blob" and selected(x["path"])}
    pointers = json.loads((HERE / "full-core-lfs-pointers.json").read_text())
    a.output.mkdir()  # Refuse to overwrite user inputs or earlier evidence.
    result = {"scope": "REVIEW ONLY; FULL PINNED SOURCE; NO ADOPTION", "commit": pins["commit"],
              "archive_sha256": pins["archive"]["sha256"], "files": {}, "patches": {}, "commands": []}
    try:
        with tarfile.open(a.archive, "r:gz") as archive:
            for member in archive:
                parts = PurePosixPath(member.name).parts
                if not parts or any(x in ["..", "."] for x in parts):
                    raise RuntimeError("Unsafe archive member")
                rel = "/".join(parts[1:])
                if rel not in expected:
                    continue
                if not member.isfile():
                    raise RuntimeError("Selected input is not a regular file: " + rel)
                data = archive.extractfile(member).read()
                blob = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
                if blob != expected[rel]["sha"]:
                    pointer = pointers.get(rel, "").encode()
                    pointer_blob = hashlib.sha1(b"blob " + str(len(pointer)).encode() + b"\0" + pointer).hexdigest()
                    oid = re.search(rb"^oid sha256:([a-f0-9]{64})$", pointer, re.M)
                    size = re.search(rb"^size ([0-9]+)$", pointer, re.M)
                    if (pointer_blob != expected[rel]["sha"] or not oid or not size
                            or sha(data) != oid[1].decode() or len(data) != int(size[1])):
                        raise RuntimeError("Git blob / LFS content mismatch: " + rel)
                    blob = pointer_blob
                target = a.output / rel
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
                result["files"][rel] = {"git_blob": blob, "sha256": sha(data), "size": len(data)}
        if result["files"].keys() != expected.keys():
            raise RuntimeError("Archive is missing selected inputs")
        for rel, h in {**original["files"], **core["files"]}.items():
            checked(a.output / rel, h)
        with zipfile.ZipFile(a.aar) as aar:
            for abi, entry in pins["android_ort"].items():
                rel = "core/third-party/onnxruntime/lib/android/" + entry["directory"] + "/libonnxruntime.so"
                pointer = pointers[rel]
                if not re.search(r"^oid sha256:" + entry["sha256"] + r"$", pointer, re.M):
                    raise RuntimeError("ORT LFS oid mismatch: " + abi)
                data = aar.read("jni/" + abi + "/libonnxruntime.so")
                if len(data) != entry["size"] or sha(data) != entry["sha256"]:
                    raise RuntimeError("ORT bytes mismatch: " + abi)
                (a.output / rel).write_bytes(data)
                result["files"][rel].update(sha256=sha(data), size=len(data), resolved_from="pinned original AAR")
        model = a.output / "core/silero-vad-model-data.h"
        if model.stat().st_size < 1000000:
            raise RuntimeError("Embedded model is not the real upstream input")
        for name in PATCHES:
            patch = HERE / name
            result["patches"][name] = sha(patch.read_bytes())
            for args in [["git", "apply", "--check", str(patch)], ["git", "apply", str(patch)]]:
                r = subprocess.run(args, cwd=a.output, capture_output=True, text=True)
                result["commands"].append({"argv": args, "exit": r.returncode, "output": r.stdout + r.stderr})
                if r.returncode:
                    raise RuntimeError(r.stdout + r.stderr)
        result["patched_files"] = {rel: sha((a.output / rel).read_bytes())
                                   for rel in expected if sha((a.output / rel).read_bytes()) != result["files"][rel]["sha256"]}
        manifest_hash = sha(json.dumps(result["files"], sort_keys=True, separators=(",", ":")).encode())
        if manifest_hash != pins["prepared_files_manifest_sha256"] or result["patched_files"] != pins["patched_files"]:
            raise RuntimeError("Prepared scope differs from the reviewed file manifest")
        result["complete"] = True
        print("Verified", len(expected), "Git blobs and existing pins; resolved three unchanged ORT libraries; applied patches 0001-0004")
        print("Real embedded Silero header:", model.stat().st_size, "bytes; SHA-256", sha(model.read_bytes()))
    finally:
        (a.output / "preparation.json").write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
