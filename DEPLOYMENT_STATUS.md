# Deployment- und Prüfprotokoll – Klar. 1.0.0

Datum: 2026-11-12 (Europe/Vienna)

## Verifizierter Teil

- **VPS:** bestehender privater Server, SSH-Alias `wardogs-vps`; Code unter `/opt/klar-app`.
- **Backend:** PostgreSQL 17 in Docker, FastAPI in eigenem Container, Caddy als HTTPS-Reverse-Proxy.
- **Live API:** `https://api.152.53.206.242.sslip.io/health` lieferte `{"status":"ok","service":"klar-api"}`.
- **SideStore-Source:** `https://apps.152.53.206.242.sslip.io/source.json` liefert eine valide leere Source (apps=[]). **Keine IPA verfügbar.**
- **Datenbankmigration:** Start des API-Containers führt `alembic upgrade head` aus; Container blieb nach dem korrigierten Python-Pfad online.
- **Tests:** sechs automatisierte FastAPI-Tests plus vier Tests des Source-Generators erfolgreich (`10 passed`).
- **iOS-Quellcode:** Swift-Parser akzeptiert alle Swift-Dateien; kein Xcode-Typcheck, kein iOS-Build.
- **App-Grundfunktionen im Code:** Aufgaben, wiederkehrende Aufgaben, Transaktionen, Fixkosten, Abos, Monatsbudgets, Einkaufslisten mit Ausgabeübernahme, Kalender, Face ID/Geräte-Code, Push-Erinnerungen, Offline-Speicherung, Token-Anmeldung, Datensynchronisierung, CSV-Export und Dark Mode.

## Noch NICHT verifiziert oder ausgeliefert

1. Die App wurde nicht auf einem Mac unter Xcode gebaut und nicht auf einem iPhone 12 ausgeführt.
2. Eine signierbare/installierbare `.ipa` existiert noch nicht; SideStore-Installation und Update im echten Client sind nicht getestet.
3. Pixelgenaue Übereinstimmung mit den Design-Mockups wurde auf einem echten Gerät nicht geprüft.
4. Verschlüsselte Offsite-Backups und Rücksicherung wurden nicht eingerichtet bzw. getestet.
5. Der temporäre Domainname über `sslip.io` sollte vor dauerhaftem Einsatz gegen eigene stabile Domains ersetzt werden.
6. Produktiver Kontoregistrierungs- und Synchronisations-Test auf dem öffentlichen Endpoint wurde hier nicht abschließend nachgewiesen; automatisierte Backend-Integrationstests waren erfolgreich.

**Diese Ergebnisse sind ein umfassender Quellcode- und Backend-Stand, aber noch keine fertig ausgelieferte iPhone-App.**
