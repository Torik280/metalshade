import Foundation
import Combine

// One adjustable parameter (maps to a Metal buffer slot)
final class ShaderParam: ObservableObject, Identifiable {
    let id    = UUID()
    let name:  String   // HLSL uniform name
    let label: String   // Display label (from ui_label annotation or name)
    let min:   Float
    let max:   Float
    @Published var value: Float

    init(name: String, label: String? = nil, min: Float = 0, max: Float = 1, value: Float = 0.5) {
        self.name  = name
        self.label = label ?? name
        self.min   = min
        self.max   = max
        self.value = value
    }
}

final class ShaderEffect: ObservableObject, Identifiable {
    let id           = UUID()
    let name:         String
    let description:  String
    let functionName: String
    let isCustom:     Bool

    @Published var isEnabled: Bool
    @Published var params:    [ShaderParam]

    /// Convenience: first param value (intensity) for built-in single-param effects
    var intensity: Float {
        get { params.first?.value ?? 0.5 }
        set { params.first?.value = newValue }
    }

    init(
        name:         String,
        description:  String,
        functionName: String,
        isEnabled:    Bool         = false,
        intensity:    Float        = 0.5,
        isCustom:     Bool         = false,
        params:       [ShaderParam]? = nil
    ) {
        self.name         = name
        self.description  = description
        self.functionName = functionName
        self.isEnabled    = isEnabled
        self.isCustom     = isCustom
        self.params       = params ?? [ShaderParam(name: "intensity", label: "Intensity",
                                                   min: 0, max: 1, value: intensity)]
    }
}

final class ShaderManager: ObservableObject {
    @Published var isEnabled:         Bool    = false
    @Published var targetWindowTitle: String  = "Не выбрано"
    @Published var lastPresetName:    String  = ""
    @Published var lastPresetStatus:  String? = nil  // nil = no preset loaded yet
    // Defaults tuned for Star Stable Online's art style
    @Published var effects: [ShaderEffect] = [
        ShaderEffect(name: "Sharpen",  description: "Чёткость текстур",        functionName: "fx_sharpen",  intensity: 0.45),
        ShaderEffect(name: "Vibrance", description: "Насыщенность цветов",      functionName: "fx_vibrance", intensity: 0.35),
        ShaderEffect(name: "Bloom",    description: "Мягкое свечение",          functionName: "fx_bloom",    intensity: 0.25),
        ShaderEffect(name: "Vignette", description: "Затемнение краёв",         functionName: "fx_vignette", intensity: 0.30),
        ShaderEffect(name: "Contrast", description: "Контраст / яркость",       functionName: "fx_contrast", intensity: 0.52),
    ]

    var activeEffects: [ShaderEffect] { effects.filter { $0.isEnabled } }

    // Callbacks set by AppDelegate
    var onPickWindow:  (() -> Void)?
    var onLoadShader:  (() -> Void)?
    var onLoadPreset:  (() -> Void)?
    var onSavePreset:  (() -> Void)?
    var onAddPipeline: ((String, String) -> Bool)?

    /// Apply a loaded preset. Returns human-readable summary of what was applied.
    @discardableResult
    func applyPreset(_ preset: PresetManager.LoadedPreset) -> String {
        var matched:   [String] = []
        var unmatched: [String] = []

        for effect in effects {
            // Match against both technique name AND .fx filename
            let matchedTech = preset.techniques.first(where: {
                fuzzyMatch($0.name, effect: effect) || fuzzyMatch($0.fileName, effect: effect)
            })
            effect.isEnabled = matchedTech != nil

            // Find the params section: prefer the matched filename, then fuzzy search
            let sectionKey: String?
            if let fileName = matchedTech?.fileName, preset.params[fileName] != nil {
                sectionKey = fileName
            } else {
                sectionKey = preset.params.keys.first(where: {
                    fuzzyMatch($0.replacingOccurrences(of: ".fx", with: ""), effect: effect)
                })
            }

            if let key = sectionKey, let sectionParams = preset.params[key] {
                applyParams(sectionParams, to: effect)
            }
            if effect.isEnabled { matched.append(effect.name) }
        }

        // Report techniques that have no matching built-in effect
        for tech in preset.techniques {
            let hasMatch = effects.contains(where: {
                fuzzyMatch(tech.name, effect: $0) || fuzzyMatch(tech.fileName, effect: $0)
            })
            if !hasMatch { unmatched.append(tech.name) }
        }

        var summary: String
        if matched.isEmpty {
            summary = "Ни один встроенный эффект не совпал.\nЗагрузи нужные .fx файлы через «Загрузить .fx»."
        } else {
            summary = "Включено: \(matched.joined(separator: ", "))"
        }
        if !unmatched.isEmpty {
            let list = unmatched.prefix(6).joined(separator: ", ")
            let more = unmatched.count > 6 ? " и ещё \(unmatched.count - 6)..." : ""
            summary += "\n\nНужны .fx файлы: \(list)\(more)"
        }
        return summary
    }

    /// Try to set effect param values from the section params dict.
    /// Falls back to intensity-like key names, then to the first single float in the section.
    private func applyParams(_ sectionParams: [String: Float], to effect: ShaderEffect) {
        // Common ReShade intensity-like parameter names, in priority order
        let intensityKeys = [
            "intensity", "strength", "amount", "power", "blend", "opacity",
            "curve_height", "sharp_strength", "lumasharpen_strength",
            "vibrance", "colourfulness", "bloom_strength", "bloomstrength"
        ]

        for param in effect.params {
            let nameLC = param.name.lowercased()

            // 1. Exact match
            if let val = sectionParams.first(where: { $0.key.lowercased() == nameLC })?.value {
                param.value = min(param.max, max(param.min, val))
                continue
            }

            // 2. Try common intensity key names that contain or match the param name
            if let val = intensityKeys.lazy
                .compactMap({ sectionParams[$0] ?? sectionParams[$0.capitalized] })
                .first {
                param.value = min(param.max, max(param.min, val))
                continue
            }

            // 3. Any key that contains param name or vice versa
            if let entry = sectionParams.first(where: {
                let k = $0.key.lowercased()
                return k.contains(nameLC) || nameLC.contains(k)
            }) {
                param.value = min(param.max, max(param.min, entry.value))
                continue
            }

            // 4. Last resort: first float value in the section (clamped 0…1)
            if let first = sectionParams.values.first {
                let clamped = min(1, max(0, first))
                param.value = param.min + clamped * (param.max - param.min)
            }
        }
    }

    private func fuzzyMatch(_ technique: String, effect: ShaderEffect) -> Bool {
        let t = technique.lowercased().replacingOccurrences(of: ".fx", with: "")
        let n = effect.name.lowercased()
        let f = effect.functionName.lowercased().replacingOccurrences(of: "fx_", with: "")
        return t == n || t == f
            || t.contains(n) || n.contains(t)
            || t.contains(f) || f.contains(t)
    }

    func addCustomShader(name: String, functionName: String,
                         source: String, params: [ShaderParam]) -> Bool {
        guard let ok = onAddPipeline?(source, functionName), ok else { return false }
        let effect = ShaderEffect(
            name:         name,
            description:  "Custom shader",
            functionName: functionName,
            isEnabled:    true,
            isCustom:     true,
            params:       params.isEmpty
                ? [ShaderParam(name: "intensity", label: "Intensity")]
                : params
        )
        DispatchQueue.main.async { self.effects.append(effect) }
        return true
    }
}
