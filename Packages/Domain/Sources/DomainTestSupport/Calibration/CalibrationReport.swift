import Foundation

/// Markdown tables of calibration results, ready to paste into the ticket's implementation notes.
public enum CalibrationReport {
    /// `| threshold | precision | recall | TP | FP | FN |`, one row per point.
    public static func curveTable(_ curve: [CurvePoint]) -> String {
        var lines = [
            "| Threshold | Precision | Recall | TP | FP | FN |",
            "|---:|---:|---:|---:|---:|---:|"
        ]
        for point in curve {
            let score = point.score
            let cells = [
                String(format: "%.3f", Double(point.threshold)),
                percent(score.precision),
                percent(score.recall),
                "\(score.truePositives)",
                "\(score.falsePositives)",
                "\(score.falseNegatives)"
            ]
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `| gap | labelled pairs | split pairs | recall ceiling |`, one row per gap.
    public static func sessionGapTable(_ splits: [SessionGapSplit]) -> String {
        var lines = [
            "| Session gap | Labelled pairs | Split pairs | Recall ceiling |",
            "|---:|---:|---:|---:|"
        ]
        for split in splits {
            let cells = [
                String(format: "%g min", split.gap / 60),
                "\(split.labelledPairs)",
                "\(split.splitPairs)",
                percent(split.recallCeiling)
            ]
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Photos and groups per category: `| category | photos | groups |`.
    public static func coverageTable(_ fixture: CalibrationFixture) -> String {
        var lines = ["| Category | Photos | Groups |", "|---|---:|---:|"]
        for category in CalibrationCategory.allCases {
            let photos = fixture.photos.filter { $0.category == category }
            lines.append("| \(category.rawValue) | \(photos.count) | \(Set(photos.map(\.group)).count) |")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.1f %%", value * 100)
    }
}
