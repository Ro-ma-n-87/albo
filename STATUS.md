# Stand und Abnahme

Stand: 9. November 2026. Das Gesamtziel ist nicht abgeschlossen.

Neu: Privater Baustellenzugriff für 1–5 Personen mit NetBird vorbereitet. Die Verwaltung bleibt auf localhost:8787; der getrennte Abgleich bindet nur an die NetBird-IP auf Port 8788. Neun Server-Tests bestanden, einschließlich Abweisung lokaler Browser-Sitzungen und administrativer Endpunkte am Baustellenzugang. Aktualisierte iOS-Unterstützung und zusätzlicher nativer Test müssen noch im neuen Build geprüft werden. Der bisherige erfolgreiche Build unten enthält diesen VPN-Schalter noch nicht.

Die öffentliche Veröffentlichung im Repository `Ro-ma-n-87/albo` wurde vom Nutzer ausdrücklich freigegeben. [Build 42670462238](https://github.com/Ro-ma-n-87/albo/actions/runs/42670462238) ist erfolgreich abgeschlossen. Quellcommit: `8a35536f94ca8bef6053949502224720657b89d5`.

Die erzeugte Datei `ALBOConnect-unsigned.ipa` hat 1.046.430 Bytes und die SHA-256-Prüfsumme `e0902129467c4b6bb37e075c16cd52372fc01faaba63860c713d6042bb545814`. Nach dem Download wurden Archivstruktur, Prüfsumme, arm64-Mach-O-Code und die iOS-Geräteplattform geprüft. Die Datei ist **nicht Apple-signiert** und enthält kein Provisioning-Profil.

| Anforderung aus der Bildvorlage | Aktueller Nachweis | Noch erforderlich |
|---|---|---|
| ALBO-Startseite mit sechs Kacheln und Navigation | Interaktive Vorschau im Browser geprüft; native Oberfläche in `RootView.swift` angelegt | Native Darstellung auf iPhone/iPad rendern und mit Vorlage vergleichen |
| Zeiterfassung für alle Mitarbeiter | Browser- und native Tests für unabhängige Zeiten, Pausen, Neustart und Überschneidungen bestanden; PC-Abgleich implementiert | Teamabgleich mit echten Geräten ausführen |
| Sprachberichte und KI-Formulierung | Native Apple-Spracherkennung und optionale lokale KI implementiert | Build, Mikrofon-/Berechtigungstests, deutsche Diktate und KI-Faktentreue auf unterstütztem Gerät prüfen |
| Individuelle Vorlagen | Im Browser getestet; native Verwaltung implementiert | Native Bedienung prüfen |
| Automatisches Aufmaß | Browser- und native Tests mit deutschen Dezimalzahlen und ungültigen Werten bestanden | Bedienung und Berichtübernahme auf Gerät prüfen |
| Zugeordnete Baustellenfotos | Browseranhänge einschließlich PDF getestet; native Mediathek/Kamera implementiert | Kamera, Bildbeschreibungen und Persistenz auf Gerät prüfen |
| Digitale Unterschriften Kunde/Monteur | Im Browser getestet; native Zeichenflächen und Speicherung implementiert | Finger/Stift, Drehung des Geräts und Export prüfen |
| Professionelle PDF-Berichte | Browser-PDF erzeugt; nativer PDFKit-Test für mehrere Seiten und deutsche Sonderzeichen bestanden | Vollständige Darstellung und Bildanhänge in nativen Berichten visuell prüfen |
| Verwaltung am PC | Echte lokale PC-Verwaltung mit dauerhafter Speicherung im Browser getestet; Geräte-Kopplung, Berechtigungen, Widerruf, Konflikterkennung und Offline-Abgleich im Server getestet | Native Gegenstelle auf iPhone testen; HTTPS und Netzwerkbereitstellung für den konkreten Einsatz einrichten |
| Installierbare Apple-App | Simulator-Tests und Release-Geräte-Build erfolgreich; echte arm64-IPA erzeugt und nach Download geprüft | Apple-Signierung, Provisioning-Profil und Geräteinstallation fehlen |

## Prüfungen auf Windows

Die Projektstruktur, Dateireferenzen, Assets und XML-Dateien werden lokal geprüft. Diese Prüfung beweist weder Swift-Typkorrektheit noch iOS-Laufzeitverhalten.

Der echte PC-Server wurde mit `node --test pc/server.test.mjs` geprüft. Die Tests decken dauerhafte Speicherung und Neustart, parallele unabhängige Änderungen, Konflikte, Zugangsrollen, deaktivierte und widerrufene Geräte, abgewiesene fremde Ursprünge, beschädigte Datenbanken, Foto-/Unterschriftsdaten im nativen JSON-Format sowie signierte Ausgangsstände nach längerer Offline-Zeit ab.

Ein lokaler Edge-Browsertest prüfte Anmeldung, Baustellenanlage und Wiederladen, eigene Vorlagen, Berichtanlage und Druckansicht, Mitarbeiteranlage, Geräte-Kopplung und Widerruf. Die Darstellung wurde bei 320, 550 und 1100 Pixeln ohne horizontales Überlaufen geprüft. Der Druckaufruf wurde geprüft; eine vom Betriebssystem gespeicherte PC-PDF-Datei wurde dabei nicht erzeugt.

Die Server-/Browsertests sind kein Nachweis für den nativen Netzwerkzugriff, den iOS-Schlüsselbund, Netzwerkberechtigungen, ATS-Ausnahmen oder TLS-Verhalten. Diese Punkte benötigen weiterhin einen Apple-Build und Gerätetests.

## Native Tests — sieben bestanden

`ALBOConnectTests/StoreTests.swift` prüft insbesondere:

- Pausenberechnung, Neustart während Pause und tatsächliches Ende einer Arbeitszeit.
- Unabhängige Mitarbeiterzeiten und Ablehnung sich überschneidender manueller Einträge.
- Schutz einer beschädigten Datenbank vor versehentlichem Überschreiben.
- Sicherung und Wiederherstellung von Fotoanhängen und Unterschriften.
- Mehrseitige PDF-Ausgabe und deutsche Sonderzeichen.
- Deutsche Dezimalzahlen und Ablehnung ungültiger Maße.
- Ablehnung öffentlicher HTTP-Adressen und eingebetteter Zugangsdaten bei der PC-Verbindung.

Diese Tests wurden unter Xcode 26.6 auf dem iOS-Simulator ausgeführt: sieben Tests, null Fehler. Der erfolgreiche Lauf bestätigt die genannten Logiktests; er ersetzt weder eine vollständige UI-Prüfung noch Mikrofon-, Kamera-, KI- und Netzwerkversuche auf einem echten Gerät.
