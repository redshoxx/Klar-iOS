import importlib.util
import io
import plistlib
import zipfile
from pathlib import Path
import pytest

script = Path(__file__).resolve().parents[1] / 'scripts/sync_github_release.py'
spec = importlib.util.spec_from_file_location('release_sync', script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def test_selects_latest_with_complete_pair():
    releases = [
        {'assets':[{'name':'Klar-1.0.0-build8.ipa','state':'uploaded'}]},
        {'assets':[{'name':'Klar-1.0.0-build7.ipa','state':'uploaded'},
                   {'name':'Klar-1.0.0-build7.ipa.sha256','state':'uploaded'}]}
    ]
    selected = module.select_release(releases)
    assert selected[3:] == ('1.0.0','7')


def test_source_keeps_history_and_build_number():
    previous = module.make_source({}, version='1.0.0',build='3',name='Klar-1.0.0-build3.ipa',size=5000,published_at='2026-11-12T15:00:00Z')
    latest = module.make_source(previous, version='1.0.0',build='4',name='Klar-1.0.0-build4.ipa',size=5100,published_at='2026-11-13T16:00:00Z')
    versions=latest['apps'][0]['versions']
    assert [x['buildVersion'] for x in versions] == ['4','3']
    assert versions[0]['downloadURL'].endswith('Klar-1.0.0-build4.ipa')


def test_validates_real_plist_and_mach_o():
    obj=io.BytesIO()
    with zipfile.ZipFile(obj,'w') as z:
        z.writestr('Payload/Klar.app/Info.plist',plistlib.dumps({'CFBundleIdentifier':'at.klar.app','CFBundleVersion':'12','CFBundleShortVersionString':'1.0.0','CFBundleExecutable':'Klar'}))
        z.writestr('Payload/Klar.app/Klar',b'\xcf\xfa\xed\xfe' + b'A'*4096)
    module.validate_ipa(obj.getvalue(),version='1.0.0',build='12')
    with pytest.raises(ValueError, match='version'):
        module.validate_ipa(obj.getvalue(),version='1.0.0',build='13')
