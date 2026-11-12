# Klar. — iPhone-App mit eigenem VPS

Stand: 2026-11-12 | Version 1.0.0 | iPhone 12 / iOS 17+

## Aufbau

- `ios/Klar/`: native SwiftUI-App, SwiftData und offline gespeicherte Aufgaben, Finanzbuchungen, Fixkosten, Einkaufslisten, Kalender und Einstellungen.
- `backend/`: FastAPI + PostgreSQL, Argon2-Passwörter, kurzlebige Access-Tokens, rotierende Refresh-Tokens, versionierte Synchronisation mit Konflikterkennung, mandantenbezogene Daten.
- `deploy/`: Docker Compose mit PostgreSQL und Caddy/TLS, API nur über Reverse Proxy.
- `source/`: eigene SideStore/AltStore-Source, vor Veröffentlichung muss die tatsächliche IPA eingesetzt werden.


## IPA automatisch über GitHub Actions (Standardweg für jedes Update)

Der Workflow `.github/workflows/ios-ipa.yml` wird bei jedem Push nach `main`, bei Pull Requests, bei jedem Tag `vX.Y.Z` und manuell ausgeführt. GitHub verwendet einen macOS-Runner mit Xcode und generiert aus dem SwiftUI-Code eine **unsigned IPA**, die SideStore auf dem Gerät signieren kann. Es wird **kein eigener Mac** benötigt.

- Entwicklungsbuild: In GitHub unter **Actions → Klar iOS – IPA → Run workflow** starten oder nach `main` pushen. Die fertige IPA unter **Artifacts** herunterladen.
- Neue Version veröffentlichen: Versionsnummer erhöhen und ein neues Tag setzen, z. B. `git tag v1.0.1 && git push origin v1.0.1`. GitHub baut die IPA und legt sie im passenden **Release** ab.
- Für SideStore muss die IPA anschließend über eine **öffentliche HTTPS-Adresse** erreichbar sein. Bei einem *privaten GitHub-Repository* sind GitHub-Releases nicht direkt als anonyme Downloadquelle für SideStore geeignet. Dafür ist der bereits eingerichtete VPS mit eigener Source zuständig. Die öffentliche Source erst aktualisieren, wenn die IPA auf dem VPS verfügbar und geprüft ist.
- GitHub Actions kann keine funktionale Geräteprüfung ersetzen. Nach dem ersten erfolgreichen macOS-Build folgt der Installationstest auf dem iPhone 12.

**Wichtig:** Die CI-Datei allein startet noch keine Builds, solange der Projektcode nicht in einem GitHub-Repository liegt. CI/CD bedeutet nicht automatisch, dass die App auf deinem iPhone installiert ist.

## Backend lokal testen

```sh
cd backend
pip install -r requirements-dev.txt
pytest -q
alembic upgrade head
uvicorn app.main:app --reload
```

## iOS-App bauen (macOS mit Xcode erforderlich)

```sh
brew install xcodegen
cd ios
xcodegen generate
xcodebuild -project Klar.xcodeproj -scheme Klar -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Für eine installierbare IPA aus dem Build erzeugt ein macOS-CI-Prozess `Payload/Klar.app` und verpackt das Verzeichnis als ZIP mit Endung `.ipa`. Diese IPA muss für SideStore korrekt vorbereitet sein und durch SideStore mit der Apple-ID signiert werden. Eine Build-Prüfung in macOS/Xcode und ein echter Geräte-Installationstest sind nötig, bevor die App als ausgeliefert gilt.

## Produktive Inbetriebnahme

1. DNS-Einträge `api.DOMAIN` und `apps.DOMAIN` auf den VPS richten.
2. `deploy/Caddyfile.example` in `deploy/Caddyfile` kopieren, Platzhalter durch verifizierte eigene Domains ersetzen.
3. `deploy/.env` mit einem langen, zufällig erzeugten `POSTGRES_PASSWORD` erstellen. Nicht in Git einchecken.
4. `docker compose -f deploy/docker-compose.yml up --build -d` im Projektverzeichnis ausführen.
5. API unter `https://api.DOMAIN/health` prüfen, Xcode-Build ausführen, IPA unter `deploy/web/releases/` veröffentlichen.
6. `source/source-template.json` mit eigenen HTTPS-Adressen, echter Dateigröße und erfolgreichem Build aktualisieren und als `deploy/web/source.json` bereitstellen.
7. Auf dem iPhone die eigene API-Adresse bei der Anmeldung konfigurieren; SideStore-Source hinzufügen und IPA signieren.

## Wichtige Produktregeln

- Jeder Benutzer sieht nur seine eigenen Datensätze. Server schreibt pro Änderung eine neue Revision, jede lokale Änderung bleibt bis zur Bestätigung erhalten.
- Beträge werden als **Integer-Cent** gespeichert. Fixkosten sind geplante Ausgaben und werden **nicht automatisch als tatsächliche Buchungen** gezählt.
- Einkaufslistenpreise sind Schätzungen; erst beim bestätigten Einkauf wird eine tatsächliche Ausgabe erzeugt.
- Die App verwendet keine direkte Bankverbindung. Alle Buchungen werden manuell erfasst, CSV-Export ist vorhanden.
- Offline-Synchronisationskonflikte überschreiben keine lokal geänderten Daten. Ein Konflikt erfordert einen manuellen Abgleich der betroffenen Datensätze.
- Die App benötigt gültiges HTTPS, einen stabilen Server-Domainnamen sowie einen Xcode-Build zur Installation. Die SideStore-Signatur muss abhängig vom Apple-Account erneuert werden.

## Offene Prüfungen für Produktion

- Reale iPhone-12-Build-, Installations-, Signatur- und Laufzeittests auf macOS/iOS.
- Live-HTTPS unter der endgültigen Domain, vollständiger Restore-Test aus verschlüsseltem PostgreSQL-Backup.
- E-Mail-Verifizierung/Passwort-Rücksetzung, falls die App außer für den privaten Eigengebrauch genutzt werden soll.
- UI-Feinschliff per Screenshot-Vergleich auf dem realen iPhone.
