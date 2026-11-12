import importlib.util
import json
import plistlib
import zipfile
from pathlib import Path
import pytest

script = Path(__file__).resolve().parents[1] / 'scripts/create-source.py'
spec = importlib.util.spec_from_file_location('source_builder', script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def test_prevents_missing_ipa(tmp_path):
    icon = tmp_path / 'icon.png'
    icon.write_bytes(b'x' * 1024)
    with pytest.raises(ValueError, match='IPA'):
        module.create_source(tmp_path / 'missing.ipa','https://apps.example.test', tmp_path/'source.json', icon)


def test_source_contains_real_size_and_valid_urls(tmp_path):
    ipa = tmp_path/'Klar-1.0.0.ipa'
    with zipfile.ZipFile(ipa, 'w', zipfile.ZIP_STORED) as archive:
        archive.writestr('Payload/Klar.app/Info.plist', plistlib.dumps({
            'CFBundleExecutable': 'Klar',
            'CFBundleIdentifier': 'at.klar.app',
            'CFBundleVersion': '1',
            'CFBundleShortVersionString': '1.0.0',
        }))
        archive.writestr('Payload/Klar.app/Klar', b'\xcf\xfa\xed\xfe' + b'x' * 4096)
    icon = tmp_path/'icon.png'
    icon.write_bytes(b'png' * 500)
    out = tmp_path/'www/source.json'
    source = module.create_source(ipa,'https://apps.example.test',out,icon)
    obj = json.loads(out.read_text())
    assert source == obj
    version = obj['apps'][0]['versions'][0]
    assert version['size'] == ipa.stat().st_size
    assert version['buildVersion'] == '1'
    assert version['downloadURL'].startswith('https://apps.example.test/releases/')
    assert (out.parent/'releases'/ipa.name).read_bytes() == ipa.read_bytes()
    assert (out.parent/'icon.png').read_bytes() == icon.read_bytes()
    assert len((out.parent/'releases'/(ipa.name+'.sha256')).read_text().split()[0]) == 64


def test_refuses_plain_http(tmp_path):
    with pytest.raises(ValueError, match='HTTPS'):
        module.create_source(tmp_path/'foo.ipa','http://example.test',tmp_path/'source.json',tmp_path/'foo.png')


def test_rejects_spoofed_ipa(tmp_path):
    ipa = tmp_path / 'bad.ipa'
    ipa.write_bytes(b'PK' + b'x' * 4096)
    icon = tmp_path / 'icon.png'
    icon.write_bytes(b'x' * 1024)
    with pytest.raises(ValueError, match='Ungültige IPA'):
        module.create_source(ipa, 'https://apps.example.test', tmp_path/'source.json', icon)
