import SwiftUI
import PhotosUI

struct ReportsView: View {
    @EnvironmentObject private var store: Store
    @State private var adding = false
    var body: some View {
        List {
            if store.data.reports.isEmpty { ContentUnavailableView("Noch keine Berichte", systemImage: "doc.text", description: Text("Lege einen Bericht über + an.")) }
            ForEach(store.data.reports) { report in NavigationLink { ReportDetailView(reportID: report.id) } label: { ReportRow(report: report) } }
        }.navigationTitle("Berichte").toolbar { Button { adding = true } label: { Label("Neuer Bericht", systemImage: "plus") } }
            .sheet(isPresented: $adding) { NavigationStack { ReportEditor(report: Report(jobID: store.data.jobs.first?.id ?? UUID(), author: store.data.employee, title: "", text: "", materials: "")) } }
    }
}
struct ReportRow: View {
    @EnvironmentObject private var store: Store
    let report: Report
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(report.date, format: .dateTime.day().month().year()).font(.caption).foregroundStyle(.secondary)
            Text(report.title).font(.headline)
            HStack { Text(store.job(report.jobID)?.customer ?? "Baustelle"); Spacer(); Text(report.completed ? "Abgeschlossen" : "Entwurf").foregroundStyle(report.completed ? .green : .secondary) }.font(.caption)
        }.padding(.vertical, 5)
    }
}

struct ReportEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var report: Report
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var takingPhoto = false
    @State private var addingMeasurement = false
    @State private var addingJob = false
    @State private var loadingPhotos = false
    var body: some View {
        Form {
            if store.data.jobs.isEmpty {
                Section { Text("Lege zuerst eine Baustelle an."); Button("Baustelle anlegen") { addingJob = true } }
            } else {
                Section("Zuordnung") {
                    Picker("Baustelle", selection: $report.jobID) { ForEach(store.data.jobs) { Text("\($0.customer) · \($0.title)").tag($0.id) } }
                    TextField("Berichtstitel", text: $report.title)
                    TextField("Monteur", text: $report.author).disabled(!store.canManage)
                    DatePicker("Datum", selection: $report.date, displayedComponents: .date)
                }
                Section("Durchgeführte Arbeiten") {
                    Menu("Vorlage einsetzen") { ForEach(store.data.templates) { template in Button(template.name) { report.text = template.text; if report.title.isEmpty { report.title = template.name } } } }
                    TextEditor(text: $report.text).frame(minHeight: 180).accessibilityLabel("Berichtstext")
                    TextField("Verwendetes Material", text: $report.materials, axis: .vertical)
                }
                Section("Baustellenfotos") {
                    ForEach($report.photos) { $photo in
                        VStack(alignment: .leading) {
                            if let image = store.photo(photo) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220) }
                            TextField("Bildbeschreibung", text: $photo.caption)
                        }
                    }.onDelete { report.photos.remove(atOffsets: $0) }
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: max(1, 20 - report.photos.count), matching: .images) { Label("Fotos auswählen", systemImage: "photo.on.rectangle") }.disabled(loadingPhotos || report.photos.count >= 20)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) { Button { takingPhoto = true } label: { Label("Foto aufnehmen", systemImage: "camera") }.disabled(report.photos.count >= 20) }
                    if loadingPhotos { ProgressView("Fotos laden …") }
                }
                Section("Aufmaß") {
                    ForEach(report.measurements) { measurement in
                        VStack(alignment: .leading) { Text(measurement.label); Text("\(measurement.squareMetres.formatted(.number.precision(.fractionLength(2)))) m²").font(.caption).foregroundStyle(.secondary) }
                    }.onDelete { report.measurements.remove(atOffsets: $0) }
                    if !report.measurements.isEmpty { LabeledContent("Gesamtfläche", value: "\(report.measurements.reduce(0) { $0 + $1.squareMetres }.formatted(.number.precision(.fractionLength(2)))) m²") }
                    Button("Aufmaß hinzufügen") { addingMeasurement = true }
                }
                Section("Unterschriften") {
                    TextField("Kundenname", text: $report.customerName)
                    Text("Kunde").font(.caption)
                    SignaturePad(data: $report.customerSignature).frame(height: 130).accessibilityLabel("Kundenunterschrift zeichnen")
                    Button("Kundenunterschrift löschen", role: .destructive) { report.customerSignature = nil }
                    Text("Monteur").font(.caption)
                    SignaturePad(data: $report.workerSignature).frame(height: 130).accessibilityLabel("Monteurunterschrift zeichnen")
                    Button("Monteurunterschrift löschen", role: .destructive) { report.workerSignature = nil }
                }
                Section { Toggle("Bericht abschließen", isOn: $report.completed); Text("Prüfe den Text und das Aufmaß vor dem Abschluss. Für den Abschluss sind Kundenname und beide Unterschriften erforderlich.").font(.caption) }
            }
        }.navigationTitle("Monteurbericht").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Speichern") { if store.save(report: report) { dismiss() } }.disabled(!valid || loadingPhotos) }
            }
            .onAppear { ensureJob() }
            .onChange(of: store.data.jobs.count) { _, _ in ensureJob() }
            .onChange(of: pickerItems) { _, items in
                loadingPhotos = true
                Task { @MainActor in
                    defer { loadingPhotos = false; pickerItems = [] }
                    for item in items {
                        do {
                            guard let bytes = try await item.loadTransferable(type: Data.self), let image = UIImage(data: bytes) else { throw CocoaError(.fileReadCorruptFile) }
                            report.photos.append(try store.addPhoto(image))
                        } catch { store.error = "Foto konnte nicht geladen werden: \(error.localizedDescription)" }
                    }
                }
            }
            .sheet(isPresented: $takingPhoto) { CameraPicker { image in do { report.photos.append(try store.addPhoto(image)) } catch { store.error = error.localizedDescription } } }
            .sheet(isPresented: $addingMeasurement) { NavigationStack { MeasurementEditor { report.measurements.append($0) } } }
            .sheet(isPresented: $addingJob) { NavigationStack { JobEditor(job: Job(title: "", customer: "", address: "")) } }
    }
    private var valid: Bool { store.job(report.jobID) != nil && ![report.title, report.author, report.text].contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    private func ensureJob() { if store.job(report.jobID) == nil, let first = store.data.jobs.first { report.jobID = first.id } }
}

