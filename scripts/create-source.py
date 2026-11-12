#!/usr/bin/env python3
"""Build AltStore/SideStore source.json only for an existing, nonempty IPA."""
import argparse
import hashlib
import json
import plistlib
import zipfile
from datetime import date
from pathlib import Path
from urllib.parse import urlsplit


def create_source(ipa: Path, base_url: str, output: Path, icon: Path,
                  version: str = '1.0.0', build: str = '1') -> dict:
    parts = urlsplit(base_url)
    if parts.scheme != 'https' or not parts.netloc or parts.username or parts.password or parts.query or parts.fragment:
        raise ValueError('Eine gültige HTTPS-Basisadresse ohne Credentials oder Query ist erforderlich.')
    if not ipa.is_file() or ipa.stat().st_size < 1024:
        raise ValueError('Eine tatsächlich gebaute IPA-Datei mit mindestens 1024 Bytes ist erforderlich.')
    if ipa.suffix.lower() != '.ipa':
        raise ValueError('Die Installationsdatei muss auf .ipa enden.')
    try:
        with zipfile.ZipFile(ipa) as archive:
            plist = plistlib.loads(archive.read('Payload/Klar.app/Info.plist'))
            executable_name = plist['CFBundleExecutable']
            executable = archive.read(f'Payload/Klar.app/{executable_name}')
            if executable[:4] not in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf',
                                      b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
                raise ValueError('Das App-Binary ist nicht im Mach-O-Format.')
            if plist['CFBundleIdentifier'] != 'at.klar.app':
                raise ValueError('Bundle-ID der IPA stimmt nicht mit der Source überein.')
            if plist['CFBundleShortVersionString'] != version or plist['CFBundleVersion'] != build:
                raise ValueError('IPA-Version und Source-Version stimmen nicht überein.')
    except (zipfile.BadZipFile, KeyError, plistlib.InvalidFileException) as exc:
        raise ValueError('Ungültige IPA: Klar.app/Info.plist oder Binary fehlen.') from exc
    if not icon.is_file() or icon.stat().st_size < 100:
        raise ValueError('App-Icon fehlt oder ist ungültig.')
    base = base_url.rstrip('/')
    metadata = {
        'name': 'Klar. – Private App Source',
        'identifier': 'at.klar.sidestore',
        'sourceURL': base + '/source.json',
        'apps': [{
            'name': 'Klar.', 'bundleIdentifier': 'at.klar.app',
            'developerName': 'Private Distribution',
            'subtitle': 'Aufgaben, Finanzen und Einkaufslisten',
            'localizedDescription': 'Aufgaben, Finanzen, Fixkosten, Abos und Einkaufslisten. Native iPhone-App mit VPS-Synchronisation.',
            'iconURL': base + '/icon.png', 'tintColor': '#3F7850',
            'versions': [{
                'version': version,
                'buildVersion': str(build),
                'date': date.today().isoformat(),
                'localizedDescription': 'Erstveröffentlichung',
                'downloadURL': base + '/releases/' + ipa.name,
                'size': ipa.stat().st_size,
                'minOSVersion': '17.0',
            }]
        }], 'news': []
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (output.parent / 'icon.png').write_bytes(icon.read_bytes())
    (output.parent / 'releases').mkdir(parents=True, exist_ok=True)
    destination = output.parent / 'releases' / ipa.name
    destination.write_bytes(ipa.read_bytes())
    (output.parent / 'releases' / (ipa.name + '.sha256')).write_text(
        hashlib.sha256(ipa.read_bytes()).hexdigest() + '  ' + ipa.name + '\n', encoding='ascii')
    return metadata


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ipa', type=Path, required=True)
    parser.add_argument('--base-url', required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--icon', type=Path, required=True)
    parser.add_argument('--version', default='1.0.0')
    parser.add_argument('--build', default='1')
    args = parser.parse_args()
    create_source(args.ipa, args.base_url, args.out, args.icon, args.version, args.build)
    print('Source erstellt:', args.out)
