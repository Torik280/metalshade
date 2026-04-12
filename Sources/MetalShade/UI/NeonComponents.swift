import SwiftUI

enum Neon {
    static let cyan    = Color(red: 0.00, green: 0.95, blue: 1.00)
    static let purple  = Color(red: 0.65, green: 0.10, blue: 1.00)
    static let green   = Color(red: 0.15, green: 1.00, blue: 0.55)
    static let bg      = Color.black.opacity(0.82)
    static let surface = Color.white.opacity(0.04)
    static let border  = Color.white.opacity(0.08)
    static let dim     = Color.white.opacity(0.35)
}

struct NeonToggle: View {
    @Binding var isOn: Bool
    var color: Color = Neon.cyan

    private let w: CGFloat = 36
    private let h: CGFloat = 20

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: h / 2)
                .fill(isOn ? color.opacity(0.25) : Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: h / 2)
                        .stroke(isOn ? color : Color.white.opacity(0.15), lineWidth: 1)
                )

            Circle()
                .fill(isOn ? color : Color.white.opacity(0.4))
                .frame(width: h - 4, height: h - 4)
                .padding(2)
                .shadow(color: isOn ? color.opacity(0.8) : .clear, radius: 4)
        }
        .frame(width: w, height: h)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isOn)
        .onTapGesture { isOn.toggle() }
    }
}

struct NeonSlider: View {
    @Binding var value: Float
    var color: Color = Neon.cyan

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 3)

                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.6), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * CGFloat(value), height: 3)
                    .shadow(color: color.opacity(0.5), radius: 3)

                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .shadow(color: color.opacity(0.9), radius: 5)
                    .offset(x: geo.size.width * CGFloat(value) - 5)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        value = max(0, min(1, Float(drag.location.x / geo.size.width)))
                    }
            )
        }
        .frame(height: 16)
    }
}

struct GlowText: View {
    let text: String
    var color: Color = Neon.cyan
    var size: CGFloat = 13
    var weight: Font.Weight = .medium

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight, design: .monospaced))
            .foregroundColor(color)
            .shadow(color: color.opacity(0.8), radius: 6)
            .shadow(color: color.opacity(0.4), radius: 12)
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(Neon.dim)
                .kerning(2)
            Rectangle()
                .fill(Neon.border)
                .frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }
}