struct ReportDetailView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let reportID: UUID
    @State private var editing = false
    @State private var pdf: URL?
    @State private var confirmingDelete = false
    var body: some View {
        ScrollView {
            if let report = store.data.reports.first(where: { $0.id == reportID }) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(report.title).font(.title2.bold())
                    Text("\(store.job(report.jobID)?.customer ?? "") · \(report.author)").foregroundStyle(.secondary)
                    Text(report.date, style: .date).font(.caption)
                    Text(report.completed ? "Abgeschlossen" : "Entwurf").font(.caption.bold()).foregroundStyle(report.completed ? .green : .secondary)
                    Text(report.text).textSelection(.enabled)
                    if !report.materials.isEmpty { Text("Material").font(.headline); Text(report.materials) }
                    ForEach(report.measurements) { measurement in Text("\(measurement.label): \(measurement.squareMetres.formatted()) m²") }
                    ForEach(report.photos) { photo in
                        if let image = store.photo(photo) { Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12)); Text(photo.caption).font(.caption) }
                    }
                    signature(report.customerSignature, label: "Kunde: \(report.customerName)")
                    signature(report.workerSignature, label: "Monteur: \(report.author)")
                    Button { do { pdf = try PDFService.create(report: report, job: store.job(report.jobID), photo: store.photo) } catch { store.error = error.localizedDescription } } label: { Label("PDF-Bericht erstellen", systemImage: "doc.richtext") }.buttonStyle(.borderedProminent)
                    if let pdf { ShareLink(item: pdf) { Label("PDF teilen / sichern", systemImage: "square.and.arrow.up") } }
                }.padding().frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
            }
        }.navigationTitle("Bericht").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Bearbeiten") { editing = true }; Button(role: .destructive) { confirmingDelete = true } label: { Image(systemName: "trash") } }
            .sheet(isPresented: $editing, onDismiss: { pdf = nil }) { if let report = store.data.reports.first(where: { $0.id == reportID }) { NavigationStack { ReportEditor(report: report) } } }
            .confirmationDialog("Bericht endgültig löschen?", isPresented: $confirmingDelete, titleVisibility: .visible) { Button("Löschen", role: .destructive) { if let report = store.data.reports.first(where: { $0.id == reportID }) { store.delete(report: report); if !store.data.reports.contains(where: { $0.id == reportID }) { dismiss() } } } }
    }
    @ViewBuilder private func signature(_ data: Data?, label: String) -> some View {
        if let data, let image = UIImage(data: data) { Text(label).font(.caption); Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 100) }
    }
}

