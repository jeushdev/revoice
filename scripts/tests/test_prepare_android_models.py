import base64
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
import urllib.error
import urllib.request
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'prepare_android_models.py'
SPEC = importlib.util.spec_from_file_location('prepare_models', SCRIPT)
models = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(models)


class ModelPreparationTests(unittest.TestCase):
    def entry(self, data=b'123456789'):
        return {
            'path': 'models/stt/test.ort',
            'bytes': len(data),
            'sha256': hashlib.sha256(data).hexdigest(),
            'crc32c': base64.b64encode(bytes.fromhex('e3069283')).decode(),
            'url': 'https://example.invalid/test.ort',
        }

    def test_crc32c_known_vector(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'test'
            path.write_bytes(b'123456789')
            self.assertEqual(models.checksums(path, True)['crc32c'], '4waSgw==')
            self.assertEqual(models.verify_file(path, self.entry())['sha256'],
                             hashlib.sha256(b'123456789').hexdigest())

    def test_missing_size_crc_and_sha_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'test'
            with self.assertRaisesRegex(ValueError, 'Missing'):
                models.verify_file(path, self.entry())
            path.write_bytes(b'short')
            with self.assertRaisesRegex(ValueError, 'size'):
                models.verify_file(path, self.entry())
            path.write_bytes(b'abcdefghi')
            with self.assertRaisesRegex(ValueError, 'crc32c'):
                models.verify_file(path, self.entry())
            entry = self.entry()
            del entry['crc32c']
            with self.assertRaisesRegex(ValueError, 'sha256'):
                models.verify_file(path, entry)

    def test_import_atomic_reuse_and_original_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'source'
            target = Path(directory) / 'nested/model'
            source.write_bytes(b'123456789')
            with patch.object(models.urllib.request, 'urlopen', side_effect=AssertionError):
                models.prepare_file(target, self.entry(), source)
                models.prepare_file(target, self.entry())
            self.assertEqual(source.read_bytes(), b'123456789')
            self.assertEqual(target.read_bytes(), source.read_bytes())
            self.assertEqual(list(target.parent.glob('*.part')), [])

    def test_existing_corrupt_file_not_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'model'
            target.write_bytes(b'user-file')
            with self.assertRaises(ValueError):
                models.prepare_file(target, self.entry())
            self.assertEqual(target.read_bytes(), b'user-file')

    def test_failed_download_never_published(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'model'
            with patch.object(models.urllib.request, 'urlopen', side_effect=OSError('offline')):
                with self.assertRaises(OSError):
                    models.prepare_file(target, self.entry())
            self.assertFalse(target.exists())
            self.assertEqual(list(target.parent.glob('*.part')), [])

    def test_publisher_manifest_matches_pins(self):
        lock = json.loads(models.LOCK_PATH.read_text(encoding='utf-8'))
        models.validate_publisher_metadata(lock)
        self.assertEqual(len(lock['files']), 11)
        self.assertEqual(sum(entry['bytes'] for entry in lock['files']), 638220939)

    def test_partial_manifest_does_not_claim_full_readiness(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            entry = self.entry()
            lock = {'files': [entry], 'moonshine': {}, 'gemma': {}}
            models.write_manifest(root, lock, {}, False)
            manifest = json.loads((root / 'model-manifest.json').read_text())
            self.assertFalse(manifest['complete'])
            self.assertFalse(manifest['files'][0]['verified'])
            self.assertEqual(manifest['verifiedBytes'], 0)

    def test_token_from_environment(self):
        with patch.dict(models.os.environ, {'HF_TOKEN': 'hf_test123'}):
            self.assertEqual(models.hugging_face_token(), 'hf_test123')

    def test_hidden_prompt_does_not_echo_token(self):
        output = io.StringIO()
        with patch.object(models.sys.stdin, 'isatty', return_value=True), \
                patch.object(models.getpass, 'getpass', return_value='hf_test123'), \
                patch.object(models.sys, 'stdout', output):
            self.assertEqual(models.hugging_face_token(prompt=True), 'hf_test123')
        self.assertNotIn('hf_test123', output.getvalue())

    def test_hidden_prompt_refuses_noninteractive_input(self):
        with patch.object(models.sys.stdin, 'isatty', return_value=False), \
                patch.object(models.getpass, 'getpass', side_effect=AssertionError):
            with self.assertRaisesRegex(ValueError, 'interactive terminal'):
                models.hugging_face_token(prompt=True)

    def test_token_cache_read_only(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'token'
            path.write_text('hf_cached123\n', encoding='utf-8')
            with patch.dict(models.os.environ, {'HF_TOKEN': '', 'HF_TOKEN_PATH': str(path)}):
                self.assertEqual(models.hugging_face_token(), 'hf_cached123')
            self.assertEqual(path.read_text(), 'hf_cached123\n')

    def test_token_never_sent_to_other_origin(self):
        for url in ('https://example.invalid/file', 'http://huggingface.co/file'):
            with self.subTest(url=url), \
                    patch.object(models.urllib.request, 'build_opener', side_effect=AssertionError):
                with self.assertRaisesRegex(ValueError, 'Credentials may only'):
                    models.open_download(urllib.request.Request(url), 'hf_test123')

    def test_redirect_strips_auth_to_cdn_but_preserves_same_origin(self):
        request = urllib.request.Request('https://huggingface.co/model', headers={
            'Authorization': 'Bearer hf_test123'
        })
        handler = models.ModelRedirectHandler()
        cdn_request = handler.redirect_request(
            request, None, 302, 'Found', {}, 'https://cdn.example.invalid/model'
        )
        self.assertIsNone(cdn_request.get_header('Authorization'))
        hf_request = handler.redirect_request(
            request, None, 302, 'Found', {}, 'https://huggingface.co/resolve/model'
        )
        self.assertEqual(hf_request.get_header('Authorization'), 'Bearer hf_test123')
        with self.assertRaisesRegex(ValueError, 'non-HTTPS'):
            handler.redirect_request(request, None, 302, 'Found', {}, 'http://cdn.example/model')

    def test_invalid_token_error_does_not_include_secret(self):
        with patch.dict(models.os.environ, {'HF_TOKEN': 'secret\ninvalid'}):
            with self.assertRaises(ValueError) as error:
                models.hugging_face_token()
            self.assertNotIn('secret', str(error.exception))

    def test_gated_access_error_reports_account_and_token_permissions(self):
        error = urllib.error.HTTPError(
            'https://huggingface.co/model', 403, 'Forbidden',
            {'X-Error-Code': 'GatedRepo'}, None
        )
        message = models.http_error_message(error)
        error.close()
        self.assertIn('huggingface.co', message)
        self.assertIn('gated repository access denied', message)
        self.assertIn('fine-grained token', message)

    def test_cdn_error_does_not_log_signed_url_or_blame_token(self):
        error = urllib.error.HTTPError(
            'https://cdn.example.invalid/model?signature=secret', 403,
            'Forbidden', {}, None
        )
        message = models.http_error_message(error)
        error.close()
        self.assertIn('cdn.example.invalid', message)
        self.assertNotIn('secret', message)
        self.assertNotIn('signature', message)
        self.assertIn('does not prove the token is invalid', message)


if __name__ == '__main__':
    unittest.main()
