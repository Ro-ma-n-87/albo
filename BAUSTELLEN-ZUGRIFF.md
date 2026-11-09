# ALBO Connect unterwegs — für 1–5 Personen

Die Vorbereitung nutzt ein privates NetBird-Netz zwischen Büro-PC und iPhones. Der Büro-PC bleibt der Datenserver und muss eingeschaltet sowie mit dem Internet verbunden sein. Die ALBO-App speichert weiterhin lokal; zum Austausch wird manuell synchronisiert.

NetBird nennt für kleine Teams aktuell einen kostenlosen Cloud-Tarif mit bis zu fünf Nutzern und 100 Geräten. Der Administrator zählt als Nutzer. Vor der Anmeldung den Tarif **Free** wählen, nicht den zeitlich begrenzten Test eines kostenpflichtigen Tarifs. [Tarife](https://netbird.io/pricing), [Tarifdokumentation](https://docs.netbird.io/manage/settings/plans-and-billing). Es fallen damit innerhalb der Tarifgrenzen keine zusätzlichen VPN-/Hostinggebühren an; der vorhandene PC, Strom und Internet werden weiterhin benötigt.

## Einmalige Einrichtung

1. Ein eigenes NetBird-Konto anlegen und den Free-Tarif prüfen. Kontoanmeldung, Vertragsannahme und Gerätezulassungen übernimmt der Nutzer selbst.
2. NetBird auf Büro-PC und iPhones aus der offiziellen Quelle installieren und die Geräte demselben eigenen Netz zuordnen. [Offizielle Installation](https://docs.netbird.io/get-started/install).
3. Im NetBird-Dashboard getrennte Gerätegruppen **ALBO-Büro-PC** und **ALBO-iPhones** anlegen. Den Büro-PC bzw. die vorgesehenen iPhones zuordnen. Eine gerichtete TCP-Regel von den iPhones zum Büro-PC ausschließlich auf Port **8788** anlegen. Breite Standardregeln nach Prüfung entfernen/deaktivieren; andere benötigte Verbindungen dabei berücksichtigen. Keine pauschale Freigabe des gesamten Büro-Netzes einrichten. [Gruppen und Zugriffsregeln](https://docs.netbird.io/manage/access-control/manage-network-access).
4. Am Büro-PC `pc/Start-Baustelle-Windows.cmd` starten und die **NetBird-IP dieses PCs** aus dem NetBird-Programm eingeben, beispielsweise `100.80.10.20`. Die echte Adresse hängt vom eigenen Netz ab.
5. Die PC-Verwaltung öffnet unter `http://localhost:8787`. Dort für jedes Gerät einen eigenen Mitarbeiterzugang unter **Geräte koppeln** erstellen.
6. In der **aktualisierten** ALBO-App unter **Mehr → PC-Verbindung** die Adresse `http://DEINE-NETBIRD-IP:8788` und den passenden Kopplungsschlüssel eintragen. **Private VPN-Verbindung (NetBird)** einschalten. Die bisherige erste IPA-Version besitzt diesen neuen Schalter noch nicht.
7. NetBird auf dem iPhone verbinden und dann **Verbinden und synchronisieren** antippen. ALBO Connect startet die VPN-App nicht selbst und erkennt deren Verbindungszustand nicht zuverlässig; ohne aktive VPN-Verbindung darf dieser HTTP-Modus nicht verwendet werden.

Es wurde kein NetBird-Konto erstellt, kein VPN installiert und keine Firewall-/Routerregel geändert. Diese externen Schritte sind noch offen. Falls Windows eine Firewallfreigabe verlangt, muss der Nutzer sie auf das vorgesehene Programm, die VPN-Verbindung und Port 8788 begrenzen. Keine Portweiterleitung am Internetrouter einrichten.

## Getrennte Zugänge

- **8787 / localhost:** PC-Verwaltung, Anmeldung, Geräte-Kopplung. Kein Listener an öffentlichen Adressen oder LAN-Schnittstellen im privaten VPN-Modus.
- **8788 / NetBird-IP:** Nur Daten laden und synchronisieren, mit gültigem Geräte-Kopplungsschlüssel. Keine PC-Anmeldung, keine Schlüsselverwaltung, keine Weboberfläche; lokale Browser-Sitzungen gelten hier nicht.
- Die Netzwerkverschlüsselung kommt in diesem Modus vom aktiven privaten VPN. Für eine spätere öffentlich erreichbare Serveradresse weiterhin HTTPS benutzen.

## Prüfen, bevor Mitarbeiter damit arbeiten

Am iPhone WLAN ausschalten und Mobilfunk sowie NetBird einschalten. Einen eigenen Testbericht erstellen, synchronisieren und am PC aktualisieren. Danach VPN trennen: ALBO darf den Server nicht mehr erreichen. Abschließend den Gerätezugang am PC widerrufen und prüfen, dass auch bei aktivem VPN kein Abgleich mehr möglich ist.

Server-Rollen und die Trennung der Endpunkte werden automatisiert getestet. Ein echter NetBird-Mobilfunk-Test sowie die Installation und Signierung der aktualisierten IPA bleiben bis zur Einrichtung offen.
