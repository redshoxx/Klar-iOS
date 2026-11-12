#!/usr/bin/env python3
"""Mirror verified Klar GitHub release IPAs into the existing SideStore VPS source.

No credentials needed for the PUBLIC repository. Run via a dedicated, unprivileged
systemd timer. Does not touch the backend or its PostgreSQL database.
"""
from __future__ import annotations
import hashlib
import json
import os
import plistlib
import re
import sys
import tempfile
import urllib.request
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit

API_URL = 'https://api.github.com/repos/redshoxx/Klar-iOS/releases?per_page=20'
ICON_URL = 'https://raw.githubusercontent.com/redshoxx/Klar-iOS/main/ios/Klar/Assets.xcassets/AppIcon.appiconset/AppIcon.png'
BASE_URL = 'https://apps.152.53.206.242.sslip.io'
WEB_ROOT = Path('/opt/klar-app/deploy/web')
IPA_PATTERN = re.compile(r'^Klar-(\d+\.\d+\.\d+)-build([1-9]\d*)\.ipa$')
HASH_PATTERN = re.compile(r'^([a-fA-F0-9]{64})\s+\*?([^\s]+)$')
MAX_IPA_BYTES = 160 * 1024 * 1024
HEADERS = {'User-Agent': 'Klar-iOS-VPS-Release-Sync/1.0', 'Accept': 'application/vnd.github+json'}


def fetch_bytes(url: str, *, max_bytes: int) -> bytes:
    if urlsplit(url).scheme != 'https':
        raise ValueError('Only HTTPS downloads are permitted')
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=40) as response:
        data = response.read(max_bytes + 1)
        if len(data) > max_bytes:
            raise ValueError('Downloaded file exceeds limit')
        return data


def select_release(releases: list[dict]) -> tuple[dict, dict, dict, str, str] | None:
    # GitHub returns newest releases first, excluding drafts.
    for release in releases:
        if release.get('draft'):
            continue
        assets = release.get('assets') or []
        for asset in assets:
            name = asset.get('name', '')
            match = IPA_PATTERN.fullmatch(name)
            if not match:
                continue
            sha = next((x for x in assets if x.get('name') == name + '.sha256'), None)
            if sha and asset.get('state') == 'uploaded' and sha.get('state') == 'uploaded':
                return release, asset, sha, match.group(1), match.group(2)
    return None


def validate_ipa(data: bytes, *, version: str, build: str) -> None:
    from io import BytesIO
    try:
        with zipfile.ZipFile(BytesIO(data)) as archive:
            plist = plistlib.loads(archive.read('Payload/Klar.app/Info.plist'))
            executable = archive.read('Payload/Klar.app/' + plist['CFBundleExecutable'])
            if executable[:4] not in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
                raise ValueError('Missing Mach-O executable')
            if plist.get('CFBundleIdentifier') != 'at.klar.app':
                raise ValueError('Unexpected bundle identifier')
            if plist.get('CFBundleShortVersionString') != version or plist.get('CFBundleVersion') != build:
                raise ValueError('IPA version or build mismatch')
    except (KeyError, zipfile.BadZipFile, plistlib.InvalidFileException) as exc:
        raise ValueError('Invalid IPA: missing signed app structure') from exc


def make_source(old: dict, *, version: str, build: str, name: str, size: int, published_at: str) -> dict:
    previous_apps = old.get('apps') or []
    older = (previous_apps[0].get('versions') or []) if previous_apps else []
    published = published_at[:10] if re.fullmatch(r'\d{4}-\d{2}-\d{2}.*', published_at) else datetime.now(timezone.utc).date().isoformat()
    latest = {
        'version': version, 'buildVersion': build, 'date': published,
        'localizedDescription': f'Automatischer GitHub-Build {build}',
        'downloadURL': BASE_URL + '/releases/' + name,
        'size': size, 'minOSVersion': '17.0',
    }
    remaining = [x for x in older if (x.get('version'), x.get('buildVersion')) != (version, build)]
    app = {
        'name': 'Klar.', 'bundleIdentifier': 'at.klar.app',
        'developerName': 'Private Distribution',
        'subtitle': 'Aufgaben, Finanzen und Einkaufslisten',
        'localizedDescription': 'Aufgaben, Finanzen, Fixkosten, Abos und Einkaufslisten mit VPS-Synchronisation.',
        'iconURL': BASE_URL + '/icon.png', 'tintColor': '#3F7850',
        'versions': [latest] + remaining[:9],
    }
    return {
        'name': old.get('name', 'Klar. – Private App Source'),
        'identifier': 'at.klar.sidestore',
        'sourceURL': BASE_URL + '/source.json',
        'apps': [app], 'news': [],
    }


