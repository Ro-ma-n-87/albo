import SwiftUI
import UIKit

struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var receive: (UIImage) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera; picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.receive(image) }; parent.dismiss()
        }
    }
}

struct SignaturePad: UIViewRepresentable {
    @Binding var data: Data?
    func makeUIView(context: Context) -> SignatureCanvas { let view = SignatureCanvas(); view.backgroundColor = .white; view.layer.cornerRadius = 10; view.layer.borderWidth = 1; view.layer.borderColor = UIColor.systemGray4.cgColor; return view }
    func updateUIView(_ view: SignatureCanvas, context: Context) {
        view.changed = { data = $0 }
        if view.lastData != data { view.lastData = data; view.image = data.flatMap { UIImage(data: $0) }; view.path.removeAllPoints(); view.setNeedsDisplay() }
    }
}
final class SignatureCanvas: UIView {
    var image: UIImage?
    var lastData: Data?
    var changed: ((Data?) -> Void)?
    let path = UIBezierPath()
    override func draw(_ rect: CGRect) { image?.draw(in: bounds); UIColor.black.setStroke(); path.lineWidth = 2; path.lineCapStyle = .round; path.stroke() }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { guard let point = touches.first?.location(in: self) else { return }; path.move(to: point); path.addLine(to: CGPoint(x: point.x + 0.1, y: point.y + 0.1)); setNeedsDisplay() }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { if let point = touches.first?.location(in: self) { path.addLine(to: point); setNeedsDisplay() } }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        image = UIGraphicsImageRenderer(bounds: bounds).image { _ in UIColor.white.setFill(); UIRectFill(bounds); image?.draw(in: bounds); UIColor.black.setStroke(); path.stroke() }
        path.removeAllPoints(); lastData = image?.pngData(); changed?(lastData); setNeedsDisplay()
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { path.removeAllPoints(); setNeedsDisplay() }
}
