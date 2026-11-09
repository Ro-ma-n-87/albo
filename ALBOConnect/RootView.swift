import SwiftUI
import UniformTypeIdentifiers

enum HomeRoute: String, Identifiable {
    case speech, templates, photos, measurement
    var id: String { rawValue }
}

struct RootView: View {
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView(tab: $tab) }.tabItem { Label("Start", systemImage: "house.fill") }.tag(0)
            NavigationStack { JobsView() }.tabItem { Label("Baustellen", systemImage: "building.2") }.tag(1)
            NavigationStack { ReportsView() }.tabItem { Label("Berichte", systemImage: "doc.text") }.tag(2)
            NavigationStack { TimeView() }.tabItem { Label("Zeiten", systemImage: "clock") }.tag(3)
            NavigationStack { SettingsView() }.tabItem { Label("Mehr", systemImage: "ellipsis") }.tag(4)
        }
        .preferredColorScheme(.light)
    }
}

struct BrandLogo: View {
    var body: some View {
        VStack(spacing: 6) {
            Image("Reference").resizable().frame(width: 1176, height: 2560)
                .offset(x: -100, y: -968).frame(width: 270, height: 100, alignment: .topLeading).clipped()
                .accessibilityLabel("ALBO Sanitär und Heizung Meisterbetrieb")
            HStack(spacing: 5) {
                Text("ALBO").font(.system(size: 32, weight: .heavy))
                Text("Connect").font(.system(size: 30, weight: .bold)).italic().foregroundStyle(.white)
                    .padding(.horizontal, 8).background(Brand.blue, in: RoundedRectangle(cornerRadius: 5))
            }
            Text("Baustellendokumentation · Zeiterfassung · Berichte").font(.system(size: 10))
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var store: Store
    @Binding var tab: Int
    @State private var route: HomeRoute?
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                BrandLogo().padding(.top, 10).padding(.bottom, 20)
                VStack(alignment: .leading, spacing: 15) {
                    Text("Guten Morgen, \(store.data.employee.isEmpty ? "Team" : store.data.employee) 👋")
                        .font(.system(size: 18, weight: .bold)).minimumScaleFactor(0.7).lineLimit(1)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        tile("Arbeitszeit", "Starten · Pause · Beenden", "clock", primary: true) { tab = 3 }
                        tile("Meine\nBaustellen", "Kunden · Projekte", "person.fill.viewfinder") { tab = 1 }
                        tile("Bericht sprechen", "Per Sprache zum\nfertigen Bericht", "mic") { route = .speech }
                        tile("Berichtsvorlagen", "Gespeicherte\nVorlagen nutzen", "list.clipboard") { route = .templates }
                        tile("Fotos", "Baustellenfotos\ndokumentieren", "camera") { route = .photos }
                        tile("Aufmaß", "Maße erfassen\nund berechnen", "ruler") { route = .measurement }
                    }
                }
                .padding(14)
                .background {
                    ZStack(alignment: .bottom) {
                        LinearGradient(colors: [.white, Color(red: 0.78, green: 0.89, blue: 0.95)], startPoint: .topTrailing, endPoint: .bottomLeading)
                        Wave().stroke(Color.cyan.opacity(0.25), lineWidth: 9).frame(height: 80)
                        Wave().stroke(Color.red.opacity(0.85), lineWidth: 7).frame(height: 55).offset(x: 200, y: 20)
                    }.clipped()
                }
            }
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .background(.white).toolbar(.hidden, for: .navigationBar)
        .sheet(item: $route) { route in
            NavigationStack {
                Group {
                    switch route {
                    case .speech: SpeechReportView()
                    case .templates: TemplatesView()
                    case .photos: PhotoLibraryView()
                    case .measurement: MeasurementStartView()
                    }
                }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { self.route = nil } } }
            }
        }
    }
    private func tile(_ title: String, _ subtitle: String, _ symbol: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 29, weight: .regular)).foregroundStyle(primary ? .white : Brand.blue)
                Text(title).font(.system(size: 16, weight: .bold)).minimumScaleFactor(0.7)
                Text(subtitle).font(.system(size: 11)).minimumScaleFactor(0.8)
            }
            .multilineTextAlignment(.center).foregroundStyle(primary ? Color.white : Color.black)
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(primary ? Brand.blue : Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 17))
            .contentShape(RoundedRectangle(cornerRadius: 17))
        }.buttonStyle(.plain)
    }
}

struct Wave: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in p.move(to: CGPoint(x: -30, y: rect.height * 0.7)); p.addCurve(to: CGPoint(x: rect.width + 30, y: 5), control1: CGPoint(x: rect.width * 0.45, y: rect.height * 1.8), control2: CGPoint(x: rect.width * 0.6, y: -30)) }
    }
}

