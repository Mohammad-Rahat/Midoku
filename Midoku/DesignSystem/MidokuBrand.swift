import SwiftUI

// Add MidokuAssets.xcassets to the same app target as this file.
// Use named colors so appearance changes follow the system automatically.
enum MidokuTheme {
    static let background = Color("MidokuBackground")
    static let surface = Color("MidokuSurface")
    static let elevated = Color("MidokuElevated")
    static let primaryText = Color("MidokuPrimaryText")
    static let secondaryText = Color("MidokuSecondaryText")
    static let accent = Color("MidokuAccent")
    static let accentFill = Color("MidokuAccentFill")
    static let onAccent = Color("MidokuOnAccent")
    static let border = Color("MidokuBorder")
    static let danger = Color("MidokuDanger")
    static let readerBackground = Color("MidokuReaderBackground")
}

struct MidokuBrandTile: View {
    var size: CGFloat = 112

    var body: some View {
        Image("MidokuArtwork")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct MidokuWordmark: View {
    var body: some View {
        HStack(spacing: 12) {
            MidokuBrandTile(size: 40)
            Text("Midoku")
                .font(.title2.bold())
                .foregroundStyle(MidokuTheme.primaryText)
        }
    }
}

/// Optional in-app bootstrap screen, shown only while required local work is running.
/// The caller owns loading state. Never add an artificial timer to display this view.
/// Use LaunchScreen.storyboard for the actual system launch screen.
struct MidokuSplashView: View {
    var body: some View {
        ZStack {
            MidokuTheme.background.ignoresSafeArea()
            VStack(spacing: 24) {
                MidokuBrandTile()
                Text("Midoku")
                    .font(.largeTitle.bold())
                    .foregroundStyle(MidokuTheme.primaryText)
            }
            .padding(24)
        }
    }
}

struct MidokuPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(MidokuTheme.onAccent)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(minHeight: 48)
            .background(MidokuTheme.accentFill,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview("Splash — Light") {
    MidokuSplashView().preferredColorScheme(.light)
}

#Preview("Splash — Dark") {
    MidokuSplashView().preferredColorScheme(.dark)
}
