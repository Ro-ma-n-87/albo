import Foundation

enum JobStatus: String, Codable, CaseIterable, Identifiable {
    case planned = "Geplant", active = "In Arbeit", done = "Abgeschlossen"
    var id: String { rawValue }
}

struct Job: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var customer: String
    var address: String
    var status: JobStatus = .planned
    var notes = ""
}

struct WorkEntry: Identifiable, Codable {
    var id = UUID()
    var jobID: UUID
    var start: Date
    var end: Date
    var paidSeconds: TimeInterval? = nil
    var employee: String? = nil
    var seconds: TimeInterval { max(0, paidSeconds ?? end.timeIntervalSince(start)) }
}

struct RunningClock: Codable {
    var jobID: UUID
    var started: Date
    var segmentStart: Date?
    var accumulated: TimeInterval = 0
    func elapsed(at date: Date) -> TimeInterval {
        accumulated + (segmentStart.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }
}

struct Measurement: Identifiable, Codable {
    var id = UUID()
    var label: String
    var length: Double
    var width: Double
    var quantity: Int
    var squareMetres: Double { length * width * Double(quantity) }
}

struct SitePhoto: Identifiable, Codable {
    var id = UUID()
    var filename: String
    var caption: String
}

struct Report: Identifiable, Codable {
    var id = UUID()
    var jobID: UUID
    var date = Date()
    var author: String
    var title: String
    var text: String
    var materials: String
    var photos: [SitePhoto] = []
    var measurements: [Measurement] = []
    var customerName = ""
    var workerSignature: Data? = nil
    var customerSignature: Data? = nil
    var completed = false
}

struct ReportTemplate: Identifiable, Codable {
    var id = UUID()
    var name: String
    var text: String
    static let defaults = [
        ReportTemplate(id: UUID(uuidString: "A1B00000-0000-4000-8000-000000001001")!, name: "Wartung", text: "Anlage / Gerät:\nDurchgeführte Wartung:\nMesswerte:\nFestgestellte Mängel:\nEmpfohlene Maßnahmen:"),
        ReportTemplate(id: UUID(uuidString: "A1B00000-0000-4000-8000-000000001002")!, name: "Reparatur", text: "Gemeldete Störung:\nUrsache:\nDurchgeführte Arbeiten:\nFunktionsprüfung:\nWeitere Maßnahmen:"),
        ReportTemplate(id: UUID(uuidString: "A1B00000-0000-4000-8000-000000001003")!, name: "Kundendienst", text: "Kundenauftrag:\nDurchgeführte Arbeiten:\nErgebnis / Übergabe:\nOffene Punkte:")
    ]
}

struct AppData: Codable {
    var jobs: [Job] = []
    var reports: [Report] = []
    var entries: [WorkEntry] = []
    var clock: RunningClock? = nil
    var employee = "Salvatore"
    var templates = ReportTemplate.defaults
    var clocks: [String: RunningClock]? = nil
    var employees: [Employee]? = nil
    var customers: [Customer]? = nil
    var syncState: WorkspaceSyncState? = nil
}

struct WorkspaceSyncState: Codable {
    var server: String
    var workspaceID: String
    var revision: Int
    var role: String? = nil
    var proof: String? = nil
    var baseline: Data? = nil
}

struct WorkspaceBackup: Codable {
    var version = 1
    var database: AppData
    var photos: [String: Data]
}

struct Employee: Identifiable, Codable {
    var id = UUID()
    var name: String
    var role = "Monteur"
    var active = true
}

struct Customer: Identifiable, Codable {
    var id = UUID()
    var name: String
    var address: String
    var phone = ""
    var email = ""
}

enum InputNumber {
    static func decimal(_ value: String) -> Double? {
        guard let number = Double(value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")), number.isFinite, number > 0 else { return nil }
        return number
    }
}

func durationText(_ seconds: TimeInterval) -> String {
    let value = Int(max(0, seconds))
    return String(format: "%02d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60)
}
