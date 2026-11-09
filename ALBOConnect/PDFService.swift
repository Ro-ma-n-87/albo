import UIKit

enum PDFService {
    @MainActor static func create(report: Report, job: Job?, photo: (SitePhoto) -> UIImage?) throws -> URL {
        let bounds = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: report.title, kCGPDFContextCreator as String: "ALBO Connect"]
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)
        let data = renderer.pdfData { context in
            let left: CGFloat = 44, width: CGFloat = bounds.width - 88
            var y: CGFloat = 100
            var page = 0
            func startPage() {
                context.beginPage(); page += 1; y = 106
                ("ALBO Connect" as NSString).draw(at: CGPoint(x: left, y: 35), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 22), .foregroundColor: UIColor.systemBlue])
                ("Sanitär & Heizung · Monteurbericht" as NSString).draw(at: CGPoint(x: left, y: 66), withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.darkGray])
                ("ALBO Connect · Seite \(page)" as NSString).draw(at: CGPoint(x: left, y: 806), withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.darkGray])
            }
            func ensure(_ height: CGFloat) { if y + height > 775 { startPage() } }
            func line(_ text: String, size: CGFloat = 11, bold: Bool = false) {
                let attributes: [NSAttributedString.Key: Any] = [.font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.black]
                for paragraph in text.components(separatedBy: .newlines) {
                    var current = ""
                    // Character wrapping also handles very long unbroken text.
                    for char in paragraph {
                        let candidate = current + String(char)
                        if (candidate as NSString).size(withAttributes: attributes).width > width, !current.isEmpty {
                            ensure(size + 7); (current as NSString).draw(at: CGPoint(x: left, y: y), withAttributes: attributes); y += size + 6; current = String(char)
                        } else { current = candidate }
                    }
                    ensure(size + 7); (current as NSString).draw(at: CGPoint(x: left, y: y), withAttributes: attributes); y += size + 6
                }
                y += 4
            }
            func heading(_ text: String) { ensure(45); y += 10; line(text, size: 13, bold: true) }
            func drawImage(_ image: UIImage, maxHeight: CGFloat) {
                guard image.size.width > 0, image.size.height > 0 else { return }
                let scale = min(width / image.size.width, maxHeight / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                ensure(size.height + 18); image.draw(in: CGRect(x: left, y: y, width: size.width, height: size.height)); y += size.height + 16
            }
            startPage()
            line(report.title, size: 18, bold: true)
            line("\(report.completed ? "Abgeschlossen" : "Entwurf") · \(report.date.formatted(date: .numeric, time: .omitted))")
            heading("Baustelle / Kunde")
            line([job?.customer, job?.title, job?.address].compactMap { $0 }.joined(separator: "\n"))
            line("Monteur: \(report.author)")
            heading("Durchgeführte Arbeiten"); line(report.text)
            if !report.materials.isEmpty { heading("Verwendetes Material"); line(report.materials) }
            if !report.measurements.isEmpty {
                heading("Aufmaß")
                for measurement in report.measurements { line("\(measurement.label): \(measurement.length.formatted()) × \(measurement.width.formatted()) m × \(measurement.quantity) = \(measurement.squareMetres.formatted()) m²") }
                line("Gesamt: \(report.measurements.reduce(0) { $0 + $1.squareMetres }.formatted()) m²", bold: true)
            }
            for attachment in report.photos {
                if let image = photo(attachment) { heading("Baustellenfoto"); drawImage(image, maxHeight: 310); if !attachment.caption.isEmpty { line(attachment.caption) } }
            }
            if let bytes = report.customerSignature, let image = UIImage(data: bytes) { heading("Unterschrift Kunde: \(report.customerName)"); drawImage(image, maxHeight: 90) }
            if let bytes = report.workerSignature, let image = UIImage(data: bytes) { heading("Unterschrift Monteur: \(report.author)"); drawImage(image, maxHeight: 90) }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ALBO-Bericht-\(UUID().uuidString).pdf")
        try data.write(to: url, options: [.atomic, .completeFileProtection]); return url
    }
}
