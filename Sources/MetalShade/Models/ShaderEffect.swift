import Foundation
import Combine

final class ShaderEffect: ObservableObject, Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let functionName: String

    @Published var isEnabled: Bool
    @Published var intensity: Float

    init(
        name: String,
        description: String,
        functionName: String,
        isEnabled: Bool = false,
        intensity: Float = 0.5
    ) {
        self.name = name
        self.description = description
        self.functionName = functionName
        self.isEnabled = isEnabled
        self.intensity = intensity
    }
}

final class ShaderManager: ObservableObject {
    @Published var isEnabled: Bool = false

    @Published var effects: [ShaderEffect] = [
        ShaderEffect(name: "Sharpen",  description: "Edge enhancement",           functionName: "fx_sharpen",  intensity: 0.6),
        ShaderEffect(name: "Vibrance", description: "Intelligent saturation boost",functionName: "fx_vibrance", intensity: 0.5),
        ShaderEffect(name: "Bloom",    description: "Soft glow on bright areas",   functionName: "fx_bloom",    intensity: 0.4),
        ShaderEffect(name: "Vignette", description: "Dark edges, cinematic look",  functionName: "fx_vignette", intensity: 0.5),
        ShaderEffect(name: "Contrast", description: "Lift / crush mid-tones",      functionName: "fx_contrast", intensity: 0.55),
    ]

    var activeEffects: [ShaderEffect] {
        effects.filter { $0.isEnabled }
    }
}
