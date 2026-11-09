# Stand und Abnahme

Stand: 9. November 2026. Das Gesamtziel ist nicht abgeschlossen.

Die öffentliche Veröffentlichung im Repository `Ro-ma-n-87/albo` wurde vom Nutzer ausdrücklich freigegeben. Der Geräte-IPA-Workflow ist vorbereitet; sein Ergebnis muss nach dem Start geprüft werden. Es existiert noch keine nachgewiesene gebaute IPA-Datei.

| Anforderung aus der Bildvorlage | Aktueller Nachweis | Noch erforderlich |
|---|---|---|
| ALBO-Startseite mit sechs Kacheln und Navigation | Interaktive Vorschau im Browser geprüft; native Oberfläche in `RootView.swift` angelegt | Native Darstellung auf iPhone/iPad rendern und mit Vorlage vergleichen |
| Zeiterfassung für alle Mitarbeiter | Browsertest mit unabhängigen Mitarbeiterzeiten bestanden; native Speicherung implementiert; authentifizierter PC-Abgleich implementiert | Native Tests und Teamabgleich mit echten Geräten ausführen |
| Sprachberichte und KI-Formulierung | Native Apple-Spracherkennung und optionale lokale KI implementiert | Build, Mikrofon-/Berechtigungstests, deutsche Diktate und KI-Faktentreue auf unterstütztem Gerät prüfen |
| Individuelle Vorlagen | Im Browser getestet; native Verwaltung implementiert | Native Bedienung prüfen |
| Automatisches Aufmaß | Im Browser mit deutschen Dezimalzahlen geprüft; native Berechnung und Tests vorbereitet | Native Tests und Berichtübernahme prüfen |
| Zugeordnete Baustellenfotos | Browseranhänge einschließlich PDF getestet; native Mediathek/Kamera implementiert | Kamera, Bildbeschreibungen und Persistenz auf Gerät prüfen |
| Digitale Unterschriften Kunde/Monteur | Im Browser getestet; native Zeichenflächen und Speicherung implementiert | Finger/Stift, Drehung des Geräts und Export prüfen |
| Professionelle PDF-Berichte | Browser-PDF erfolgreich erzeugt und geöffnet; nativer mehrseitiger Renderer und PDFKit-Test vorbereitet | Native Textumbrüche, Sonderzeichen, Bilder und Seitenwechsel prüfen |
| Verwaltung am PC | Echte lokale PC-Verwaltung mit dauerhafter Speicherung im Browser getestet; Geräte-Kopplung, Berechtigungen, Widerruf, Konflikterkennung und Offline-Abgleich im Server getestet | Native Gegenstelle auf iPhone testen; HTTPS und Netzwerkbereitstellung für den konkreten Einsatz einrichten |
| Installierbare Apple-App | Xcode-Projekt, Scheme, Assets und Buildworkflow für Tests plus echte Geräte-IPA vorbereitet | Der Workflow wurde noch nicht gestartet; erfolgreicher macOS-Build, IPA-Datei, Apple-Signierung und Geräteinstallation fehlen |

## Prüfungen auf Windows

Die Projektstruktur, Dateireferenzen, Assets und XML-Dateien werden lokal geprüft. Diese Prüfung beweist weder Swift-Typkorrektheit noch iOS-Laufzeitverhalten.

Der echte PC-Server wurde mit `node --test pc/server.test.mjs` geprüft. Die Tests decken dauerhafte Speicherung und Neustart, parallele unabhängige Änderungen, Konflikte, Zugangsrollen, deaktivierte und widerrufene Geräte, abgewiesene fremde Ursprünge, beschädigte Datenbanken, Foto-/Unterschriftsdaten im nativen JSON-Format sowie signierte Ausgangsstände nach längerer Offline-Zeit ab.

Ein lokaler Edge-Browsertest prüfte Anmeldung, Baustellenanlage und Wiederladen, eigene Vorlagen, Berichtanlage und Druckansicht, Mitarbeiteranlage, Geräte-Kopplung und Widerruf. Die Darstellung wurde bei 320, 550 und 1100 Pixeln ohne horizontales Überlaufen geprüft. Der Druckaufruf wurde geprüft; eine vom Betriebssystem gespeicherte PC-PDF-Datei wurde dabei nicht erzeugt.

Die Server-/Browsertests sind kein Nachweis für den nativen Netzwerkzugriff, den iOS-Schlüsselbund, Netzwerkberechtigungen, ATS-Ausnahmen oder TLS-Verhalten. Diese Punkte benötigen weiterhin einen Apple-Build und Gerätetests.

## Vorbereitete native Tests — noch nicht ausgeführt

`ALBOConnectTests/StoreTests.swift` prüft insbesondere:

- Pausenberechnung, Neustart während Pause und tatsächliches Ende einer Arbeitszeit.
- Unabhängige Mitarbeiterzeiten und Ablehnung sich überschneidender manueller Einträge.
- Schutz einer beschädigten Datenbank vor versehentlichem Überschreiben.
- Sicherung und Wiederherstellung von Fotoanhängen und Unterschriften.
- Mehrseitige PDF-Ausgabe und deutsche Sonderzeichen.
- Deutsche Dezimalzahlen und Ablehnung ungültiger Maße.

Erst ein erfolgreicher Lauf unter Xcode ist ein Prüfnachweis für diese Tests.
