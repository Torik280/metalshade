import SwiftUI

// MARK: - Main control panel view

struct ControlPanel: View {
    @ObservedObject var manager: ShaderManager

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Neon.border).padding(.horizontal, 8)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    masterToggle
                    SectionHeader(title: "EFFECTS")
                    effectsList
                }
                .padding(.bottom, 16)
            }
        }
        .background(.ultraThinMaterial)
        .background(Neon.bg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Neon.border, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            // Animated status dot
            Circle()
                .fill(manager.isEnabled ? Neon.green : Color.white.opacity(0.2))
                .frame(width: 6, height: 6)
                .shadow(color: manager.isEnabled ? Neon.green.opacity(0.9) : .clear, radius: 4)
                .animation(.easeInOut(duration: 0.3), value: manager.isEnabled)

            GlowText("METALSHADE", color: Neon.cyan, size: 12, weight: .bold)
                .kerning(3)

            Spacer()

            // Quit button
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Neon.dim)
                    .frame(width: 18, height: 18)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Master toggle

    private var masterToggle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Post-Processing")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                Text(manager.isEnabled ? "Active" : "Inactive")
                    .font(.system(size: 10))
                    .foregroundColor(manager.isEnabled ? Neon.green : Neon.dim)
            }
            Spacer()
            NeonToggle(isOn: $manager.isEnabled, color: Neon.green)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Neon.surface)
        .cornerRadius(10)
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    // MARK: - Effects list

    private var effectsList: some View {
        VStack(spacing: 4) {
            ForEach(manager.effects) { effect in
                EffectRow(effect: effect)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .opacity(manager.isEnabled ? 1 : 0.4)
        .animation(.easeInOut(duration: 0.2), value: manager.isEnabled)
        .allowsHitTesting(manager.isEnabled)
    }
}

// MARK: - Single effect row

struct EffectRow: View {
    @ObservedObject var effect: ShaderEffect

    var body: some View {
        VStack(spacing: 0) {
            // Header row: name + toggle
            HStack {
                // Status indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(effect.isEnabled ? Neon.cyan : Color.white.opacity(0.15))
                    .frame(width: 3, height: 24)
                    .shadow(color: effect.isEnabled ? Neon.cyan.opacity(0.7) : .clear, radius: 3)

                VStack(alignment: .leading, spacing: 1) {
                    Text(effect.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(effect.isEnabled ? .white : Neon.dim)
                    Text(effect.description)
                        .font(.system(size: 9))
                        .foregroundColor(Neon.dim)
                }

                Spacer()
                NeonToggle(isOn: $effect.isEnabled)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            // Intensity slider — shown only when enabled
            if effect.isEnabled {
                HStack(spacing: 8) {
                    Text("INTENSITY")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(Neon.dim)
                        .kerning(1)
                    NeonSlider(value: $effect.intensity)
                    Text(String(format: "%.2f", effect.intensity))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Neon.cyan)
                        .frame(width: 30, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Neon.surface)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(effect.isEnabled ? Neon.cyan.opacity(0.25) : Neon.border, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: effect.isEnabled)
    }
}

// MARK: - Preview (requires Xcode canvas)
#Preview {
    ControlPanel(manager: ShaderManager())
        .frame(width: 270, height: 460)
}