struct SpeechReportView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var speech = SpeechService()
    @State private var method = 0
    @State private var preview = ""
    @State private var generating = false
    @State private var report: Report?
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Picker("Berichtsmethode", selection: $method) { Label("Sprechen", systemImage: "mic").tag(0); Label("Vorlage", systemImage: "doc.text").tag(1); Label("Manuell", systemImage: "pencil").tag(2) }.pickerStyle(.segmented)
                if method == 0 {
                    Image(systemName: "waveform.circle.fill").font(.system(size: 64)).foregroundStyle(Brand.blue.opacity(0.6))
                    Text("Bericht aufnehmen").font(.headline)
                    Text("Sprich einfach, was du dokumentieren möchtest.").font(.subheadline).multilineTextAlignment(.center)
                    TextEditor(text: $speech.transcript).frame(minHeight: 115).padding(8).background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 10)).accessibilityLabel("Diktierter Text").disabled(speech.recording)
                    Button { if speech.recording { speech.stop() } else { Task { await speech.start() } } } label: { Image(systemName: speech.recording ? "stop.fill" : "mic.fill").font(.title2).frame(width: 58, height: 58).background(.red, in: Circle()).foregroundStyle(.white) }.accessibilityLabel(speech.recording ? "Aufnahme stoppen" : "Aufnahme starten").disabled(speech.preparing)
                    Text(speech.recording ? "Aufnahme läuft · maximal 55 Sekunden" : "Bereit zur Aufnahme").font(.caption)
                    Button("KI-Bericht erstellen") {
                        generating = true
                        Task { @MainActor in defer { generating = false }; do { preview = try await ReportAI.rewrite(speech.transcript) } catch { store.error = error.localizedDescription } }
                    }.buttonStyle(.bordered).disabled(!ReportAI.available || generating || speech.recording || speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if generating { ProgressView("Bericht wird formuliert …") }
                    if !ReportAI.available { Text("Lokale KI nicht verfügbar. Diktat unverändert übernehmen oder bearbeiten.").font(.caption).foregroundStyle(.secondary) }
                    Button("Diktat in Vorschau übernehmen") { preview = speech.transcript }.disabled(speech.recording)
                    Text("Erstellter Bericht (Vorschau)").font(.subheadline.bold()).frame(maxWidth: .infinity, alignment: .leading)
                    TextEditor(text: $preview).frame(minHeight: 160).padding(8).overlay(RoundedRectangle(cornerRadius: 10).stroke(.gray.opacity(0.3))).accessibilityLabel("Berichtsvorschau")
                    Button { report = Report(jobID: store.data.jobs.first?.id ?? UUID(), author: store.data.employee, title: "Monteurbericht", text: preview, materials: "") } label: { Label("Bericht übernehmen", systemImage: "checkmark") }.buttonStyle(.borderedProminent).disabled(preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || speech.recording || generating)
                    Text("Diktate verwenden möglichst lokale Apple-Spracherkennung. Falls nicht verfügbar, kann Apple Audiodaten zur Erkennung verarbeiten.").font(.caption2).foregroundStyle(.secondary)
                } else if method == 1 { TemplatesView().frame(minHeight: 500) }
                else { Button("Manuellen Bericht öffnen") { report = Report(jobID: store.data.jobs.first?.id ?? UUID(), author: store.data.employee, title: "", text: "", materials: "") } }
            }.padding().frame(maxWidth: 600).frame(maxWidth: .infinity)
        }.navigationTitle("Monteurbericht").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $report) { report in NavigationStack { ReportEditor(report: report) } }
            .onDisappear { speech.cancel() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { speech.stop() } }
            .onChange(of: method) { _, _ in speech.stop() }
            .alert("Spracheingabe", isPresented: Binding(get: { speech.error != nil }, set: { if !$0 { speech.error = nil } })) { Button("OK") { speech.error = nil } } message: { Text(speech.error ?? "") }
    }
}

struct PhotoLibraryView: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        List {
            Section { NavigationLink("Bericht mit Fotos erstellen") { ReportEditor(report: Report(jobID: store.data.jobs.first?.id ?? UUID(), author: store.data.employee, title: "Fotodokumentation", text: "", materials: "")) } }
            ForEach(store.data.reports.filter { !$0.photos.isEmpty }) { report in
                Section(report.title) { ForEach(report.photos) { photo in if let image = store.photo(photo) { Image(uiImage: image).resizable().scaledToFit(); Text(photo.caption).font(.caption) } }; NavigationLink("Bericht öffnen") { ReportDetailView(reportID: report.id) } }
            }
        }.navigationTitle("Baustellenfotos")
    }
}
