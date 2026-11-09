import SwiftUI

private enum AdminPage: String, CaseIterable, Identifiable {
    case overview = "Übersicht", jobs = "Baustellen", reports = "Berichte", times = "Zeiterfassung", templates = "Vorlagen", customers = "Kunden", employees = "Mitarbeiter"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .overview: "house"; case .jobs: "building.2"; case .reports: "doc.text"; case .times: "clock"; case .templates: "list.clipboard"; case .customers: "person.crop.square"; case .employees: "person.2" }
    }
}
struct AdminView: View {
    @State private var selection: AdminPage? = .overview
    var body: some View {
        NavigationSplitView {
            List(AdminPage.allCases, selection: $selection) { page in Label(page.rawValue, systemImage: page.symbol).tag(page) }.navigationTitle("ALBO Connect")
        } detail: {
            NavigationStack {
                switch selection ?? .overview {
                case .overview: AdminOverview()
                case .jobs: JobsView()
                case .reports: ReportsView()
                case .times: AdminTimesView()
                case .templates: TemplatesView()
                case .customers: CustomersView()
                case .employees: EmployeesView()
                }
            }
        }.navigationTitle("Verwaltung").navigationBarTitleDisplayMode(.inline)
    }
}
struct AdminOverview: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 12) {
                    stat("Aktive Baustellen", store.data.jobs.filter { $0.status != .done }.count, "building.2")
                    stat("Offene Berichte", store.data.reports.filter { !$0.completed }.count, "doc.text")
                    stat("Aktive Mitarbeiter", store.employees.filter(\.active).count, "person.2")
                    stat("Abgeschlossene Berichte", store.data.reports.filter(\.completed).count, "checkmark.circle")
                }.padding(.vertical, 8)
            }
            Section("Aktuelle Baustellen") { ForEach(store.data.jobs.filter { $0.status != .done }) { job in NavigationLink { JobDetailView(jobID: job.id) } label: { JobRow(job: job) } } }
            Section("Letzte Berichte") { ForEach(Array(store.data.reports.prefix(8))) { report in NavigationLink { ReportDetailView(reportID: report.id) } label: { ReportRow(report: report) } } }
        }.navigationTitle("Übersicht")
    }
    private func stat(_ title: String, _ number: Int, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Image(systemName: symbol).foregroundStyle(Brand.blue); Text(title).font(.caption); Text(number.formatted()).font(.title.bold()) }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct AdminTimesView: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        List {
            Section("Laufende Erfassung") {
                ForEach((store.data.clocks ?? [:]).keys.sorted(), id: \.self) { name in
                    if let clock = store.data.clocks?[name] {
                        VStack(alignment: .leading) { Text(name).font(.headline); Text(store.job(clock.jobID)?.customer ?? ""); TimelineView(.periodic(from: .now, by: 1)) { context in Text("\(clock.segmentStart == nil ? "Pause" : "In Arbeit") · \(durationText(clock.elapsed(at: context.date)))").font(.caption).monospacedDigit() } }
                    }
                }
            }
            Section("Gespeicherte Arbeitszeiten") {
                ForEach(store.data.entries) { entry in
                    VStack(alignment: .leading, spacing: 5) { Text(entry.employee ?? "Monteur").font(.headline); Text(store.job(entry.jobID)?.customer ?? "Baustelle"); HStack { Text(entry.start, style: .date); Spacer(); Text(durationText(entry.seconds)).monospacedDigit() }.font(.caption) }
                }
            }
        }.navigationTitle("Zeiterfassung")
    }
}
struct EmployeesView: View {
    @EnvironmentObject private var store: Store
    @State private var editing: Employee?
    var body: some View {
        List(store.employees) { employee in
            Button { editing = employee } label: { VStack(alignment: .leading, spacing: 4) { Text(employee.name).foregroundStyle(.primary); Text("\(employee.role) · \(employee.active ? "Aktiv" : "Inaktiv")").font(.caption).foregroundStyle(.secondary) } }
        }.navigationTitle("Mitarbeiter").toolbar { Button { editing = Employee(name: "") } label: { Label("Mitarbeiter anlegen", systemImage: "plus") } }
            .sheet(item: $editing) { employee in NavigationStack { EmployeeEditor(employee: employee) } }
    }
}
struct EmployeeEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var employee: Employee
    var body: some View {
        Form { TextField("Name", text: $employee.name); Picker("Rolle", selection: $employee.role) { Text("Monteur").tag("Monteur"); Text("Verwaltung").tag("Verwaltung"); Text("Geschäftsleitung").tag("Geschäftsleitung") }; Toggle("Aktiv", isOn: $employee.active) }
            .navigationTitle("Mitarbeiter").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Speichern") { employee.name = employee.name.trimmingCharacters(in: .whitespacesAndNewlines); if store.save(employee: employee) { dismiss() } }.disabled(employee.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
    }
}
struct CustomersView: View {
    @EnvironmentObject private var store: Store
    @State private var editing: Customer?
    var body: some View {
        List {
            if store.customers.isEmpty { Text("Noch keine Kunden im Kundenverzeichnis.").foregroundStyle(.secondary) }
            ForEach(store.customers) { customer in Button { editing = customer } label: { VStack(alignment: .leading, spacing: 5) { Text(customer.name).font(.headline).foregroundStyle(.primary); Text(customer.address).font(.caption).foregroundStyle(.secondary) } } }
        }.navigationTitle("Kunden").toolbar { Button { editing = Customer(name: "", address: "") } label: { Label("Kunde anlegen", systemImage: "plus") } }
            .sheet(item: $editing) { customer in NavigationStack { CustomerEditor(customer: customer) } }
    }
}
struct CustomerEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var customer: Customer
    var body: some View {
        Form { TextField("Kundenname", text: $customer.name); TextField("Adresse", text: $customer.address); TextField("Telefon", text: $customer.phone).keyboardType(.phonePad); TextField("E-Mail", text: $customer.email).keyboardType(.emailAddress).textInputAutocapitalization(.never) }
            .navigationTitle("Kunde").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Speichern") { if store.save(customer: customer) { dismiss() } }.disabled(customer.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || customer.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
    }
}