def main() -> int:
    WEB_ROOT.mkdir(parents=True, exist_ok=True)
    release_bytes = fetch_bytes(API_URL, max_bytes=2 * 1024 * 1024)
    releases = json.loads(release_bytes)
    if not isinstance(releases, list):
        raise ValueError('GitHub did not return a releases list')
    selected = select_release(releases)
    if selected is None:
        print('No published GitHub IPA release yet; source unchanged.')
        return 0
    release, asset, checksum_asset, version, build = selected
    name = asset['name']
    if not str(asset.get('browser_download_url', '')).startswith('https://github.com/redshoxx/Klar-iOS/releases/download/'):
        raise ValueError('Invalid GitHub release IPA URL')
    if not str(checksum_asset.get('browser_download_url', '')).startswith('https://github.com/redshoxx/Klar-iOS/releases/download/'):
        raise ValueError('Invalid GitHub checksum URL')
    source_path = WEB_ROOT / 'source.json'
    old = json.loads(source_path.read_text(encoding='utf-8')) if source_path.exists() else {}
    existing = (old.get('apps') or [])
    if existing and existing[0].get('versions') and (existing[0]['versions'][0].get('version'),existing[0]['versions'][0].get('buildVersion')) == (version, build) and (WEB_ROOT / 'releases' / name).exists():
        print(f'Already up-to-date: {version} ({build})')
        return 0
    checksum = fetch_bytes(checksum_asset['browser_download_url'], max_bytes=1024).decode('utf-8').strip()
    match = HASH_PATTERN.fullmatch(checksum)
    if match is None or match.group(2) != name:
        raise ValueError('Malformed release sha256 file')
    payload = fetch_bytes(asset['browser_download_url'], max_bytes=MAX_IPA_BYTES)
    if hashlib.sha256(payload).hexdigest().lower() != match.group(1).lower():
        raise ValueError('Release IPA SHA-256 does not match')
    validate_ipa(payload, version=version, build=build)
    release_dir = WEB_ROOT / 'releases'
    release_dir.mkdir(parents=True, exist_ok=True)
    if not (WEB_ROOT / 'icon.png').exists():
        icon = fetch_bytes(ICON_URL, max_bytes=3_000_000)
        if not icon.startswith(b'\x89PNG\r\n\x1a\n'):
            raise ValueError('Icon is not a PNG')
        atomic_write(WEB_ROOT / 'icon.png', icon)
    atomic_write(release_dir / name, payload)
    atomic_write(release_dir / (name + '.sha256'), (checksum + '\n').encode('ascii'))
    updated = make_source(old, version=version, build=build, name=name, size=len(payload), published_at=release.get('published_at') or '')
    # Publish metadata last so clients never see a reference to an incomplete IPA.
    atomic_write(source_path, (json.dumps(updated, ensure_ascii=False, indent=2) + '\n').encode('utf-8'))
    print(f'Published Klar {version} ({build}) to {BASE_URL}/source.json; {len(payload)} bytes')
    return 0


def atomic_write(path: Path, content: bytes) -> None:
    with tempfile.NamedTemporaryFile(prefix='.klar-', dir=path.parent, delete=False) as f:
        staging = Path(f.name)
        try:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        except Exception:
            staging.unlink(missing_ok=True)
            raise
    try:
        os.replace(staging, path)
    except Exception:
        staging.unlink(missing_ok=True)
        raise


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as exc:
        print(f'SideStore release sync failed; prior source retained: {exc}', file=sys.stderr)
        sys.exit(1)
