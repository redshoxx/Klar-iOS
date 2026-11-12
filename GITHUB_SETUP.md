# Klar. — automatische IPA über GitHub Actions

**Ziel:** Jede Änderung an `main` bekommt einen macOS/Xcode-Build als GitHub-Actions-Artefakt. Ein neues Versions-Tag `vX.Y.Z` erstellt zusätzlich ein GitHub-Release mit der unsigned IPA.

## Einmalige Aktivierung

1. In GitHub **ein neues privates Repository `Klar-iOS`** erstellen: https://github.com/new. Keine automatische README oder `.gitignore` hinzufügen (beide liegen bereits im Projekt).
2. Dieses Projekt (einschließlich des versteckten Ordners `.github/workflows`) in das Repository hochladen.
3. Unter **Actions → Klar iOS – IPA** den ersten Build ansehen. Ein erfolgreicher Build erzeugt das Artefakt `Klar-<version>-build<nummer>`, das die `.ipa` enthält.
4. Für eine neue veröffentlichte Version die `MARKETING_VERSION` in `ios/project.yml` erhöhen und ein gleichlautendes Git-Tag pushen, z. B. `v1.0.1`.
5. GitHub erstellt dann automatisch das Release mit IPA und SHA-256-Prüfsumme.

Wenn der vollständige Projektordner auf dem PC vorliegt, kann er alternativ per Git übertragen werden:

```powershell
cd .\klar-suite
git init
git branch -M main
git add .
git commit -m "Klar iOS: initialer GitHub Actions IPA-Build"
git remote add origin https://github.com/DEIN-ACCOUNT/Klar-iOS.git
git push -u origin main
```

Die URL nach Erstellung mit der tatsächlichen Repository-Adresse ersetzen. Die Befehle verändern keine bestehenden Repositories.

## Wiederkehrender Build

- **Push auf `main`:** Tests, SwiftUI-Release-Build auf `macos-15`, IPA-ZIP-Prüfung, GitHub-Artefakt (30 Tage Aufbewahrung).
- **Pull Request:** Prüfbuild; nur nach erfolgreichem Test.
- **Tag `v1.0.1` o. Ä.:** derselbe Build plus GitHub-Release mit `Klar-1.0.1-build<nummer>.ipa`.
- **Manuell:** Actions → Klar iOS – IPA → Run workflow.

## SideStore und eigener VPS

Die erzeugte IPA ist absichtlich **nicht mit einem privaten Apple-Zertifikat signiert**. SideStore übernimmt die Signierung auf dem iPhone. Ein GitHub-Release aus einem **privaten** Repository ist ohne Authentifizierung nicht öffentlich herunterladbar. Für die eigentliche SideStore-Source muss die getestete IPA über die vorhandene VPS-HTTPS-Adresse `apps.152.53.206.242.sslip.io` veröffentlicht und `source.json` aktualisiert werden. Das VPS-Publishing ist noch **nicht** an GitHub Actions gekoppelt; dazu ist ein dedizierter Deployment-Schlüssel bzw. ein begrenzter Veröffentlichungsdienst erforderlich.

**Keinen VPS-Root-SSH-Key und keine Finanzdaten als GitHub-Repository-Dateien hochladen.** In CI sind nur Quellcode und Konfigurationsbeispiele enthalten. Auch ein grüner GitHub-Build ersetzt keinen Start- und Funktionstest auf dem echten iPhone 12.
