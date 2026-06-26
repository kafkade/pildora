import Foundation

// MARK: - PDF Report Content

/// Platform-independent description of the Doctor Mode report. Building the
/// content is separated from rendering so it can be unit-tested on any platform
/// and rendered to PDF only where UIKit is available.
public struct DoctorReport: Equatable {
    public struct Line: Equatable {
        public enum Style: Equatable { case title, heading, body, caption }
        public var text: String
        public var style: Style
        public init(_ text: String, _ style: Style) {
            self.text = text
            self.style = style
        }
    }

    public var lines: [Line]

    /// Build the report from current store state.
    @MainActor
    public static func build(from store: MedicationStore, now: Date = Date()) -> DoctorReport {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short

        var lines: [Line] = []
        lines.append(.init("Pildora — Medication Summary", .title))
        lines.append(.init("Generated \(dateFormatter.string(from: now))", .caption))
        lines.append(.init(DrugReference.disclaimer, .caption))

        // Always report the full medication set, independent of any active search filter.
        for section in MedicationStore.group(store.medications) {
            guard !section.medications.isEmpty else { continue }
            lines.append(.init(section.category.displayName, .heading))
            for med in section.medications {
                lines.append(.init(med.titleWithDosage, .body))
                var detail = "\(med.form.displayName) · \(med.frequency)"
                if let prescriber = med.prescriber {
                    detail += " · \(prescriber)"
                }
                lines.append(.init(detail, .caption))
                if let inv = store.inventory(for: med.id) {
                    lines.append(.init("Inventory: \(inv.currentCount) remaining (refill at \(inv.refillThreshold))", .caption))
                }
                if let ref = store.reference(for: med) {
                    lines.append(.init("Class: \(ref.drugClass)", .caption))
                    lines.append(.init(ref.attribution(), .caption))
                }
            }
        }
        return DoctorReport(lines: lines)
    }

    /// A plain-text rendering, used as a fallback (and for tests) when PDF
    /// rendering is unavailable.
    public var plainText: String {
        lines.map { line in
            switch line.style {
            case .title: return line.text.uppercased()
            case .heading: return "\n\(line.text)\n" + String(repeating: "-", count: line.text.count)
            case .body: return line.text
            case .caption: return "  \(line.text)"
            }
        }.joined(separator: "\n")
    }
}

// MARK: - PDF Renderer

/// Renders a `DoctorReport` to PDF **entirely on-device** (Doctor Mode).
public enum PDFReportRenderer {

    /// Render the report to PDF data. On platforms without UIKit (e.g. the
    /// macOS toolchain build), returns a UTF-8 plain-text fallback so the API
    /// is always available; callers should treat the bytes opaquely.
    public static func render(_ report: DoctorReport) -> Data {
        #if canImport(UIKit)
        return renderPDF(report)
        #else
        return Data(report.plainText.utf8)
        #endif
    }
}

#if canImport(UIKit)
import UIKit

extension PDFReportRenderer {
    private static func renderPDF(_ report: DoctorReport) -> Data {
        // US Letter at 72 dpi.
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 48
        let contentWidth = pageRect.width - margin * 2
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        return renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = margin

            for line in report.lines {
                let attributes = attributes(for: line.style)
                let bounding = (line.text as NSString).boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                )
                let spacingBefore: CGFloat = line.style == .heading ? 12 : 2
                if y + bounding.height + spacingBefore > pageRect.height - margin {
                    context.beginPage()
                    y = margin
                }
                y += spacingBefore
                (line.text as NSString).draw(
                    in: CGRect(x: margin, y: y, width: contentWidth, height: bounding.height),
                    withAttributes: attributes
                )
                y += bounding.height
            }
        }
    }

    private static func attributes(for style: DoctorReport.Line.Style) -> [NSAttributedString.Key: Any] {
        switch style {
        case .title:
            return [.font: UIFont.boldSystemFont(ofSize: 22)]
        case .heading:
            return [.font: UIFont.boldSystemFont(ofSize: 15)]
        case .body:
            return [.font: UIFont.systemFont(ofSize: 12, weight: .medium)]
        case .caption:
            return [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor.darkGray,
            ]
        }
    }
}
#endif
