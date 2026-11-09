import SwiftUI
import UIKit

@MainActor final class Store: ObservableObject {
    @Published private(set) var data = AppData()
    @Published var error: String?
    @Published private(set) var synchronizing = false
    private let directory: URL
    private let database: URL
    private var readable = true

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.documentsDirectory.appendingPathComponent("ALBOConnect", isDirectory: true)
        database = self.directory.appendingPathComponent("database.json")
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: database.path) {
                data = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: database))
            }
        } catch {
            readable = false
            self.error = "Die gespeicherten Daten konnten nicht geöffnet werden. Sie werden nicht überschrieben. \(error.localizedDescription)"
        }
    }

    @discardableResult private func commit(_ next: AppData, fromSync: Bool = false) -> Bool {
        guard !synchronizing || fromSync else { error = "Synchronisierung läuft. Bitte anschließend erneut speichern."; return false }
        guard readable else { error = "Speichern gesperrt, weil die vorhandene Datenbank nicht gelesen werden konnte."; return false }
        do {
            let bytes = try JSONEncoder().encode(next)
            try bytes.write(to: database, options: [.atomic, .completeFileProtection])
            data = next
            return true
        } catch {
            self.error = "Speichern fehlgeschlagen: \(error.localizedDescription)"
            return false
        }
    }

    func job(_ id: UUID) -> Job? { data.jobs.first { $0.id == id } }
    var canManage: Bool { data.syncState?.role != "worker" }
    private func requireManagement() -> Bool { if canManage { return true }; error = "Diese Änderung ist nur mit einem Verwaltungszugang möglich."; return false }
    func save(job: Job) -> Bool {
        guard requireManagement() else { return false }
        var next = data
        if let index = next.jobs.firstIndex(where: { $0.id == job.id }) { next.jobs[index] = job }
        else { next.jobs.append(job) }
        return commit(next)
    }
    func save(report: Report) -> Bool {
        guard canManage || (report.author == data.employee && data.reports.first(where: { $0.id == report.id }).map { $0.author == data.employee } != false) else { error = "Mitarbeiter dürfen nur eigene Berichte bearbeiten."; return false }
        guard job(report.jobID) != nil, ![report.title, report.author, report.text].contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            error = "Bitte Baustelle, Titel, Monteur und Berichtstext ergänzen."; return false
        }
        guard !report.completed || (!report.customerName.trimmingCharacters(in: .whitespaces).isEmpty && report.customerSignature != nil && report.workerSignature != nil) else {
            error = "Zum Abschließen bitte Kundenname und beide Unterschriften ergänzen."
            return false
        }
        var next = data
        if let index = next.reports.firstIndex(where: { $0.id == report.id }) { next.reports[index] = report }
        else { next.reports.insert(report, at: 0) }
        return commit(next)
    }
    func delete(report: Report) {
        guard canManage || report.author == data.employee else { error = "Mitarbeiter dürfen nur eigene Berichte löschen."; return }
        var next = data
        next.reports.removeAll { $0.id == report.id }
        if commit(next) {
            for photo in report.photos { try? FileManager.default.removeItem(at: directory.appendingPathComponent(photo.filename)) }
        }
    }
    var employees: [Employee] { data.employees ?? [Employee(id: UUID(uuidString: "A1B00000-0000-4000-8000-000000000001")!, name: data.employee.isEmpty ? "Salvatore" : data.employee)] }
    var customers: [Customer] { data.customers ?? [] }
    var currentClock: RunningClock? { data.clocks?[data.employee] ?? (data.clocks == nil ? data.clock : nil) }
    func saveEmployee(_ name: String) {
        guard canManage else { error = "Der Mitarbeiter ist durch den gekoppelten Zugang festgelegt."; return }
        guard employees.contains(where: { $0.name == name && $0.active }) else { error = "Bitte einen aktiven Mitarbeiter auswählen."; return }
        var next = data
        if next.clocks == nil, let legacy = next.clock { next.clocks = [data.employee: legacy]; next.clock = nil }
        next.employee = name
        commit(next)
    }
    func save(employee: Employee) -> Bool {
        guard requireManagement() else { return false }
        guard !employees.contains(where: { $0.id != employee.id && $0.name == employee.name }) else { error = "Dieser Mitarbeitername existiert bereits."; return false }
        var next = data; var list = employees
        if let i = list.firstIndex(where: { $0.id == employee.id }) {
            let old = list[i].name
            guard employee.active || old != data.employee else { error = "Bitte zuerst einen anderen aktiven Mitarbeiter auswählen."; return false }
            guard employee.active || next.clocks?[old] == nil else { error = "Bitte die laufende Zeiterfassung dieses Mitarbeiters zuerst beenden."; return false }
            if let clock = next.clocks?[old], old != employee.name { next.clocks?[employee.name] = clock; next.clocks?.removeValue(forKey: old) }
            for index in next.entries.indices where next.entries[index].employee == old { next.entries[index].employee = employee.name }
            if old == data.employee { next.employee = employee.name }
            list[i] = employee
        } else { list.append(employee) }
        next.employees = list; return commit(next)
    }
    func save(customer: Customer) -> Bool {
        guard requireManagement() else { return false }
        guard !customers.contains(where: { $0.id != customer.id && $0.name == customer.name }) else { error = "Dieser Kunde existiert bereits."; return false }
        var next = data; var list = customers
        if let i = list.firstIndex(where: { $0.id == customer.id }) {
            let old = list[i].name
            for j in next.jobs.indices where next.jobs[j].customer == old { next.jobs[j].customer = customer.name; next.jobs[j].address = customer.address }
            list[i] = customer
        } else { list.append(customer) }
        next.customers = list; return commit(next)
    }
    @discardableResult func saveTemplate(_ template: ReportTemplate) -> Bool {
        guard requireManagement() else { return false }
        var next = data
        if let index = next.templates.firstIndex(where: { $0.id == template.id }) { next.templates[index] = template }
        else { next.templates.append(template) }
        return commit(next)
    }
    func deleteTemplates(at offsets: IndexSet) { guard requireManagement() else { return }; var next = data; next.templates.remove(atOffsets: offsets); commit(next) }

    func start(jobID: UUID, now: Date = Date()) {
        guard job(jobID) != nil else { error = "Bitte eine gültige Baustelle wählen."; return }
        guard currentClock == nil else { return }
        var next = data
        next.clocks = next.clocks ?? [:]
        next.clocks?[data.employee] = RunningClock(jobID: jobID, started: now, segmentStart: now)
        next.clock = nil
        commit(next)
    }
    func togglePause(now: Date = Date()) {
        guard var clock = currentClock else { return }
        if clock.segmentStart != nil { clock.accumulated = clock.elapsed(at: now); clock.segmentStart = nil }
        else { clock.segmentStart = now }
        var next = data; next.clocks = next.clocks ?? [:]; next.clocks?[data.employee] = clock; next.clock = nil; commit(next)
    }
    func stop(now: Date = Date()) {
        guard let clock = currentClock else { return }
        var next = data
        next.entries.insert(WorkEntry(jobID: clock.jobID, start: clock.started, end: now, paidSeconds: clock.elapsed(at: now), employee: data.employee), at: 0)
        next.clock = nil
        next.clocks?.removeValue(forKey: data.employee)
        commit(next)
    }
    func addEntry(jobID: UUID, start: Date, end: Date) -> Bool {
        guard job(jobID) != nil else { error = "Bitte eine gültige Baustelle wählen."; return false }
        guard end > start else { error = "Das Ende muss nach dem Beginn liegen."; return false }
        guard currentClock == nil else { error = "Bitte die laufende Zeiterfassung zuerst beenden."; return false }
        guard !data.entries.contains(where: { ($0.employee ?? data.employee) == data.employee && start < $0.end && end > $0.start }) else {
            error = "Dieser Zeitraum überschneidet sich mit einer gespeicherten Arbeitszeit."; return false
        }
        var next = data; next.entries.insert(WorkEntry(jobID: jobID, start: start, end: end, employee: data.employee), at: 0)
        return commit(next)
    }
    func deleteEntry(_ id: UUID) { guard canManage || data.entries.first(where: { $0.id == id })?.employee == data.employee else { error = "Fremde Arbeitszeiten dürfen nicht gelöscht werden."; return }; var next = data; next.entries.removeAll { $0.id == id }; commit(next) }

    func addPhoto(_ image: UIImage, caption: String = "") throws -> SitePhoto {
        guard image.size.width > 0, image.size.height > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 1800 / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let bytes = resized.jpegData(compressionQuality: 0.8) else { throw CocoaError(.fileWriteUnknown) }
        let filename = UUID().uuidString + ".jpg"
        try bytes.write(to: directory.appendingPathComponent(filename), options: [.atomic, .completeFileProtection])
        return SitePhoto(filename: filename, caption: caption)
    }
    func photoURL(_ photo: SitePhoto) -> URL { directory.appendingPathComponent((photo.filename as NSString).lastPathComponent) }
    func photo(_ photo: SitePhoto) -> UIImage? { UIImage(contentsOfFile: photoURL(photo).path) }
    func backupURL() throws -> URL {
        // Self-contained backup, including attached images. Contains customer data.
        var photos: [String: Data] = [:]
        for report in data.reports {
            for photo in report.photos { photos[photo.filename] = try Data(contentsOf: photoURL(photo)) }
        }
        struct Backup: Encodable { var version = 1; var database: AppData; var photos: [String: Data] }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ALBO-Backup-\(UUID().uuidString).json")
        try JSONEncoder().encode(Backup(database: data, photos: photos)).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
    func importBackup(from url: URL) throws {
        struct Backup: Decodable { var version: Int; var database: AppData; var photos: [String: Data] }
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        let backup = try JSONDecoder().decode(Backup.self, from: Data(contentsOf: url))
        guard backup.version == 1 else { throw CocoaError(.coderReadCorrupt) }
        // Remap photo names to keep the previous database intact if import fails.
        var imported = backup.database
        for r in imported.reports.indices {
            for p in imported.reports[r].photos.indices {
                let original = imported.reports[r].photos[p].filename
                guard let bytes = backup.photos[original], let image = UIImage(data: bytes) else { throw CocoaError(.fileReadCorruptFile) }
                imported.reports[r].photos[p] = try addPhoto(image, caption: imported.reports[r].photos[p].caption)
            }
        }
        imported.clock = nil
        imported.clocks = [:]
        imported.syncState = nil
        guard commit(imported) else { throw CocoaError(.fileWriteUnknown) }
    }

    func makeSyncBackup() throws -> WorkspaceBackup {
        var photos: [String: Data] = [:]
        for report in data.reports { for photo in report.photos { photos[photo.filename] = try Data(contentsOf: photoURL(photo)) } }
        var database = data
        database.syncState = nil
        database.employees = employees
        database.customers = customers
        if database.clocks == nil { database.clocks = database.clock.map { [database.employee: $0] } ?? [:] }
        database.clock = nil
        return WorkspaceBackup(database: database, photos: photos)
    }

    func synchronize(using connection: PCConnection) async throws {
        guard !synchronizing else { return }
        synchronizing = true
        defer { synchronizing = false }
        let result = try await PCSync.exchange(connection: connection, local: makeSyncBackup(), previous: data.syncState)
        var next = result.snapshot.backup.database
        for report in next.reports {
            for photo in report.photos {
                guard UUID(uuidString: String(photo.filename.prefix(36))) != nil,
                      photo.filename.count == 40,
                      [".jpg", ".png"].contains(String(photo.filename.suffix(4))),
                      let bytes = result.snapshot.backup.photos[photo.filename], UIImage(data: bytes) != nil else { throw CocoaError(.fileReadCorruptFile) }
                let target = directory.appendingPathComponent(photo.filename)
                if FileManager.default.fileExists(atPath: target.path) {
                    guard try Data(contentsOf: target) == bytes else { throw PCSync.problem("Ein Foto hat dieselbe ID, aber einen anderen Inhalt. Die lokalen Daten bleiben erhalten.") }
                } else { try bytes.write(to: target, options: [.atomic, .completeFileProtection]) }
            }
        }
        let active = (next.employees ?? []).filter(\.active)
        if let employeeID = result.identity.employeeID, let employee = active.first(where: { $0.id.uuidString.caseInsensitiveCompare(employeeID) == .orderedSame }) { next.employee = employee.name }
        else { next.employee = active.first(where: { $0.name == data.employee })?.name ?? active.first?.name ?? data.employee }
        next.syncState = WorkspaceSyncState(server: connection.server, workspaceID: result.snapshot.workspaceID, revision: result.snapshot.revision, role: result.identity.role, proof: result.snapshot.proof, baseline: result.snapshot.baseline)
        guard commit(next, fromSync: true) else { throw PCSync.problem("Die empfangenen Daten konnten lokal nicht gespeichert werden.") }
    }
}
