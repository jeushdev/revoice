"""Development-only asset preparation. Python 3.10+, standard library only.

Downloads pinned Moonshine assets and optionally authenticated Gemma assets,
or imports an authorized developer's local Gemma file. No runtime downloader.
"""

import argparse
import base64
import getpass
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
LOCK_PATH = ROOT / 'models/android-models.lock.json'
METADATA_PATH = ROOT / 'models/provenance/moonshine-model-file-metadata.generated.cpp'
CHUNK_SIZE = 1024 * 1024
REQUIRED_PATHS = {
    'models/stt/adapter.ort', 'models/stt/cross_kv.ort', 'models/stt/decoder_kv.ort',
    'models/stt/encoder.ort', 'models/stt/frontend.model.ort', 'models/stt/frontend.weights.ort',
    'models/stt/streaming_config.json', 'models/stt/tokenizer.bin',
    'models/diarization/segmentation.ort', 'models/diarization/embedding.ort',
    'models/llm/gemma3-1b-it-int4.litertlm',
}


def crc_table():
    table = []
    for number in range(256):
        for _ in range(8):
            number = (number >> 1) ^ (0x82F63B78 if number & 1 else 0)
        table.append(number)
    return table


CRC_TABLE = crc_table()


class ModelRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Never forward a Hugging Face bearer token to a different host."""

    def redirect_request(self, request, response, code, message, headers, new_url):
        destination = urllib.parse.urlsplit(new_url)
        if destination.scheme != 'https':
            raise ValueError('Refusing a non-HTTPS model download redirect')
        redirected = super().redirect_request(
            request, response, code, message, headers, new_url
        )
        if redirected is not None and destination.netloc != 'huggingface.co':
            redirected.remove_header('Authorization')
        return redirected


def hugging_face_token(prompt=False):
    if prompt:
        if not sys.stdin.isatty():
            raise ValueError('The hidden token prompt requires a local interactive terminal')
        token = getpass.getpass('Hugging Face read token (hidden, not saved): ')
    else:
        token = os.environ.get('HF_TOKEN', '')
        if not token:
            cache_home = Path(os.environ.get('XDG_CACHE_HOME', Path.home() / '.cache'))
            hf_home = Path(os.environ.get('HF_HOME', cache_home / 'huggingface'))
            token_path = Path(os.environ.get('HF_TOKEN_PATH', hf_home / 'token'))
            if token_path.is_file():
                token = token_path.read_text(encoding='utf-8')
    token = token.strip()
    if not token:
        raise ValueError('No Hugging Face credentials available. Use --prompt-token '
                         'in a local terminal or configure HF_TOKEN locally.')
    if not re.fullmatch(r'hf_[A-Za-z0-9]+', token):
        raise ValueError('Invalid Hugging Face token format; token was not logged or saved')
    return token


def open_download(request, token=None):
    if token is None:
        return urllib.request.urlopen(request, timeout=120)
    origin = urllib.parse.urlsplit(request.full_url)
    if origin.scheme != 'https' or origin.netloc != 'huggingface.co':
        raise ValueError('Credentials may only be sent to https://huggingface.co')
    request.add_header('Authorization', f'Bearer {token}')
    return urllib.request.build_opener(ModelRedirectHandler()).open(request, timeout=120)


def http_error_message(error):
    # Do not log raw response bodies, URLs, or signed CDN query parameters.
    host = urllib.parse.urlsplit(error.url).hostname or 'unknown host'
    message = f'Asset download failed: HTTP {error.code} from {host}.'
    if host == 'huggingface.co' and error.code in (401, 403):
        error_code = error.headers.get('X-Error-Code', '') if error.headers else ''
        if error_code == 'GatedRepo':
            message += ' Hugging Face reports gated repository access denied.'
        message += (' Confirm access to litert-community/Gemma3-1B-IT for the account '
                    'owning the token. Use a Read token, or enable public gated-repository '
                    'read access on a fine-grained token.')
    elif error.code == 403:
        message += (' The download server rejected the request. This alone does not '
                    'prove the token is invalid; a signed-link or network issue is possible.')
    else:
        message += ' Rerun to retry.'
    return message


def checksums(path, include_crc):
    sha = hashlib.sha256()
    crc = 0xFFFFFFFF
    with path.open('rb') as stream:
        while data := stream.read(CHUNK_SIZE):
            sha.update(data)
            if include_crc:
                for byte in data:
                    crc = CRC_TABLE[(crc ^ byte) & 0xFF] ^ (crc >> 8)
    result = {'sha256': sha.hexdigest()}
    if include_crc:
        result['crc32c'] = base64.b64encode(
            (crc ^ 0xFFFFFFFF).to_bytes(4, 'big')
        ).decode('ascii')
    return result


def verify_file(path, entry):
    if not path.is_file():
        raise ValueError(f'Missing required asset: {entry["path"]}')
    if path.stat().st_size != entry['bytes']:
        raise ValueError(f'Incorrect size: {entry["path"]}')
    actual = checksums(path, 'crc32c' in entry)
    for key in ('crc32c', 'sha256'):
        if key in entry and actual[key] != entry[key]:
            raise ValueError(f'{key} mismatch: {entry["path"]}')
    return actual


def validate_publisher_metadata(lock):
    """Check lock entries against the preserved canonical publisher manifest."""
    if (lock.get('schemaVersion') != 1 or
            lock.get('assetRoot') != 'android/app/src/main/assets/revise' or
            len(lock.get('files', [])) != len(REQUIRED_PATHS) or
            {entry.get('path') for entry in lock['files']} != REQUIRED_PATHS):
        raise ValueError('Invalid model lock inventory or asset root')
    for entry in lock['files']:
        if (type(entry.get('bytes')) is not int or entry['bytes'] <= 0 or
                not re.fullmatch(r'[0-9a-f]{64}', entry.get('sha256', ''))):
            raise ValueError(f'Invalid model size/hash: {entry["path"]}')
        group = entry['path'].split('/')[1]
        name = entry['path'].split('/')[-1]
        if group == 'llm':
            expected = ('https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/'
                        'a6306a4e292016480083b73b8dc6f3f939ae04c3/' + name)
        else:
            directory = 'tiny-streaming-en/quantized_26_08_21' if group == 'stt' else 'diarization-community1'
            expected = f'https://download.moonshine.ai/model/{directory}/{name}'
            if not re.fullmatch(r'[A-Za-z0-9+/]{6}==', entry.get('crc32c', '')):
                raise ValueError(f'Invalid publisher CRC32C: {entry["path"]}')
        if entry.get('url') != expected:
            raise ValueError(f'Unexpected model source: {entry["path"]}')
    source = METADATA_PATH.read_text(encoding='utf-8')
    # The C++ generator wraps long URLs into adjacent string literals.
    pattern = r'\{((?:"[^"\n]*"\s*)+),\s*(\d+),\s*"([^"]+)",\s*"crc32c"\}'
    metadata = {}
    for urls, size, crc in re.findall(pattern, source):
        url = ''.join(re.findall(r'"([^"]*)"', urls))
        metadata[url] = (int(size), crc)
    for entry in lock['files']:
        if 'crc32c' in entry:
            if metadata.get(entry['url']) != (entry['bytes'], entry['crc32c']):
                raise ValueError(f'Publisher metadata mismatch: {entry["path"]}')
    gemma_metadata = json.loads(
        (ROOT / 'models/provenance/gemma-metadata.json').read_text(encoding='utf-8')
    )
    if gemma_metadata['sha'] != lock['gemma']['revision']:
        raise ValueError('Gemma publisher revision mismatch')
    gemma_entry = next(item for item in lock['files'] if item['path'].startswith('models/llm/'))
    published = next(item for item in gemma_metadata['siblings']
                     if item['rfilename'] == Path(gemma_entry['path']).name)
    if (published['size'], published['lfs']['sha256']) != (
        gemma_entry['bytes'], gemma_entry['sha256']
    ):
        raise ValueError('Gemma publisher checksum/size mismatch')


def prepare_file(target, entry, source=None, token=None):
    if target.exists():
        # Never replace an existing corrupt/unknown file without the user deciding.
        actual = verify_file(target, entry)
        print(f'Verified existing {entry["path"]}', flush=True)
        return actual
    if source is not None:
        verify_file(source, entry)
    target.parent.mkdir(parents=True, exist_ok=True)
    if shutil.disk_usage(target.parent).free < entry['bytes'] + 64 * CHUNK_SIZE:
        raise ValueError(f'Insufficient disk space for {entry["path"]}')
    fd, temporary = tempfile.mkstemp(suffix='.part', dir=target.parent)
    temporary = Path(temporary)
    try:
        with os.fdopen(fd, 'wb') as output:
            if source is not None:
                with source.open('rb') as stream:
                    shutil.copyfileobj(stream, output, CHUNK_SIZE)
            else:
                print(f'Downloading {entry["path"]}', flush=True)
                request = urllib.request.Request(entry['url'], headers={
                    'User-Agent': 'ReVise-model-preparation/1'
                })
                with open_download(request, token) as response:
                    downloaded = 0
                    next_progress = 64 * CHUNK_SIZE
                    while chunk := response.read(CHUNK_SIZE):
                        downloaded += len(chunk)
                        if downloaded > entry['bytes']:
                            raise ValueError(f'Oversized download: {entry["path"]}')
                        output.write(chunk)
                        if downloaded >= next_progress:
                            print(f'Downloaded {downloaded / CHUNK_SIZE:.0f} / '
                                  f'{entry["bytes"] / CHUNK_SIZE:.0f} MiB', flush=True)
                            next_progress += 64 * CHUNK_SIZE
            output.flush()
            os.fsync(output.fileno())
        actual = verify_file(temporary, entry)
        # Hard-link publication is atomic and refuses to overwrite an existing file.
        os.link(temporary, target)
        print(f'Prepared {entry["path"]}', flush=True)
        return actual
    finally:
        temporary.unlink(missing_ok=True)


def runtime_manifest(lock):
    """One schema consumed by Kotlin, Gradle and the PowerShell verifier.

    The lock retains acquisition URLs. The app inventory never asks the runtime to
    fetch Gemma, and contains no per-machine readiness flags.
    """
    moonshine = lock['moonshine']
    gemma = lock['gemma']
    return {
        'schemaVersion': 1,
        'assetSetVersion': 'revise-android-v1',
        'speech': {
            'runtime': 'ai.moonshine:moonshine-voice:' + moonshine.get('sdkVersion', '0.1.5'),
            'revision': moonshine.get('sourceRevision'),
            'architecture': 'tiny-streaming-en',
            'assetRevision': 'quantized_26_08_21',
        },
        'crm': {
            'runtime': 'com.google.ai.edge.litertlm:litertlm-android:' + gemma.get('runtimeVersion', '0.18.0'),
            'repository': gemma.get('repository'),
            'revision': gemma.get('revision'),
        },
        'files': [{
            'group': entry['path'].split('/')[1],
            'path': entry['path'],
            'sizeBytes': entry['bytes'],
            'sha256': entry['sha256'],
            'crc32c': entry.get('crc32c'),
            'sourceUrl': None if entry['path'].startswith('models/llm/') else entry['url'],
        } for entry in lock['files']],
    }


def write_json_atomic(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(suffix='.part', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as output:
            json.dump(value, output, indent=2)
            output.write('\n')
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def write_manifest(asset_root, lock, results, complete, report_path=None):
    asset_root.mkdir(parents=True, exist_ok=True)
    write_json_atomic(asset_root / 'model-manifest.json', runtime_manifest(lock))
    # Local status is separate and ignored by Git; another developer's verified files
    # do not become available merely by pulling a committed manifest.
    report_path = report_path or ROOT / 'work/android-model-preparation-report.json'
    write_json_atomic(report_path, {
        'schemaVersion': 1,
        'complete': complete,
        'files': [{'path': entry['path'], 'verified': entry['path'] in results} for entry in lock['files']],
        'totalRequiredBytes': sum(entry['bytes'] for entry in lock['files']),
        'verifiedBytes': sum(entry['bytes'] for entry in lock['files'] if entry['path'] in results),
    })


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    gemma_source = parser.add_mutually_exclusive_group()
    gemma_source.add_argument('--gemma-file', type=Path)
    gemma_source.add_argument('--download-gemma', action='store_true')
    parser.add_argument('--prompt-token', action='store_true',
                        help='Read a token at a local hidden prompt; never save it')
    parser.add_argument('--accept-gemma-terms', action='store_true')
    parser.add_argument('--moonshine-only', action='store_true')
    parser.add_argument('--verify-only', action='store_true',
                        help='Offline packaging preflight; fails on missing/corrupt assets')
    args = parser.parse_args()
    if (args.gemma_file or args.download_gemma) and (args.moonshine_only or args.verify_only):
        parser.error('Gemma import/download cannot be used with --moonshine-only or --verify-only')
    if (args.gemma_file or args.download_gemma) and not args.accept_gemma_terms:
        parser.error('Gemma import/download requires --accept-gemma-terms after reviewing publisher terms')
    if args.prompt_token and not args.download_gemma:
        parser.error('--prompt-token requires --download-gemma')
    lock = json.loads(LOCK_PATH.read_text(encoding='utf-8'))
    validate_publisher_metadata(lock)
    asset_root = ROOT / lock['assetRoot']
    results = {}
    for entry in lock['files']:
        target = asset_root / entry['path']
        is_gemma = entry['path'].startswith('models/llm/')
        if is_gemma and args.moonshine_only:
            continue
        if args.verify_only:
            results[entry['path']] = verify_file(target, entry)
            print(f'Verified {entry["path"]}', flush=True)
        elif is_gemma:
            if args.gemma_file or target.exists():
                results[entry['path']] = prepare_file(target, entry, args.gemma_file)
            elif args.download_gemma:
                write_manifest(asset_root, lock, results, complete=False)
                token = hugging_face_token(prompt=args.prompt_token)
                try:
                    results[entry['path']] = prepare_file(target, entry, token=token)
                finally:
                    token = None
            else:
                write_manifest(asset_root, lock, results, complete=False)
                raise ValueError('Gemma is missing. Use --download-gemma --accept-gemma-terms '
                                 'with local credentials, or --gemma-file PATH --accept-gemma-terms.')
        else:
            results[entry['path']] = prepare_file(target, entry)
    complete = len(results) == len(lock['files'])
    if not args.verify_only:
        write_manifest(asset_root, lock, results, complete)
    total = sum(entry['bytes'] for entry in lock['files'] if entry['path'] in results)
    print(f'Verified {len(results)} files, {total:,} bytes. '
          f'All Android model assets ready: {complete}', flush=True)


if __name__ == '__main__':
    try:
        main()
    except urllib.error.HTTPError as error:
        print(http_error_message(error), file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError:
        print('Asset download failed: network error. Rerun to retry.', file=sys.stderr)
        sys.exit(1)
    except (KeyboardInterrupt, EOFError):
        print('Model preparation cancelled.', file=sys.stderr)
        sys.exit(130)
    except (OSError, ValueError, urllib.error.URLError) as error:
        print(f'Model preparation failed: {error}', file=sys.stderr)
        sys.exit(1)