struct JobsView: View {
    @EnvironmentObject private var store: Store
    @State private var adding = false
    var body: some View {
        List {
            if store.data.jobs.isEmpty { ContentUnavailableView("Noch keine Baustelle", systemImage: "building.2", description: Text("Lege deine erste Baustelle über + an.")) }
            ForEach(store.data.jobs) { job in NavigationLink { JobDetailView(jobID: job.id) } label: { JobRow(job: job) } }
        }.navigationTitle("Baustellen")
            .toolbar { Button { adding = true } label: { Label("Baustelle anlegen", systemImage: "plus") }.disabled(!store.canManage) }
            .sheet(isPresented: $adding) { NavigationStack { JobEditor(job: Job(title: "", customer: "", address: "")) } }
    }
}
struct JobRow: View {
    let job: Job
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(job.customer).font(.headline); Spacer(); Text(job.status.rawValue).font(.caption2).foregroundStyle(job.status == .active ? .green : .secondary) }
            Text(job.title).font(.subheadline)
            Text(job.address).font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}
struct JobEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var job: Job
    var body: some View {
        Form {
            TextField("Kunde", text: $job.customer)
            if !store.customers.isEmpty {
                Menu("Gespeicherten Kunden wählen") {
                    ForEach(store.customers) { customer in Button(customer.name) { job.customer = customer.name; job.address = customer.address } }
                }
            }
            TextField("Projekt", text: $job.title)
            TextField("Adresse", text: $job.address)
            Picker("Status", selection: $job.status) { ForEach(JobStatus.allCases) { Text($0.rawValue).tag($0) } }
            Section("Notizen") { TextEditor(text: $job.notes).frame(minHeight: 120) }
        }.navigationTitle("Baustelle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Speichern") { if store.save(job: job) { dismiss() } }.disabled([job.title, job.customer, job.address].contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) }
            }
    }
}
struct JobDetailView: View {
    @EnvironmentObject private var store: Store
    let jobID: UUID
    @State private var edit = false
    @State private var report = false
    var body: some View {
        List {
            if let job = store.job(jobID) {
                Section { JobRow(job: job); if !job.notes.isEmpty { Text(job.notes) } }
                Button("Bericht erstellen") { report = true }
                Section("Berichte") {
                    ForEach(store.data.reports.filter { $0.jobID == jobID }) { report in NavigationLink { ReportDetailView(reportID: report.id) } label: { ReportRow(report: report) } }
                }
            }
        }.navigationTitle(store.job(jobID)?.customer ?? "Baustelle")
            .toolbar { Button("Bearbeiten") { edit = true }.disabled(!store.canManage) }
            .sheet(isPresented: $edit) { if let job = store.job(jobID) { NavigationStack { JobEditor(job: job) } } }
            .sheet(isPresented: $report) { NavigationStack { ReportEditor(report: Report(jobID: jobID, author: store.data.employee, title: "", text: "", materials: "")) } }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @State private var backup: URL?
    @State private var importing = false
    @State private var confirmImport = false
    var body: some View {
        Form {
            Section("Mitarbeiter") {
                if store.canManage {
                    Picker("Aktiv", selection: Binding(get: { store.data.employee }, set: store.saveEmployee)) { ForEach(store.employees.filter(\.active)) { Text($0.name).tag($0.name) } }
                } else { LabeledContent("Aktiv", value: store.data.employee) }
            }
            Section {
                NavigationLink("PC-Verbindung", destination: PCSyncView())
                if store.canManage { NavigationLink("Verwaltung", destination: AdminView()) }
                NavigationLink("Berichtsvorlagen", destination: TemplatesView())
            }
            Section("Datensicherung") {
                Button("Sicherung erstellen") { do { backup = try store.backupURL() } catch { store.error = error.localizedDescription } }
                if let backup { ShareLink("Sicherung teilen", item: backup) }
                Button("Sicherung wiederherstellen") { confirmImport = true }
                Text("Die Sicherung enthält Kundendaten, Fotos und Unterschriften. Bewahre sie an einem geschützten Ort auf.").font(.caption)
            }
            Section("ALBO Connect") {
                Text("Die Daten werden lokal gespeichert. Unter PC-Verbindung kannst du sie mit der eigenen PC-Verwaltung abgleichen.").font(.footnote)
                Text("KI-Berichte verwenden Apple Intelligence, sofern auf diesem Gerät verfügbar. Diktate können alternativ manuell bearbeitet werden.").font(.footnote)
            }
        }.navigationTitle("Mehr")
            .confirmationDialog("Vorhandene Daten durch die Sicherung ersetzen?", isPresented: $confirmImport, titleVisibility: .visible) { Button("Sicherung auswählen", role: .destructive) { importing = true } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do { try store.importBackup(from: result.get()) } catch { store.error = "Wiederherstellung fehlgeschlagen: \(error.localizedDescription)" }
            }
    }
}
