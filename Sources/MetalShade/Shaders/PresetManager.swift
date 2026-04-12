import Foundation

/// Reads and writes ReShade-compatible preset .ini files.
///
/// Format:
///   Techniques=ShaderA,ShaderB
///
///   [ShaderA.fx]
///   param1=0.500000
///   param2=1.000000
///
///   [ShaderB.fx]
///   intensity=0.300000
struct PresetManager {

    // MARK: - Load

    struct LoadedPreset {
        /// Names of enabled techniques (as they appear after "Techniques=")
        let enabledTechniques: [String]
        /// Map from section name (e.g. "LumaSharpen.fx") → (paramName → value)
        let params: [String: [String: Float]]
    }

    static func load(from url: URL) -> (preset: LoadedPreset?, error: String?) {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return (nil, "Не удалось прочитать файл \(url.lastPathComponent)")
        }
        return (parse(raw), nil)
    }

    private static func parse(_ text: String) -> LoadedPreset {
        var enabledTechniques: [String]         = []
        var params:            [String: [String: Float]] = [:]
        var currentSection:    String?           = nil

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }

            // Section header [Name]
            if line.hasPrefix("[") && line.hasSuffix("]") {
                currentSection = String(line.dropFirst().dropLast())
                continue
            }

            // Key=Value
            guard let eqIdx = line.firstIndex(of: "=") else { continue }
            let key   = String(line[line.startIndex..<eqIdx]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)

            if currentSection == nil {
                // Global section
                if key == "Techniques" || key == "TechniquesAlreadyOrdered" {
                    if key == "Techniques" {
                        enabledTechniques = value
                            .components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    }
                }
            } else if let section = currentSection {
                if let floatVal = Float(value) {
                    params[section, default: [:]][key] = floatVal
                }
            }
        }

        return LoadedPreset(enabledTechniques: enabledTechniques, params: params)
    }

    // MARK: - Save

    static func save(effects: [ShaderEffect], to url: URL) -> String? {
        var lines: [String] = []

        // Techniques line
        let enabled = effects.filter { $0.isEnabled }.map { $0.name }
        lines.append("Techniques=\(enabled.joined(separator: ","))")
        lines.append("TechniquesAlreadyOrdered=\(enabled.joined(separator: ","))")
        lines.append("")

        // Per-effect sections
        for effect in effects {
            let sectionName = effect.isCustom ? "\(effect.name).fx" : "\(effect.name).fx"
            lines.append("[\(sectionName)]")
            for param in effect.params {
                lines.append("\(param.name)=\(String(format: "%.6f", param.value))")
            }
            lines.append("")
        }

        let content = lines.joined(separator: "\n")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return "Ошибка сохранения: \(error.localizedDescription)"
        }
    }
}
