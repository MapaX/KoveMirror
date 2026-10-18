import SwiftUI
import StoreKit

struct TipJarView: View {
    @StateObject private var tipManager = TipJarManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.3), Color.red.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.5), lineWidth: 1)
                        )

                    Image(systemName: "fuelpump.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.orange, Color.yellow],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Fuel the Development")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text("Voluntary Gas Purchases (Tip Jar)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                }

                Spacer()
            }

            Text("Kove Mirror is \(1.0, format: .percent) free and open source. If the app keeps your motorcycle dashboard running smoothly, you can fuel future updates with a voluntary gas tip!")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .lineSpacing(2)

            // Gas purchase tiers
            VStack(spacing: 12) {
                ForEach(FuelTipTier.allCases) { tier in
                    GasTipRow(tier: tier, tipManager: tipManager)
                }
            }

            // Supporter badge if user has previously donated
            if tipManager.totalTipsGiven > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.orange)
                        .font(.subheadline)

                    Text("Thank you! You've fueled development \(tipManager.totalTipsGiven) \(tipManager.totalTipsGiven == 1 ? "time" : "times").")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.8))

                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color.white.opacity(0.03))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [Color.orange.opacity(0.35), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .padding(.horizontal)
        .alert(tipManager.alertTitle, isPresented: $tipManager.showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            if let msg = tipManager.alertMessage {
                Text(msg)
            }
        }
    }
}

private struct GasTipRow: View {
    let tier: FuelTipTier
    @ObservedObject var tipManager: TipJarManager

    private var isPurchasingThis: Bool {
        tipManager.purchasingID == tier.rawValue
    }

    private var isAnyPurchasing: Bool {
        tipManager.purchasingID != nil
    }

    private var displayPrice: String {
        if let product = tipManager.product(for: tier) {
            return product.displayPrice
        }
        return tier.defaultPrice
    }

    private var tierColors: (Color, Color) {
        switch tier {
        case .cup:
            return (Color.cyan, Color.blue)
        case .jar:
            return (Color.orange, Color.yellow)
        case .tank:
            return (Color.red, Color.orange)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(tierColors.0.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: tier.iconName)
                    .font(.system(size: 18))
                    .foregroundColor(tierColors.0)
            }

            // Description
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(tier.defaultTitle)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text(tier.badgeText)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tierColors.0.opacity(0.2))
                        .foregroundColor(tierColors.0)
                        .clipShape(Capsule())
                }

                Text(tier.defaultDescription)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(2)
            }

            Spacer()

            // Purchase Button
            Button {
                Task {
                    await tipManager.purchase(tier)
                }
            } label: {
                ZStack {
                    if isPurchasingThis {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Text(displayPrice)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
                .frame(minWidth: 70, minHeight: 34)
                .background(
                    LinearGradient(
                        colors: [tierColors.0.opacity(0.8), tierColors.1.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(10)
                .shadow(color: tierColors.0.opacity(0.3), radius: 4)
            }
            .disabled(isAnyPurchasing)
            .opacity(isAnyPurchasing && !isPurchasingThis ? 0.5 : 1.0)
        }
        .padding(12)
        .background(Color.white.opacity(0.02))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        TipJarView()
    }
}
