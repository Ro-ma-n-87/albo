import XCTest
import PDFKit
import UIKit
@testable import ALBOConnect

final class StoreTests: XCTestCase {
    @MainActor func testPausedClockSurvivesRelaunchAndKeepsActualEndTime() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = Store(directory: directory)
        let job = Job(title: "Wartung", customer: "Testkunde", address: "Teststraße 1")
        XCTAssertTrue(store.save(job: job))
        let start = Date(timeIntervalSince1970: 10000)
        store.start(jobID: job.id, now: start)
        store.togglePause(now: start.addingTimeInterval(600))
        let reopened = Store(directory: directory)
        XCTAssertEqual(reopened.currentClock?.elapsed(at: start.addingTimeInterval(900)), 600)
        reopened.togglePause(now: start.addingTimeInterval(900))
        reopened.stop(now: start.addingTimeInterval(1200))
        let entry = try XCTUnwrap(reopened.data.entries.first)
        XCTAssertEqual(entry.seconds, 900)
        XCTAssertEqual(entry.end, start.addingTimeInterval(1200))
        XCTAssertNil(reopened.currentClock)
        XCTAssertEqual(Store(directory: directory).data.entries.first?.seconds, 900)
    }
    @MainActor func testIndependentEmployeeClocksAndTimeOverlapValidation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = Store(directory: directory)
        let job = Job(title: "Wartung", customer: "Test", address: "Test")
        XCTAssertTrue(store.save(job: job))
        XCTAssertTrue(store.save(employee: Employee(name: "Marco")))
        let start = Date(timeIntervalSince1970: 10000)
        store.start(jobID: job.id, now: start)
        store.saveEmployee("Marco")
        XCTAssertNil(store.currentClock)
        store.start(jobID: job.id, now: start)
        store.stop(now: start.addingTimeInterval(300))
        store.saveEmployee("Salvatore")
        XCTAssertNotNil(store.currentClock)
        store.stop(now: start.addingTimeInterval(600))
        XCTAssertEqual(store.data.entries.count, 2)
        XCTAssertFalse(store.addEntry(jobID: job.id, start: start.addingTimeInterval(1), end: start.addingTimeInterval(10)))
        XCTAssertTrue(store.addEntry(jobID: job.id, start: start.addingTimeInterval(600), end: start.addingTimeInterval(700)))
    }
    @MainActor func testCorruptDatabaseIsNotOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("database.json"), bytes = Data("corrupt".utf8)
        try bytes.write(to: file)
        let store = Store(directory: directory)
        XCTAssertFalse(store.save(job: Job(title: "X", customer: "Y", address: "Z")))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    @MainActor func testBackupRoundTripContainsPhotosAndSignatures() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let imported = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: imported) }
        let store = Store(directory: directory), job = Job(title: "Test", customer: "Kunde", address: "Adresse")
        XCTAssertTrue(store.save(job: job))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 70)).image { context in UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 70)) }
        let photo = try store.addPhoto(image)
        let report = Report(jobID: job.id, author: "Salvatore", title: "Wartung", text: "Brenner gereinigt.", materials: "", photos: [photo], customerName: "Kunde", workerSignature: image.pngData(), customerSignature: image.pngData(), completed: true)
        XCTAssertTrue(store.save(report: report))
        let backup = try store.backupURL()
        defer { try? FileManager.default.removeItem(at: backup) }
        let other = Store(directory: imported)
        try other.importBackup(from: backup)
        let restored = try XCTUnwrap(other.data.reports.first)
        XCTAssertEqual(restored.text, report.text)
        XCTAssertEqual(restored.customerSignature, report.customerSignature)
        XCTAssertNotNil(other.photo(try XCTUnwrap(restored.photos.first)))
        XCTAssertTrue(other.data.clocks?.isEmpty ?? true)
    }
    @MainActor func testPDFHasMultiplePagesForLongReportAndPreservesGermanText() throws {
        let report = Report(jobID: UUID(), author: "Salvatore", title: "Wartung Müller", text: String(repeating: "Ölheizung geprüft, Brenner gereinigt.\n", count: 180), materials: "Ölfilter")
        let url = try PDFService.create(report: report, job: nil, photo: { _ in nil })
        defer { try? FileManager.default.removeItem(at: url) }
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThan(pdf.pageCount, 1)
        XCTAssertTrue(pdf.string?.contains("Ölheizung") ?? false)
        XCTAssertTrue(pdf.string?.contains("Ölfilter") ?? false)
    }
    func testMeasurementAcceptsGermanDecimalsAndRejectsInvalidNumbers() {
        XCTAssertEqual(InputNumber.decimal(" 3,5 "), 3.5)
        XCTAssertNil(InputNumber.decimal("NaN")); XCTAssertNil(InputNumber.decimal("inf")); XCTAssertNil(InputNumber.decimal("-1")); XCTAssertNil(InputNumber.decimal("0"))
        XCTAssertEqual(Measurement(label: "Bad", length: 3.5, width: 2.4, quantity: 2).squareMetres, 16.8, accuracy: 0.0001)
    }
    func testPCConnectionRejectsPublicHTTPAndEmbeddedCredentials() throws {
        XCTAssertEqual(try PCSync.serverURL("http://192.168.1.20:8787").host, "192.168.1.20")
        XCTAssertEqual(try PCSync.serverURL("https://buero.example.de").scheme, "https")
        XCTAssertThrowsError(try PCSync.serverURL("http://example.com"))
        XCTAssertThrowsError(try PCSync.serverURL("https://user:password@example.com"))
        XCTAssertThrowsError(try PCSync.serverURL("https://example.com/?token=secret"))
    }
    func testVPNAddressesRequireExplicitPrivateVPNMode() throws {
        XCTAssertThrowsError(try PCSync.serverURL("http://100.80.10.20:8788"))
        XCTAssertEqual(try PCSync.serverURL("http://100.80.10.20:8788", privateVPN: true).host, "100.80.10.20")
        XCTAssertThrowsError(try PCSync.serverURL("http://100.63.255.255:8788", privateVPN: true))
        XCTAssertThrowsError(try PCSync.serverURL("http://100.128.0.1:8788", privateVPN: true))
        XCTAssertThrowsError(try PCSync.serverURL("http://example.com", privateVPN: true))
        XCTAssertThrowsError(try PCSync.serverURL("http://100.80.10.999:8788", privateVPN: true))
        XCTAssertThrowsError(try PCSync.serverURL("http://100.80.fake.10.20:8788", privateVPN: true))
        XCTAssertThrowsError(try PCSync.serverURL("http://192.168.fake.1.20:8787"))
    }
}
