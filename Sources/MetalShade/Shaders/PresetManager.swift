import Foundation

/// Reads and writes ReShade-compatible preset .ini files.
/// Handles both old format (Techniques=Name) and new format (Techniques=Name@File.fx).
struct PresetManager {

    // MARK: - Types

    struct EnabledTechnique {
        let name:     String   // e.g. "AdaptiveSharpen"
        let fileName: String   // e.g. "AdaptiveSharpen.fx"
    }

    struct LoadedPreset {
        let techniques: [EnabledTechnique]
        /// Map from .fx filename → (paramName → value), single-value floats only
        let params: [String: [String: Float]]
    }

    // MARK: - Load

    static func load(from url: URL) -> (preset: LoadedPreset?, error: String?) {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return (nil, "Не удалось прочитать файл \(url.lastPathComponent)")
        }
        return (parse(raw), nil)
    }

    private static func parse(_ text: String) -> LoadedPreset {
        var techniques:     [EnabledTechnique]          = []
        var params:         [String: [String: Float]]   = [:]
        var currentSection: String?                     = nil

        // Support both Unix (\n) and Windows (\r\n) line endings
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix(";"), !line.hasPrefix("#") else { continue }

            // Section header [FileName.fx]
            if line.hasPrefix("[") && line.hasSuffix("]") {
                currentSection = String(line.dropFirst().dropLast())
                continue
            }

            guard let eqIdx = line.firstIndex(of: "=") else { continue }
            let key   = String(line[..<eqIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: eqIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)

            if currentSection == nil {
                // Global keys
                if key == "Techniques" {
                    // Format: "TechniqueName@FileName.fx,..." or just "TechniqueName,..."
                    techniques = value
                        .components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .map { entry -> EnabledTechnique in
                            if let atIdx = entry.firstIndex(of: "@") {
                                let name     = String(entry[..<atIdx])
                                let fileName = String(entry[entry.index(after: atIdx)...])
                                return EnabledTechnique(name: name, fileName: fileName)
                            }
                            // Old format without @
                            let fileName = entry.hasSuffix(".fx") ? entry : entry + ".fx"
                            return EnabledTechnique(name: entry, fileName: fileName)
                        }
                }
            } else if let section = currentSection {
                // Skip multi-value entries like "FogColor=0.5,0.5,0.5"
                guard !value.contains(",") else { continue }
                if let floatVal = Float(value) {
                    params[section, default: [:]][key] = floatVal
                }
            }
        }

        return LoadedPreset(techniques: techniques, params: params)
    }

    // MARK: - Save

    static func save(effects: [ShaderEffect], to url: URL) -> String? {
        var lines: [String] = []

        let enabledEntries = effects.filter { $0.isEnabled }
            .map { "\($0.name)@\($0.name).fx" }
        lines.append("Techniques=\(enabledEntries.joined(separator: ","))")
        lines.append("")

        for effect in effects {
            lines.append("[\(effect.name).fx]")
            for param in effect.params {
                lines.append("\(param.name)=\(String(format: "%.6f", param.value))")
            }
            lines.append("")
        }

        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return "Ошибка сохранения: \(error.localizedDescription)"
        }
    }
}
