import SwiftUI

struct WelcomeView: View {
    let continueAction: () -> Void

    var body: some View {
        ZStack {
            GridScanField()

            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    OrielLogoMark(size: 34)
                    Spacer()
                    Text(L10n.text("onboarding.preview"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                }
                .padding(.horizontal, 28)
                .frame(height: 70)
                .background(Color.black.opacity(0.28))

                Spacer()

                VStack(spacing: 0) {
                    Text(L10n.text("onboarding.eyebrow"))
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))

                    Text("Oriel")
                        .font(.custom("Space Grotesk", fixedSize: 72).weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.top, 2)

                    Text(L10n.text("onboarding.tagline"))
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.top, 14)

                    Button(action: continueAction) {
                        HStack(spacing: 10) {
                            Text(L10n.text("onboarding.action"))
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 22)
                        .frame(height: 46)
                        .background(
                            Capsule()
                                .fill(Color.white)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 30)
                }
                .frame(maxWidth: 540)
                .background(
                    RadialGradient(
                        colors: [
                            Color.black.opacity(0.70),
                            Color.black.opacity(0.30),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 255
                    )
                    .frame(width: 600, height: 390)
                    .allowsHitTesting(false)
                )
                .offset(y: -40)

                Spacer()
            }
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 700, idealHeight: 760)
        .preferredColorScheme(.dark)
    }
}
