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
        var matched: [String]   = []
        var unmatched: [String] = []

        for effect in effects {
            // Enable if the technique name fuzzy-matches (e.g. "LumaSharpen" → "Sharpen")
            let inTechniques = preset.enabledTechniques.contains(where: {
                fuzzyMatch(technique: $0, effect: effect)
            })
            effect.isEnabled = inTechniques

            // Find matching .fx section in params
            let sectionKey = preset.params.keys.first(where: {
                fuzzyMatch(technique: $0.replacingOccurrences(of: ".fx", with: ""), effect: effect)
            })
            if let key = sectionKey, let sectionParams = preset.params[key] {
                for param in effect.params {
                    if let val = sectionParams[param.name] {
                        param.value = min(param.max, max(param.min, val))
                    } else if let entry = sectionParams.first(where: {
                        $0.key.caseInsensitiveCompare(param.name) == .orderedSame
                    }) {
                        param.value = min(param.max, max(param.min, entry.value))
                    }
                }
                if inTechniques { matched.append(effect.name) }
            }
        }

        // Collect preset techniques that didn't match any loaded effect
        for tech in preset.enabledTechniques {
            let hasMatch = effects.contains(where: { fuzzyMatch(technique: tech, effect: $0) })
            if !hasMatch { unmatched.append(tech) }
        }

        var summary = matched.isEmpty
            ? "Ни один эффект не совпал с пресетом."
            : "Включено: \(matched.joined(separator: ", "))."
        if !unmatched.isEmpty {
            summary += "\n\nНе найдено (загрузи .fx файлы):\n" + unmatched.map { "• \($0).fx" }.joined(separator: "\n")
        }
        return summary
    }

    private func fuzzyMatch(technique: String, effect: ShaderEffect) -> Bool {
        let t = technique.lowercased()
        let n = effect.name.lowercased()
        let f = effect.functionName.lowercased().replacingOccurrences(of: "fx_", with: "")
        // Exact or contains match in either direction
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
