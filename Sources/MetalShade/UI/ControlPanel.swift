import SwiftUI

struct ControlPanel: View {
    @ObservedObject var manager: ShaderManager

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Neon.border).padding(.horizontal, 8)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ssoQuickConnect
                    windowRow
                    masterToggle
                    SectionHeader(title: "EFFECTS")
                    effectsList
                    SectionHeader(title: "SHADERS")
                    loadShaderButton
                    SectionHeader(title: "PRESET")
                    presetStatus
                    presetButtons
                }
                .padding(.bottom, 16)
            }
        }
        .background(.ultraThinMaterial)
        .background(Neon.bg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Neon.border, lineWidth: 1))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(manager.isEnabled ? Neon.green : Color.white.opacity(0.2))
                .frame(width: 6, height: 6)
                .shadow(color: manager.isEnabled ? Neon.green.opacity(0.9) : .clear, radius: 4)
                .animation(.easeInOut(duration: 0.3), value: manager.isEnabled)

            GlowText(text: "METALSHADE", color: Neon.cyan, size: 12, weight: .bold)
                .kerning(3)

            Spacer()

            Button { NSApp.terminate(nil) } label: {
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

    // MARK: - Star Stable quick-connect banner (shown when no window selected)

    @ViewBuilder
    private var ssoQuickConnect: some View {
        if manager.targetWindowTitle == "Не выбрано" {
            Button {
                manager.onPickWindow?()
            } label: {
                HStack(spacing: 8) {
                    Text("⭐")
                        .font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Подключить Star Stable")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Нажми, затем выбери приложение")
                            .font(.system(size: 9))
                            .foregroundColor(Neon.dim)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Neon.dim)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Neon.cyan.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Neon.cyan.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.top, 8)
        }
    }

    // MARK: - Window picker row

    private var windowRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "macwindow")
                .font(.system(size: 10))
                .foregroundColor(Neon.dim)

            Text(manager.targetWindowTitle)
                .font(.system(size: 10))
                .foregroundColor(manager.targetWindowTitle == "Не выбрано" ? Neon.dim : .white)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button {
                manager.onPickWindow?()
            } label: {
                Text("Выбрать")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(Neon.cyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Neon.cyan.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Neon.cyan.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Neon.surface)
        .cornerRadius(10)
        .padding(.horizontal, 8)
        .padding(.top, 8)
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

    // MARK: - Preset status indicator

    @ViewBuilder
    private var presetStatus: some View {
        if let status = manager.lastPresetStatus {
            let isError = status.contains("Не найдено") || status.contains("Ни один")
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: isError ? "exclamationmark.triangle" : "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(isError ? .orange : Neon.green)
                VStack(alignment: .leading, spacing: 2) {
                    if !manager.lastPresetName.isEmpty {
                        Text(manager.lastPresetName)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    Text(status)
                        .font(.system(size: 8))
                        .foregroundColor(isError ? .orange : Neon.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background((isError ? Color.orange : Neon.green).opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                (isError ? Color.orange : Neon.green).opacity(0.2), lineWidth: 1))
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Preset buttons

    private var presetButtons: some View {
        HStack(spacing: 6) {
            Button {
                manager.onLoadPreset?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 10))
                    Text("Загрузить .ini")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                }
                .foregroundColor(Neon.green)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Neon.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Neon.green.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button {
                manager.onSavePreset?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tray.and.arrow.up")
                        .font(.system(size: 10))
                    Text("Сохранить .ini")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                }
                .foregroundColor(Neon.purple)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Neon.purple.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Neon.purple.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    // MARK: - Load shader button

    private var loadShaderButton: some View {
        Button {
            manager.onLoadShader?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 11))
                Text("Загрузить .fx / .metal")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            .foregroundColor(Neon.cyan)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Neon.cyan.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Neon.cyan.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }
}

// MARK: - Effect row (supports multiple params)

struct EffectRow: View {
    @ObservedObject var effect: ShaderEffect

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(effect.isEnabled ? Neon.cyan : Color.white.opacity(0.15))
                    .frame(width: 3, height: 24)
                    .shadow(color: effect.isEnabled ? Neon.cyan.opacity(0.7) : .clear, radius: 3)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(effect.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(effect.isEnabled ? .white : Neon.dim)
                        if effect.isCustom {
                            Text("FX")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundColor(Neon.cyan)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Neon.cyan.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Text(effect.description)
                        .font(.system(size: 9))
                        .foregroundColor(Neon.dim)
                }

                Spacer()
                NeonToggle(isOn: $effect.isEnabled)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if effect.isEnabled {
                VStack(spacing: 6) {
                    ForEach(effect.params) { param in
                        ParamRow(param: param)
                    }
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

struct ParamRow: View {
    @ObservedObject var param: ShaderParam

    var body: some View {
        HStack(spacing: 8) {
            Text(param.label.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(Neon.dim)
                .kerning(1)
                .lineLimit(1)
                .frame(width: 60, alignment: .leading)

            NeonSlider(value: Binding(
                get: {
                    guard param.max > param.min else { return 0 }
                    return (param.value - param.min) / (param.max - param.min)
                },
                set: { newNorm in
                    param.value = param.min + newNorm * (param.max - param.min)
                }
            ))

            Text(String(format: "%.2f", param.value))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Neon.cyan)
                .frame(width: 34, alignment: .trailing)
        }
    }
}

#Preview {
    ControlPanel(manager: ShaderManager())
        .frame(width: 270, height: 520)
}
