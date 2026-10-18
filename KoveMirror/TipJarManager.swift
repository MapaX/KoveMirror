import Foundation
import StoreKit
import Combine

enum FuelTipTier: String, CaseIterable, Identifiable {
    case cup = "com.mustcode.KoveMirror.tip.cup"
    case jar = "com.mustcode.KoveMirror.tip.jar"
    case tank = "com.mustcode.KoveMirror.tip.tank"

    var id: String { rawValue }

    var defaultTitle: String {
        switch self {
        case .cup: return "Cup of Gas"
        case .jar: return "Jar of Gas"
        case .tank: return "Tank of Gas"
        }
    }

    var defaultPrice: String {
        switch self {
        case .cup: return "$0.99"
        case .jar: return "$4.99"
        case .tank: return "$9.99"
        }
    }

    var defaultDescription: String {
        switch self {
        case .cup: return "A quick fuel splash to keep servers & updates rolling."
        case .jar: return "A solid boost for new features and maintenance."
        case .tank: return "Full tank of gas! Maximum support for the project."
        }
    }

    var iconName: String {
        switch self {
        case .cup: return "drop.fill"
        case .jar: return "fuelpump.fill"
        case .tank: return "flame.fill"
        }
    }

    var badgeText: String {
        switch self {
        case .cup: return "0.5 L"
        case .jar: return "3.0 L"
        case .tank: return "Full Tank"
        }
    }
}

@MainActor
final class TipJarManager: ObservableObject {
    static let shared = TipJarManager()

    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var purchasingID: String? = nil
    
    @Published var alertMessage: String? = nil
    @Published var showAlert: Bool = false
    @Published var alertTitle: String = ""

    private var transactionListener: Task<Void, Never>?

    private init() {
        transactionListener = listenForTransactions()
        Task {
            await fetchProducts()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    func fetchProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let ids = Set(FuelTipTier.allCases.map(\.rawValue))
            let storeProducts = try await Product.products(for: ids)
            self.products = storeProducts.sorted { $0.price < $1.price }
        } catch {
            print("⛽ Failed to load tip products: \(error)")
        }
    }

    func product(for tier: FuelTipTier) -> Product? {
        products.first { $0.id == tier.rawValue }
    }

    func purchase(_ tier: FuelTipTier) async {
        guard purchasingID == nil else { return }

        guard let product = product(for: tier) else {
            // If store products couldn't be loaded (e.g. offline or no store configuration active)
            alertTitle = "Store Unavailable"
            alertMessage = "Unable to connect to the App Store right now. Please check your connection and try again."
            showAlert = true
            return
        }

        purchasingID = tier.rawValue
        defer { purchasingID = nil }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                recordTip(tier: tier)
                alertTitle = "Thank You! ⛽🏍️"
                alertMessage = "Your purchase of a \(tier.defaultTitle) is greatly appreciated! Thank you for supporting Kove Mirror."
                showAlert = true

            case .userCancelled:
                break

            case .pending:
                alertTitle = "Purchase Pending"
                alertMessage = "Your purchase is pending approval."
                showAlert = true

            @unknown default:
                break
            }
        } catch {
            alertTitle = "Purchase Error"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                do {
                    guard let self = self else { return }
                    let transaction = try self.checkVerified(result)
                    await transaction.finish()
                    await MainActor.run {
                        if let tier = FuelTipTier(rawValue: transaction.productID) {
                            self.recordTip(tier: tier)
                        }
                    }
                } catch {
                    print("⛽ Transaction verification error: \(error)")
                }
            }
        }
    }

    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }

    private func recordTip(tier: FuelTipTier) {
        let countKey = "kove_fuel_tips_count"
        let currentCount = UserDefaults.standard.integer(forKey: countKey)
        UserDefaults.standard.set(currentCount + 1, forKey: countKey)
    }

    var totalTipsGiven: Int {
        UserDefaults.standard.integer(forKey: "kove_fuel_tips_count")
    }
}
