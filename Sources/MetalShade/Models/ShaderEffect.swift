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
    @Published var isEnabled:         Bool   = false
    @Published var targetWindowTitle: String = "Не выбрано"
    @Published var effects: [ShaderEffect] = [
        ShaderEffect(name: "Sharpen",  description: "Edge enhancement",            functionName: "fx_sharpen",  intensity: 0.6),
        ShaderEffect(name: "Vibrance", description: "Intelligent saturation boost", functionName: "fx_vibrance", intensity: 0.5),
        ShaderEffect(name: "Bloom",    description: "Soft glow on bright areas",    functionName: "fx_bloom",    intensity: 0.4),
        ShaderEffect(name: "Vignette", description: "Dark edges, cinematic look",   functionName: "fx_vignette", intensity: 0.5),
        ShaderEffect(name: "Contrast", description: "Lift / crush mid-tones",       functionName: "fx_contrast", intensity: 0.55),
    ]

    var activeEffects: [ShaderEffect] { effects.filter { $0.isEnabled } }

    // Callbacks set by AppDelegate
    var onPickWindow:  (() -> Void)?
    var onLoadShader:  (() -> Void)?
    var onAddPipeline: ((String, String) -> Bool)?

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
