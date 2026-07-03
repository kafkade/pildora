import Foundation

/// Renders a ``RecoveryDocument`` to a shareable/printable PDF.
///
/// Mirrors the pattern used by the medication export (`PDFReportRenderer`): the
/// UIKit rendering path produces a real US-Letter PDF; on platforms without
/// UIKit (e.g. the macOS `swift test` build) it falls back to UTF-8 plain text
/// so the API is always available and unit-testable.
public enum RecoveryKitPDFRenderer {

    /// Render `document` to PDF bytes (or plain-text bytes where UIKit is
    /// unavailable). Callers should treat the returned bytes opaquely.
    public static func render(_ document: RecoveryDocument) -> Data {
        #if canImport(UIKit)
        return renderPDF(document)
        #else
        return Data(document.plainText.utf8)
        #endif
    }
}

#if canImport(UIKit)
import UIKit

extension RecoveryKitPDFRenderer {
    private static func renderPDF(_ document: RecoveryDocument) -> Data {
        // US Letter at 72 dpi.
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 56
        let contentWidth = pageRect.width - margin * 2
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        return renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = margin

            func draw(_ text: String, font: UIFont, color: UIColor = .black, spacingBefore: CGFloat = 6) {
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let bounding = (text as NSString).boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs,
                    context: nil
                )
                if y + bounding.height + spacingBefore > pageRect.height - margin {
                    context.beginPage()
                    y = margin
                }
                y += spacingBefore
                (text as NSString).draw(
                    in: CGRect(x: margin, y: y, width: contentWidth, height: bounding.height),
                    withAttributes: attrs
                )
                y += bounding.height
            }

            // Header
            draw(document.appName, font: .systemFont(ofSize: 13, weight: .semibold),
                 color: .darkGray, spacingBefore: 0)
            draw(document.title, font: .boldSystemFont(ofSize: 26), spacingBefore: 2)
            draw("Vault: \(document.vaultName)", font: .systemFont(ofSize: 12), color: .darkGray)
            draw("Generated \(document.generatedOn)", font: .systemFont(ofSize: 10), color: .gray)

            // Recovery key box
            y += 20
            draw("YOUR RECOVERY KEY", font: .boldSystemFont(ofSize: 11), color: .darkGray)
            let keyFont = UIFont.monospacedSystemFont(ofSize: 16, weight: .semibold)
            let keyAttrs: [NSAttributedString.Key: Any] = [.font: keyFont]
            let keyBounding = (document.recoveryKey as NSString).boundingRect(
                with: CGSize(width: contentWidth - 32, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: keyAttrs,
                context: nil
            )
            let boxHeight = keyBounding.height + 28
            let boxRect = CGRect(x: margin, y: y + 6, width: contentWidth, height: boxHeight)
            let boxPath = UIBezierPath(roundedRect: boxRect, cornerRadius: 8)
            UIColor(white: 0.96, alpha: 1).setFill()
            boxPath.fill()
            UIColor(white: 0.7, alpha: 1).setStroke()
            boxPath.lineWidth = 1
            boxPath.stroke()
            (document.recoveryKey as NSString).draw(
                in: CGRect(x: margin + 16, y: y + 20, width: contentWidth - 32, height: keyBounding.height),
                withAttributes: keyAttrs
            )
            y += boxHeight + 12

            // Instructions
            y += 8
            for (index, step) in document.instructions.enumerated() {
                draw("\(index + 1).  \(step)", font: .systemFont(ofSize: 11), spacingBefore: 8)
            }

            // Warning
            y += 12
            draw("⚠︎  \(document.warning)", font: .boldSystemFont(ofSize: 12),
                 color: UIColor(red: 0.6, green: 0.05, blue: 0.07, alpha: 1), spacingBefore: 8)
        }
    }
}
#endif
