import SwiftUI
import Security

struct PCConnection: Codable {
    var server: String
    var token: String
    var privateVPN: Bool? = nil
    static func read() -> PCConnection? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.albo.connect.pc", kSecAttrAccount as String: "connection", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let bytes = item as? Data else { return nil }
        return try? JSONDecoder().decode(Self.self, from: bytes)
    }
    func save() throws {
        let bytes = try JSONEncoder().encode(self)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.albo.connect.pc", kSecAttrAccount as String: "connection"]
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: bytes] as CFDictionary)
        if update == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = bytes; add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw PCSync.problem("Kopplungsschlüssel konnte nicht im Schlüsselbund gespeichert werden.") }
        } else if update != errSecSuccess { throw PCSync.problem("Kopplungsschlüssel konnte nicht aktualisiert werden.") }
    }
}

struct PCIdentity: Decodable { var role: String; var employeeID: String? }
struct PCSnapshot: Decodable { var workspaceID: String; var revision: Int; var backup: WorkspaceBackup; var identity: PCIdentity?; var proof: String?; var baseline: Data? = nil }
struct PCSyncResult { var snapshot: PCSnapshot; var identity: PCIdentity }

enum PCSync {
    static func problem(_ text: String) -> NSError { NSError(domain: "ALBOPCSync", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    static func serverURL(_ address: String, privateVPN: Bool = false) throws -> URL {
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, ["", "/"].contains(url.path) else { throw problem("Bitte eine Serveradresse wie https://buero.example.de:8787 eingeben.") }
        if scheme == "https" { return url }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let parts = labels.compactMap { Int($0) }
        let validIPv4 = labels.count == 4 && parts.count == 4 && labels.allSatisfy { !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } } && parts.allSatisfy { (0...255).contains($0) }
        let privateIPv4 = validIPv4 && (parts[0] == 10 || parts[0] == 127 || (parts[0] == 192 && parts[1] == 168) || (parts[0] == 172 && (16...31).contains(parts[1])))
        let vpnIPv4 = privateVPN && validIPv4 && parts[0] == 100 && (64...127).contains(parts[1])
        guard scheme == "http", host == "localhost" || host.hasSuffix(".local") || privateIPv4 || vpnIPv4 else { throw problem("Für eine NetBird-Adresse bitte Private VPN-Verbindung aktivieren. Öffentliche Server benötigen HTTPS.") }
        return url
    }
    static func exchange(connection: PCConnection, local: WorkspaceBackup, previous: WorkspaceSyncState?) async throws -> PCSyncResult {
        let base = try serverURL(connection.server, privateVPN: connection.privateVPN ?? false)
        guard connection.token.count == 64, connection.token.allSatisfy({ $0.isHexDigit }) else { throw problem("Bitte den vollständigen Kopplungsschlüssel aus der PC-Verwaltung eintragen.") }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 60
        let session = URLSession(configuration: config, delegate: NoPCRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        func request(_ path: String, body: Data? = nil) async throws -> PCSnapshot {
            var request = URLRequest(url: base.appendingPathComponent("api").appendingPathComponent(path))
            request.httpMethod = body == nil ? "GET" : "POST"
            request.setValue("Bearer " + connection.token, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = body
            let (bytes, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw problem("Keine gültige Serverantwort.") }
            guard (200...299).contains(http.statusCode) else {
                struct Message: Decodable { var error: String }
                let message = (try? JSONDecoder().decode(Message.self, from: bytes).error) ?? "Serverfehler \(http.statusCode). Die lokalen Daten bleiben erhalten."
                throw problem(message)
            }
            var snapshot = try JSONDecoder().decode(PCSnapshot.self, from: bytes)
            if let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], let backup = object["backup"] as? [String: Any], let database = backup["database"] {
                snapshot.baseline = try JSONSerialization.data(withJSONObject: database, options: [.sortedKeys])
            }
            return snapshot
        }
        let remote = try await request("workspace")
        guard let identity = remote.identity else { throw problem("Server lieferte keine Zugangsrolle.") }
        let same = previous?.server == connection.server && previous?.workspaceID.caseInsensitiveCompare(remote.workspaceID) == .orderedSame
        let originalTemplates = ReportTemplate.defaults
        let untouchedTemplates = local.database.templates.count == originalTemplates.count && local.database.templates.allSatisfy { template in originalTemplates.contains { $0.name == template.name && $0.text == template.text } }
        let freshEmployee = (local.database.employees ?? []).count == 1 && local.database.employees?.first?.name == "Salvatore" && local.database.employees?.first?.role == "Monteur"
        let fresh = local.database.jobs.isEmpty && local.database.reports.isEmpty && local.database.entries.isEmpty && (local.database.customers ?? []).isEmpty && (local.database.clocks ?? [:]).isEmpty && freshEmployee && untouchedTemplates
        if !same, fresh { return PCSyncResult(snapshot: remote, identity: identity) }
        if !same, identity.role != "admin" { throw problem("Dieses Gerät enthält bereits lokale Daten. Bitte zuerst eine Sicherung erstellen und den Erstabgleich mit einem Verwaltungszugang durchführen.") }
        struct Upload: Encodable { var workspaceID: String; var baseRevision: Int?; var backup: WorkspaceBackup }
        var changes = local
        changes.photos = local.photos.filter { remote.backup.photos[$0.key] != $0.value }
        let upload = Upload(workspaceID: remote.workspaceID, baseRevision: same ? previous?.revision : nil, backup: changes)
        // JSONEncoder omits nil by default; the server uses an explicit null for a safe first merge.
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(upload)) as! [String: Any]
        if upload.baseRevision == nil { object["baseRevision"] = NSNull() }
        if same, let proof = previous?.proof, let baseline = previous?.baseline, let revision = previous?.revision {
            object["baseSnapshot"] = ["revision": revision, "proof": proof, "database": try JSONSerialization.jsonObject(with: baseline)]
        }
        let updated = try await request("sync", body: JSONSerialization.data(withJSONObject: object))
        return PCSyncResult(snapshot: updated, identity: identity)
    }
}

private final class NoPCRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct PCSyncView: View {
    @EnvironmentObject private var store: Store
    @State private var server = ""
    @State private var token = ""
    @State private var status = ""
    @State private var privateVPN = false
    var body: some View {
        Form {
            Section("Verbindung") {
                TextField("Serveradresse", text: $server).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Kopplungsschlüssel", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle("Private VPN-Verbindung (NetBird)", isOn: $privateVPN)
                if privateVPN { Text("Zuerst NetBird auf dem iPhone verbinden. Verwende die NetBird-Adresse des Büro-PCs, z. B. http://100.80.10.20:8788. Die ALBO-App startet und prüft die VPN-Verbindung nicht selbst.").font(.caption) }
                Text("Am PC unter Geräte koppeln einen eigenen Zugang erstellen. Auf dem iPhone die Netzwerkadresse des PCs eintragen; localhost bezeichnet auf dem iPhone das iPhone selbst.").font(.caption)
            }
            Section {
                Button("Verbinden und synchronisieren") {
                    let connection = PCConnection(server: server.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")), token: token.trimmingCharacters(in: .whitespacesAndNewlines), privateVPN: privateVPN)
                    Task { @MainActor in
                        do { try connection.save(); try await store.synchronize(using: connection); status = "Synchronisiert · \(Date().formatted(date: .omitted, time: .shortened))" }
                        catch { store.error = error.localizedDescription; status = privateVPN ? "Nicht synchronisiert. NetBird-Verbindung und Büro-PC prüfen. Lokale Änderungen bleiben erhalten." : "Nicht synchronisiert. Lokale Änderungen bleiben erhalten." }
                    }
                }.disabled(store.synchronizing || server.isEmpty || token.isEmpty)
                if store.synchronizing { ProgressView("Daten abgleichen …") }
                if !status.isEmpty { Text(status).font(.caption) }
            }
            Section("Abgleich") {
                Text("Beim ersten Verbinden lädt ein leeres Gerät den PC-Datenbestand. Vorhandene lokale Daten werden nur mit einem Verwaltungszugang zusammengeführt. Bei späteren Abgleichen bleiben unabhängige Änderungen erhalten; Konflikte werden gemeldet.").font(.footnote)
                Text("Der Kopplungsschlüssel wird im iOS-Schlüsselbund gespeichert. Öffentliche Server benötigen HTTPS. Bei NetBird muss der private VPN-Tunnel aktiv sein; darüber wird die Verbindung verschlüsselt.").font(.footnote)
                if let state = store.data.syncState { LabeledContent("Serverstand", value: state.revision.formatted()) }
            }
        }.navigationTitle("PC-Verbindung")
            .onAppear { if let connection = PCConnection.read() { server = connection.server; token = connection.token; privateVPN = connection.privateVPN ?? false } }
    }
}
