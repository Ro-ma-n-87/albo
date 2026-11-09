import SwiftUI

struct TimeView: View {
    @EnvironmentObject private var store: Store
    @State private var selectedJob: UUID?
    @State private var manual = false
    var body: some View {
        List {
            Section(store.data.employee) {
                if let clock = store.currentClock {
                    Text(store.job(clock.jobID)?.customer ?? "Baustelle").font(.headline)
                    TimelineView(.periodic(from: .now, by: 1)) { context in Text(durationText(clock.elapsed(at: context.date))).font(.system(size: 40, weight: .semibold, design: .monospaced)).frame(maxWidth: .infinity) }
                    Text(clock.segmentStart == nil ? "Pausiert" : "Arbeitszeit läuft").foregroundStyle(.secondary)
                    HStack { Button(clock.segmentStart == nil ? "Fortsetzen" : "Pause") { store.togglePause() }.buttonStyle(.borderedProminent); Button("Beenden") { store.stop() }.buttonStyle(.bordered) }
                } else {
                    Picker("Baustelle", selection: $selectedJob) { Text("Bitte wählen").tag(nil as UUID?); ForEach(store.data.jobs) { Text("\($0.customer) · \($0.title)").tag(Optional($0.id)) } }
                    Button("Arbeitszeit starten") { if let selectedJob { store.start(jobID: selectedJob) } }.disabled(selectedJob == nil)
                }
            }
            Section("Gespeicherte Zeiten") {
                ForEach(store.data.entries.filter { ($0.employee ?? store.data.employee) == store.data.employee }) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.job(entry.jobID)?.customer ?? "Baustelle").font(.headline)
                        Text(entry.start, style: .date).font(.caption)
                        Text("\(entry.start.formatted(date: .omitted, time: .shortened)) – \(entry.end.formatted(date: .omitted, time: .shortened)) · Netto \(durationText(entry.seconds))").font(.caption).monospacedDigit()
                    }.swipeActions { Button("Löschen", role: .destructive) { store.deleteEntry(entry.id) } }
                }
            }
        }.navigationTitle("Arbeitszeit").toolbar { Button("Nachtragen") { manual = true }.disabled(store.currentClock != nil) }
            .onAppear { if selectedJob == nil { selectedJob = store.data.jobs.first?.id } }
            .sheet(isPresented: $manual) { NavigationStack { ManualTimeView() } }
    }
}
struct ManualTimeView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var jobID: UUID?
    @State private var start = Date().addingTimeInterval(-3600)
    @State private var end = Date()
    var body: some View {
        Form {
            Picker("Baustelle", selection: $jobID) { Text("Bitte wählen").tag(nil as UUID?); ForEach(store.data.jobs) { Text($0.customer).tag(Optional($0.id)) } }
            DatePicker("Beginn", selection: $start)
            DatePicker("Ende", selection: $end)
        }.navigationTitle("Arbeitszeit nachtragen").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Speichern") { if let jobID, store.addEntry(jobID: jobID, start: start, end: end) { dismiss() } }.disabled(jobID == nil || end <= start) } }.onAppear { jobID = store.data.jobs.first?.id }
    }
}

struct MeasurementEditor: View {
    @Environment(\.dismiss) private var dismiss
    var receive: (Measurement) -> Void
    @State private var label = ""
    @State private var length = ""
    @State private var width = ""
    @State private var quantity = 1
    private var area: Double? {
        guard let length = InputNumber.decimal(length), let width = InputNumber.decimal(width) else { return nil }
        let area = length * width * Double(quantity); return area.isFinite ? area : nil
    }
    var body: some View {
        Form {
            TextField("Bezeichnung", text: $label)
            TextField("Länge in Metern", text: $length).keyboardType(.decimalPad)
            TextField("Breite in Metern", text: $width).keyboardType(.decimalPad)
            Stepper("Anzahl: \(quantity)", value: $quantity, in: 1...999)
            if let area { LabeledContent("Fläche", value: "\(area.formatted(.number.precision(.fractionLength(2)))) m²") }
            else { Text("Bitte positive Maße eingeben.").foregroundStyle(.secondary) }
        }.navigationTitle("Aufmaß").toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Übernehmen") { if let length = InputNumber.decimal(length), let width = InputNumber.decimal(width) { receive(Measurement(label: label, length: length, width: width, quantity: quantity)); dismiss() } }.disabled(area == nil || label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }
    }
}
struct MeasurementStartView: View {
    @EnvironmentObject private var store: Store
    @State private var measurements: [Measurement] = []
    @State private var adding = false
    @State private var report: Report?
    var body: some View {
        List {
            ForEach(measurements) { measurement in LabeledContent(measurement.label, value: "\(measurement.squareMetres.formatted()) m²") }.onDelete { measurements.remove(atOffsets: $0) }
            LabeledContent("Gesamt", value: "\(measurements.reduce(0) { $0 + $1.squareMetres }.formatted()) m²")
            Button("Position hinzufügen") { adding = true }
            Button("In Bericht übernehmen") { report = Report(jobID: store.data.jobs.first?.id ?? UUID(), author: store.data.employee, title: "Aufmaß", text: "", materials: "", measurements: measurements) }.disabled(measurements.isEmpty)
        }.navigationTitle("Aufmaß").sheet(isPresented: $adding) { NavigationStack { MeasurementEditor { measurements.append($0) } } }
            .sheet(item: $report) { report in NavigationStack { ReportEditor(report: report) } }
    }
}

struct TemplatesView: View {
    @EnvironmentObject private var store: Store
    @State private var editing: ReportTemplate?
    @State private var report: Report?
    var body: some View {
        List {
            ForEach(store.data.templates) { template in
                VStack(alignment: .leading, spacing: 10) {
                    Text(template.name).font(.headline)
                    Text(template.text).font(.caption).lineLimit(3).foregroundStyle(.secondary)
                    HStack {
                        Button("Vorlage nutzen") { report = Report(jobID: store.data.jobs.first?.id ?? UUID(), author: store.data.employee, title: template.name, text: template.text, materials: "") }.buttonStyle(.borderedProminent)
                        Button("Bearbeiten") { editing = template }.buttonStyle(.bordered).disabled(!store.canManage)
                    }
                }.padding(.vertical, 5)
            }.onDelete(perform: store.deleteTemplates)
        }.navigationTitle("Berichtsvorlagen").toolbar { Button { editing = ReportTemplate(name: "", text: "") } label: { Label("Neue Vorlage", systemImage: "plus") }.disabled(!store.canManage) }
            .sheet(item: $editing) { template in NavigationStack { TemplateEditor(template: template) } }
            .sheet(item: $report) { report in NavigationStack { ReportEditor(report: report) } }
    }
}
struct TemplateEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var template: ReportTemplate
    var body: some View {
        Form { TextField("Vorlagenname", text: $template.name); TextEditor(text: $template.text).frame(minHeight: 240).accessibilityLabel("Vorlagentext") }
            .navigationTitle("Vorlage").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Speichern") { if store.saveTemplate(template) { dismiss() } }.disabled(template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || template.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
    }
}
