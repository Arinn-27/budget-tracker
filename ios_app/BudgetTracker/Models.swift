import Foundation
import SwiftUI
import CryptoKit

// MARK: - Apple HIG Design Token System (Dark Mode Only)
public struct AppleTheme {
    // Canvas & Card Surfaces (Native Semantic iOS Colors)
    public static let bgCanvas = Color.black // #000000 True OLED Black
    public static let bgCard = Color(UIColor.secondarySystemGroupedBackground) // #1C1C1E Apple System Gray 6
    public static let bgTertiary = Color(UIColor.tertiarySystemGroupedBackground) // #2C2C2E Apple System Gray 5
    public static let bgGlass = Color(UIColor.secondarySystemGroupedBackground).opacity(0.85)
    
    // Specular Card Hairline
    public static let cardStroke = LinearGradient(
        colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    public static let cardStrokeHairline = Color.white.opacity(0.08)
    
    // Semantic Accents
    public static let accentGreen = Color(UIColor.systemGreen) // #30D158 Positive / Income / On-Pace
    public static let accentRed = Color(UIColor.systemRed)     // #FF453A Expense / Liability / Over-Budget
    public static let accentOrange = Color(UIColor.systemOrange) // #FF9F0A Warning / Near-Budget (>= 80%)
    public static let accentBlue = Color(UIColor.systemBlue)   // #0A84FF Interactive / Active Tint
    public static let accentIndigo = Color(UIColor.systemIndigo) // #5E5CE6 AI / Intelligence
    public static let accentPurple = Color(UIColor.systemPurple)
    public static let accentPink = Color(UIColor.systemPink)
    public static let accentTeal = Color(UIColor.systemTeal)
    public static let accentMint = Color(UIColor.systemMint)
    public static let accentYellow = Color(UIColor.systemYellow)
    
    // Typography Colors
    public static let labelPrimary = Color(UIColor.label)
    public static let labelSecondary = Color(UIColor.secondaryLabel) // #8E8E93
    public static let labelTertiary = Color(UIColor.tertiaryLabel)
    public static let labelQuaternary = Color(UIColor.quaternaryLabel)
    
    // Corner Radii
    public static let cardCornerRadius: CGFloat = 20
    public static let compactCornerRadius: CGFloat = 14
    public static let buttonCornerRadius: CGFloat = 16
    public static let pillCornerRadius: CGFloat = 12
    
    // Compatibility Aliases for DesignSystem / Theme
    public static let bgPrimary = bgCanvas
    public static let bgSecondary = bgCard
    public static let bgElevated = bgCard
    public static let borderSubtle = Color.white.opacity(0.08)
    public static let accentCoral = accentRed
    public static let accentGold = accentYellow
    public static let accentAmber = accentOrange
    public static let bentoCornerRadius: CGFloat = cardCornerRadius
}

// Backward Compatibility Aliases
public typealias DesignSystem = AppleTheme
public typealias Theme = AppleTheme

// MARK: - View Modifiers for Apple HIG Styling
public struct AppleCardModifier: ViewModifier {
    var cornerRadius: CGFloat = AppleTheme.cardCornerRadius
    var fill: Color = AppleTheme.bgCard
    
    public func body(content: Content) -> some View {
        content
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)
    }
}

public extension View {
    func appleCard(cornerRadius: CGFloat = AppleTheme.cardCornerRadius, fill: Color = AppleTheme.bgCard) -> some View {
        modifier(AppleCardModifier(cornerRadius: cornerRadius, fill: fill))
    }
}

// MARK: - Category Model
public struct Category: Identifiable, Hashable {
    public let id: Int
    public let name: String
    
    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
    
    public static func suggestedSubCategories(for categoryName: String) -> [String] {
        return suggestedMerchants(for: categoryName)
    }
    
    /// Loads category-specific merchants from a local git-ignored `local_merchants.json` file if available.
    /// Returns an empty list when no local file is present so no merchant names are hardcoded in source control.
    public static func suggestedMerchants(for categoryName: String) -> [String] {
        let localMap = loadLocalMerchantsMap()
        if let exact = localMap[categoryName] {
            return exact
        }
        if let match = localMap.first(where: { $0.key.caseInsensitiveCompare(categoryName) == .orderedSame }) {
            return match.value
        }
        return []
    }
    
    public static func loadLocalMerchantsMap() -> [String: [String]] {
        let fm = FileManager.default
        if let docsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let docFile = docsURL.appendingPathComponent("local_merchants.json")
            if let data = try? Data(contentsOf: docFile),
               let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
                return decoded
            }
        }
        #if targetEnvironment(simulator)
        let sourceDirURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let workspaceFile = sourceDirURL.appendingPathComponent("local_merchants.json")
        if let data = try? Data(contentsOf: workspaceFile),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            return decoded
        }
        #endif
        return [:]
    }
    
    public static func saveLocalMerchantsMap(_ map: [String: [String]]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(map) else { return }
        if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let docFile = docsURL.appendingPathComponent("local_merchants.json")
            try? data.write(to: docFile, options: .atomic)
        }
        #if targetEnvironment(simulator)
        let sourceDirURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let workspaceFile = sourceDirURL.appendingPathComponent("local_merchants.json")
        if FileManager.default.fileExists(atPath: workspaceFile.path) {
            try? data.write(to: workspaceFile, options: .atomic)
        }
        #endif
    }
}

// MARK: - Category Styling & Metadata
public struct CategoryStyle {
    public let icon: String
    public let color: Color
    public let emoji: String
    public let isIncome: Bool
    
    public init(icon: String, color: Color, emoji: String, isIncome: Bool = false) {
        self.icon = icon
        self.color = color
        self.emoji = emoji
        self.isIncome = isIncome
    }
    
    public static func style(for name: String) -> CategoryStyle {
        let lower = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Income categories
        if lower.contains("salary") || lower.contains("paycheck") || lower.contains("payroll") {
            return CategoryStyle(icon: "banknote.fill", color: Color(UIColor.systemGreen), emoji: "💵", isIncome: true)
        } else if lower.contains("invest") || lower.contains("dividend") || lower.contains("crypto") || lower.contains("stock") {
            return CategoryStyle(icon: "chart.line.uptrend.xyaxis", color: Color(UIColor.systemMint), emoji: "📈", isIncome: true)
        } else if lower.contains("gift") || lower.contains("grant") || lower.contains("bonus") {
            return CategoryStyle(icon: "gift.fill", color: Color(UIColor.systemOrange), emoji: "🎁", isIncome: true)
        } else if lower.contains("income") || lower.contains("revenue") {
            return CategoryStyle(icon: "arrow.down.left.circle.fill", color: Color(UIColor.systemGreen), emoji: "💰", isIncome: true)
        }
        
        // Transfer categories
        if lower.contains("transfer") || lower.contains("payment to") || lower.contains("credit card payment") {
            return CategoryStyle(icon: "arrow.left.arrow.right", color: Color(UIColor.systemBlue), emoji: "🔄")
        }
        
        // Expense categories
        if lower.contains("grocer") || lower.contains("food mart") || lower.contains("market") {
            return CategoryStyle(icon: "cart.fill", color: Color(UIColor.systemOrange), emoji: "🛒")
        } else if lower.contains("food") || lower.contains("drink") || lower.contains("dining") || lower.contains("restaurant") || lower.contains("coffee") || lower.contains("cafe") {
            return CategoryStyle(icon: "fork.knife", color: Color(UIColor.systemPink), emoji: "🍽️")
        } else if lower.contains("social") || lower.contains("party") || lower.contains("nightlife") || lower.contains("entertainment") || lower.contains("fun") {
            return CategoryStyle(icon: "sparkles", color: Color(UIColor.systemPurple), emoji: "🎉")
        } else if lower.contains("transport") || lower.contains("transit") || lower.contains("bus") || lower.contains("train") || lower.contains("subway") || lower.contains("uber") || lower.contains("gas") {
            return CategoryStyle(icon: "tram.fill", color: Color(UIColor.systemTeal), emoji: "🚇")
        } else if lower.contains("hous") || lower.contains("utilit") || lower.contains("rent") || lower.contains("water") || lower.contains("power") || lower.contains("electric") {
            return CategoryStyle(icon: "bolt.fill", color: Color(UIColor.systemYellow), emoji: "⚡")
        } else if lower.contains("personal") || lower.contains("care") || lower.contains("beauty") || lower.contains("salon") || lower.contains("hair") {
            return CategoryStyle(icon: "heart.fill", color: Color(UIColor.systemPink), emoji: "💖")
        } else if lower.contains("shop") || lower.contains("cloth") || lower.contains("fashion") || lower.contains("retail") {
            return CategoryStyle(icon: "bag.fill", color: Color(UIColor.systemIndigo), emoji: "🛍️")
        } else if lower.contains("health") || lower.contains("medic") || lower.contains("doctor") || lower.contains("pharmacy") || lower.contains("dental") {
            return CategoryStyle(icon: "cross.fill", color: Color(UIColor.systemRed), emoji: "🩺")
        } else if lower.contains("member") || lower.contains("subscri") || lower.contains("gym") || lower.contains("fitness") {
            return CategoryStyle(icon: "repeat", color: Color(UIColor.systemBlue), emoji: "🔁")
        } else if lower.contains("giving") || lower.contains("charity") || lower.contains("donation") {
            return CategoryStyle(icon: "hand.raised.fill", color: Color(UIColor.systemMint), emoji: "🤲")
        } else {
            return CategoryStyle(icon: "tag.fill", color: Color(UIColor.systemGray), emoji: "🏷️")
        }
    }
}

// MARK: - Budget Model
public struct Budget: Identifiable, Hashable {
    public var id: Int { categoryID }
    public let categoryID: Int
    public let categoryName: String
    public var monthlyLimit: Double
    
    public init(categoryID: Int, categoryName: String, monthlyLimit: Double) {
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.monthlyLimit = monthlyLimit
    }
}

// MARK: - Account Types & Model
public enum AccountType: String, CaseIterable, Identifiable {
    case debit = "Debit"
    case credit = "Credit"
    case savings = "Savings"
    case investment = "Investment"
    
    public var id: String { rawValue }
    
    public var isLiability: Bool {
        self == .credit
    }
    
    public var defaultIcon: String {
        switch self {
        case .debit: return "creditcard.fill"
        case .credit: return "creditcard.and.123"
        case .savings: return "banknote.fill"
        case .investment: return "chart.line.uptrend.xyaxis"
        }
    }
    
    public var displaySectionTitle: String {
        switch self {
        case .debit: return "Cash & Banking"
        case .savings: return "Savings"
        case .investment: return "Investments"
        case .credit: return "Credit Cards & Liabilities"
        }
    }
    
    public init?(fromRaw raw: String) {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch clean {
        case "debit", "checking", "chequing", "cash":
            self = .debit
        case "credit", "credit card", "credit_card", "liability", "liabilities":
            self = .credit
        case "savings", "saving":
            self = .savings
        case "investment", "investments", "invest":
            self = .investment
        default:
            if let exact = AccountType(rawValue: raw) {
                self = exact
            } else {
                return nil
            }
        }
    }
}

public struct CardBonusTier: Identifiable, Hashable, Codable {
    public var id: String
    public var rate: Double
    public var categories: [String]
    
    public init(id: String = UUID().uuidString, rate: Double, categories: [String]) {
        self.id = id
        self.rate = rate
        self.categories = categories
    }
}

public struct Account: Identifiable, Hashable {
    public let id: String
    public var name: String
    public var type: AccountType
    public var balance: Double
    public var institution: String
    public var iconName: String
    public var colorHex: String
    public var parentID: String?
    public var includeInNetWorth: Bool
    public var accountNumber: String?
    public var baseRate: Double
    public var bonusRate: Double
    public var bonusCategories: [String]
    public var bonusTiers: [CardBonusTier]
    
    public init(id: String = UUID().uuidString,
                name: String,
                type: AccountType,
                balance: Double = 0.0,
                institution: String = "",
                iconName: String = "",
                colorHex: String = "#0A84FF",
                parentID: String? = nil,
                includeInNetWorth: Bool = true,
                accountNumber: String? = nil,
                baseRate: Double = 0.0,
                bonusRate: Double = 0.0,
                bonusCategories: [String] = [],
                bonusTiers: [CardBonusTier] = []) {
        self.id = id
        self.name = name
        self.type = type
        self.balance = balance
        self.institution = institution
        self.iconName = iconName.isEmpty ? type.defaultIcon : iconName
        self.colorHex = colorHex
        self.parentID = parentID
        self.includeInNetWorth = includeInNetWorth
        self.accountNumber = accountNumber
        self.baseRate = baseRate
        self.bonusRate = bonusRate
        self.bonusCategories = bonusCategories
        self.bonusTiers = bonusTiers
    }
    
    /// Formats a percentage rate cleanly (e.g., 2.0 -> "2%", 1.5 -> "1.5%", 1.25 -> "1.25%")
    public static func formatRate(_ rate: Double) -> String {
        if abs(rate - round(rate)) < 0.001 {
            return "\(Int(round(rate)))%"
        } else if abs(rate * 10 - round(rate * 10)) < 0.01 {
            return String(format: "%.1f%%", rate)
        } else {
            return String(format: "%.2f%%", rate)
        }
    }
    
    /// All active bonus rate tiers (primary bonusRate + bonusCategories, plus any extra bonusTiers)
    public var activeBonusTiers: [CardBonusTier] {
        var tiers: [CardBonusTier] = []
        let cleanPrimaryCats = bonusCategories.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if bonusRate > 0 && !cleanPrimaryCats.isEmpty {
            tiers.append(CardBonusTier(id: "primary", rate: bonusRate, categories: cleanPrimaryCats))
        }
        for tier in bonusTiers where tier.rate > 0 && !tier.categories.isEmpty {
            tiers.append(tier)
        }
        return tiers
    }
    
    /// Returns the effective reward percentage for a given category name and whether it's a bonus rate
    public func rewardInfo(for categoryName: String) -> (rate: Double, isBonus: Bool) {
        let target = categoryName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { return (baseRate, false) }
        
        var bestBonusRate: Double? = nil
        for tier in activeBonusTiers {
            let matches = tier.categories.contains { cat in
                let c = cat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return c == target
            }
            if matches {
                if let currentBest = bestBonusRate {
                    if tier.rate > currentBest { bestBonusRate = tier.rate }
                } else {
                    bestBonusRate = tier.rate
                }
            }
        }
        
        if let bonus = bestBonusRate, bonus >= baseRate, bonus > 0 {
            return (bonus, true)
        }
        return (baseRate, false)
    }
    
    public var hasRewardRatesConfigured: Bool {
        baseRate > 0 || bonusRate > 0 || !bonusTiers.isEmpty
    }
    
    public var isSubAccount: Bool {
        guard let pid = parentID else { return false }
        return !pid.isEmpty
    }
    
    public var isLiability: Bool {
        type.isLiability
    }
    
    /// Masked card/account number for physical Apple Card feel
    public var maskedNumber: String {
        if let custom = accountNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return "•••• \(custom)"
        }
        let hash = abs(id.hashValue) % 9000 + 1000
        return "•••• \(hash)"
    }
    
    public var institutionColor: Color {
        let lower = "\(institution) \(name)".lowercased()
        if lower.contains("cibc") {
            return Color(red: 0.82, green: 0.12, blue: 0.22) // CIBC Burgundy
        } else if lower.contains("scotia") {
            return Color(red: 0.88, green: 0.1, blue: 0.15) // Scotiabank Red
        } else if lower.contains("wealth") || lower.contains("ws") {
            return Color(red: 0.22, green: 0.22, blue: 0.25) // Wealthsimple Dark Slate
        } else if lower.contains("splitwise") {
            return Color(red: 0.16, green: 0.75, blue: 0.53) // Splitwise Mint
        } else if lower.contains("bmo") {
            return Color(red: 0.0, green: 0.47, blue: 0.76) // BMO Blue
        } else if lower.contains("student") || lower.contains("university") {
            return Color(red: 0.95, green: 0.65, blue: 0.15) // Gold
        } else if lower.contains("amex") {
            return Color(red: 0.05, green: 0.43, blue: 0.73) // AMEX Blue
        } else if lower.contains("td") {
            return Color(red: 0.0, green: 0.65, blue: 0.3) // TD Green
        } else if lower.contains("rbc") {
            return Color(red: 0.0, green: 0.35, blue: 0.75) // RBC Royal Blue
        } else {
            return Color(hex: colorHex)
        }
    }
    
    /// Card gradient for Apple Wallet physical feel
    public var cardGradient: LinearGradient {
        let base = institutionColor
        switch type {
        case .credit:
            // Sleek dark titanium or tinted Apple Card gradient
            return LinearGradient(
                colors: [base.opacity(0.85), Color(red: 0.12, green: 0.12, blue: 0.15), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .investment:
            return LinearGradient(
                colors: [base.opacity(0.7), Color(UIColor.systemIndigo).opacity(0.5), Color(red: 0.08, green: 0.08, blue: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .savings:
            return LinearGradient(
                colors: [base.opacity(0.8), Color(UIColor.systemTeal).opacity(0.4), Color(red: 0.08, green: 0.1, blue: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .debit:
            return LinearGradient(
                colors: [base.opacity(0.85), Color(red: 0.14, green: 0.15, blue: 0.18), Color(red: 0.08, green: 0.08, blue: 0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Recurring Payment & Membership Frequency
public enum RecurringFrequency: String, CaseIterable, Identifiable, Codable {
    case weekly = "Weekly"
    case biWeekly = "Bi-Weekly"
    case monthly = "Monthly"
    case quarterly = "Quarterly"
    case yearly = "Yearly"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .weekly, .biWeekly: return "calendar.badge.clock"
        case .monthly: return "repeat"
        case .quarterly: return "chart.bar.xaxis"
        case .yearly: return "calendar"
        }
    }
    
    public var multiplierToMonthly: Double {
        switch self {
        case .weekly: return 52.0 / 12.0
        case .biWeekly: return 26.0 / 12.0
        case .monthly: return 1.0
        case .quarterly: return 1.0 / 3.0
        case .yearly: return 1.0 / 12.0
        }
    }
}

// MARK: - Recurring Transaction Type (Exp, Income, Transfer)
public enum RecurringTransactionType: String, CaseIterable, Identifiable, Codable {
    case expense = "Exp"
    case income = "Income"
    case transfer = "Transfer"
    
    public var id: String { rawValue }
    
    public var displayTitle: String {
        switch self {
        case .expense: return "Expense"
        case .income: return "Income"
        case .transfer: return "Transfer"
        }
    }
    
    public var dbValue: String {
        switch self {
        case .expense: return "expense"
        case .income: return "income"
        case .transfer: return "transfer"
        }
    }
    
    public init(fromRaw raw: String?, categoryName: String? = nil, name: String = "") {
        let r = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if r == "transfer" || r == "transfers" {
            self = .transfer
            return
        }
        if r == "income" {
            self = .income
            return
        }
        if r == "expense" || r == "exp" {
            let lowerName = name.lowercased()
            let lowerCat = (categoryName ?? "").lowercased()
            if lowerCat.contains("transfer") || lowerCat.contains("credit card payment") || lowerName.hasPrefix("transfer to ") || lowerName.hasPrefix("transfer from ") || lowerName.hasPrefix("transfer: ") || lowerName.hasPrefix("credit card payment") {
                self = .transfer
                return
            }
            if CategoryStyle.style(for: categoryName ?? "").isIncome {
                self = .income
                return
            }
            self = .expense
            return
        }
        let lowerName = name.lowercased()
        let lowerCat = (categoryName ?? "").lowercased()
        if lowerCat.contains("transfer") || lowerCat.contains("credit card payment") || lowerName.hasPrefix("transfer to ") || lowerName.hasPrefix("transfer from ") || lowerName.hasPrefix("transfer: ") || lowerName.hasPrefix("credit card payment") {
            self = .transfer
        } else if CategoryStyle.style(for: categoryName ?? "").isIncome {
            self = .income
        } else {
            self = .expense
        }
    }
}

// MARK: - Recurring Payment / Membership Model
public struct RecurringPayment: Identifiable, Hashable, Codable {
    public let id: String
    public var name: String
    public var amount: Double
    public var categoryID: Int?
    public var categoryName: String?
    public var accountID: String?
    public var frequency: RecurringFrequency
    public var startDate: String // "yyyy-MM-dd"
    public var nextDueDate: String // "yyyy-MM-dd"
    public var isActive: Bool
    public var notes: String?
    public var type: RecurringTransactionType
    
    public init(id: String = UUID().uuidString,
                name: String,
                amount: Double,
                categoryID: Int? = nil,
                categoryName: String? = nil,
                accountID: String? = nil,
                frequency: RecurringFrequency = .monthly,
                startDate: String,
                nextDueDate: String,
                isActive: Bool = true,
                notes: String? = nil,
                type: RecurringTransactionType = .expense) {
        self.id = id
        self.name = name
        self.amount = amount
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.accountID = accountID
        self.frequency = frequency
        self.startDate = startDate
        self.nextDueDate = nextDueDate
        self.isActive = isActive
        self.notes = notes
        self.type = type
    }
    
    public var normalizedMonthlyAmount: Double {
        amount * frequency.multiplierToMonthly
    }
}

// MARK: - Transaction Model
public struct Transaction: Identifiable, Hashable {
    public var id: String { uuid }
    public let uuid: String
    public let date: Date
    public let amount: Double // Positive for expenses, Negative for income
    public let categoryID: Int?
    public let categoryName: String?
    public let merchant: String
    public let source: String // "manual", "csv", "ai", "transfer"
    public let accountID: String?
    public let subCategory: String?
    public let notes: String?
    public let txHash: String?
    public let isRecurring: Bool
    public let recurringFrequency: String?
    public let transferPairID: String?
    public let refundOriginalUUID: String?
    
    public init(uuid: String = UUID().uuidString,
                date: Date,
                amount: Double,
                categoryID: Int?,
                categoryName: String?,
                merchant: String,
                source: String,
                accountID: String? = nil,
                subCategory: String? = nil,
                notes: String? = nil,
                txHash: String? = nil,
                isRecurring: Bool = false,
                recurringFrequency: String? = nil,
                transferPairID: String? = nil,
                refundOriginalUUID: String? = nil) {
        self.uuid = uuid
        self.date = date
        self.amount = amount
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.merchant = merchant
        self.source = source
        self.accountID = accountID
        self.subCategory = subCategory
        self.notes = notes
        self.txHash = txHash
        self.isRecurring = isRecurring
        self.recurringFrequency = recurringFrequency
        self.transferPairID = transferPairID
        self.refundOriginalUUID = refundOriginalUUID
    }
    
    /// Extracts `#tag` tokens from merchant, subCategory, or notes string
    public var tags: [String] {
        var result: [String] = []
        if let sub = subCategory?.trimmingCharacters(in: .whitespacesAndNewlines), !sub.isEmpty {
            result.append(sub.hasPrefix("#") ? sub : "#\(sub)")
        }
        let words = merchant.components(separatedBy: .whitespacesAndNewlines)
        for word in words where word.hasPrefix("#") && word.count > 1 {
            if !result.contains(word) {
                result.append(word)
            }
        }
        if let noteWords = notes?.components(separatedBy: .whitespacesAndNewlines) {
            for word in noteWords where word.hasPrefix("#") && word.count > 1 {
                if !result.contains(word) {
                    result.append(word)
                }
            }
        }
        return result
    }
}

// MARK: - Thread-Safe Static Formatter Cache
private enum FormatterCache {
    static let currencyTwoDecimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        return f
    }()
    
    static let currencyWhole: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        return f
    }()
    
    static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    
    static let mediumDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
    
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}

public extension Transaction {
    var isRefund: Bool {
        source == "refund" || refundOriginalUUID != nil
    }
    
    var isIncome: Bool {
        if isRefund { return false }
        return amount < 0 || CategoryStyle.style(for: categoryName ?? "").isIncome
    }
    
    /// Net contribution to spending (expenses are positive, refunds subtract from expenses, transfers/income are 0)
    var netExpenseImpact: Double {
        if source == "transfer" || isIncome { return 0.0 }
        if isRefund { return -abs(amount) }
        return abs(amount)
    }
    
    var displayAmount: Double {
        abs(amount)
    }
    
    var dateString: String { FormatterCache.isoDate.string(from: date) }
    var formattedDate: String { FormatterCache.mediumDate.string(from: date) }
    var relativeDateString: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return FormatterCache.shortDate.string(from: date)
    }
}

// MARK: - Color Hex Extension
public extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 10, 132, 255) // Default to system blue
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Time Period Filter
public enum TimePeriodFilter: String, CaseIterable, Identifiable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case yearly = "Yearly"
    
    public var id: String { rawValue }
}

// MARK: - Comma Number & Currency Formatter
public func formatCurrencyWithCommas(_ value: Double, showSign: Bool = false, symbol: String? = nil) -> String {
    let sym = symbol ?? (UserDefaults.standard.string(forKey: "selectedCurrencySymbol") ?? "$")
    let absVal = abs(value)
    let formatted = FormatterCache.currencyTwoDecimal.string(from: NSNumber(value: absVal)) ?? String(format: "%.2f", absVal)
    
    if value < -0.0001 {
        return "-\(sym)\(formatted)"
    } else if showSign && value > 0.0001 {
        return "+\(sym)\(formatted)"
    } else {
        return "\(sym)\(formatted)"
    }
}

public func formatWholeWithCommas(_ value: Double, symbol: String? = nil) -> String {
    let sym = symbol ?? (UserDefaults.standard.string(forKey: "selectedCurrencySymbol") ?? "$")
    let absVal = abs(value)
    let formatted = FormatterCache.currencyWhole.string(from: NSNumber(value: absVal)) ?? "\(Int(absVal))"
    return value < -0.0001 ? "-\(sym)\(formatted)" : "\(sym)\(formatted)"
}

// MARK: - Statement Import & Hash Reconciliation Models
public struct ImportedStatementBundle: Codable {
    public let statementHash: String
    public let account: String?
    public let institution: String?
    public let accountHint: String?
    public let periodStart: String?
    public let periodEnd: String?
    public let openingBalance: Double?
    public let closingBalance: Double?
    public let totalDebits: Double
    public let totalCredits: Double
    public let checksumVerified: Bool
    public let transactions: [ImportedTransactionItem]
    
    enum CodingKeys: String, CodingKey {
        case summary
        case transactions
        case statementHash = "statement_hash"
        case account
        case institution
        case accountHint = "account_hint"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case openingBalance = "opening_balance"
        case closingBalance = "closing_balance"
        case totalDebits = "total_debits"
        case totalCredits = "total_credits"
        case checksumVerified = "checksum_verified"
    }
    
    private struct NestedSummary: Codable {
        let statement_hash: String?
        let account: String?
        let institution: String?
        let account_hint: String?
        let period_start: String?
        let period_end: String?
        let opening_balance: Double?
        let closing_balance: Double?
        let parsed_total_debits: Double?
        let parsed_total_credits: Double?
        let total_debits: Double?
        let total_credits: Double?
        let checksum_verified: Bool?
    }
    
    public init(
        statementHash: String,
        account: String? = nil,
        institution: String? = nil,
        accountHint: String? = nil,
        periodStart: String? = nil,
        periodEnd: String? = nil,
        openingBalance: Double? = nil,
        closingBalance: Double? = nil,
        totalDebits: Double,
        totalCredits: Double,
        checksumVerified: Bool,
        transactions: [ImportedTransactionItem]
    ) {
        self.statementHash = statementHash
        self.account = account
        self.institution = institution
        self.accountHint = accountHint
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.openingBalance = openingBalance
        self.closingBalance = closingBalance
        self.totalDebits = totalDebits
        self.totalCredits = totalCredits
        self.checksumVerified = checksumVerified
        self.transactions = transactions
    }
    
    public init(from decoder: Decoder) throws {
        // Support both standard bundle object and top-level array of transactions
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let decodedTx = try? container.decode([ImportedTransactionItem].self, forKey: .transactions) {
            self.transactions = decodedTx
            
            if let nested = try? container.decode(NestedSummary.self, forKey: .summary) {
                self.statementHash = nested.statement_hash ?? ""
                self.account = nested.account ?? self.transactions.first?.account
                self.institution = nested.institution ?? self.transactions.first?.institution
                self.accountHint = nested.account_hint ?? self.transactions.first?.accountHint
                self.periodStart = nested.period_start
                self.periodEnd = nested.period_end
                self.openingBalance = nested.opening_balance
                self.closingBalance = nested.closing_balance
                self.totalDebits = nested.total_debits ?? nested.parsed_total_debits ?? 0.0
                self.totalCredits = nested.total_credits ?? nested.parsed_total_credits ?? 0.0
                self.checksumVerified = nested.checksum_verified ?? false
            } else {
                self.statementHash = (try? container.decode(String.self, forKey: .statementHash)) ?? ""
                self.account = (try? container.decode(String.self, forKey: .account)) ?? self.transactions.first?.account
                self.institution = (try? container.decode(String.self, forKey: .institution)) ?? self.transactions.first?.institution
                self.accountHint = (try? container.decode(String.self, forKey: .accountHint)) ?? self.transactions.first?.accountHint
                self.periodStart = try? container.decode(String.self, forKey: .periodStart)
                self.periodEnd = try? container.decode(String.self, forKey: .periodEnd)
                self.openingBalance = try? container.decode(Double.self, forKey: .openingBalance)
                self.closingBalance = try? container.decode(Double.self, forKey: .closingBalance)
                self.totalDebits = (try? container.decode(Double.self, forKey: .totalDebits)) ?? 0.0
                self.totalCredits = (try? container.decode(Double.self, forKey: .totalCredits)) ?? 0.0
                self.checksumVerified = (try? container.decode(Bool.self, forKey: .checksumVerified)) ?? false
            }
        } else {
            let singleContainer = try decoder.singleValueContainer()
            let decodedTx = try singleContainer.decode([ImportedTransactionItem].self)
            self.transactions = decodedTx
            self.statementHash = ""
            self.account = decodedTx.first?.account
            self.institution = decodedTx.first?.institution
            self.accountHint = decodedTx.first?.accountHint
            self.periodStart = decodedTx.map(\.date).min()
            self.periodEnd = decodedTx.map(\.date).max()
            self.openingBalance = nil
            self.closingBalance = nil
            self.totalDebits = decodedTx.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount }
            self.totalCredits = decodedTx.filter { $0.amount < 0 }.reduce(0) { $0 + abs($1.amount) }
            self.checksumVerified = true
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(statementHash, forKey: .statementHash)
        try container.encodeIfPresent(account, forKey: .account)
        try container.encodeIfPresent(institution, forKey: .institution)
        try container.encodeIfPresent(accountHint, forKey: .accountHint)
        try container.encodeIfPresent(periodStart, forKey: .periodStart)
        try container.encodeIfPresent(periodEnd, forKey: .periodEnd)
        try container.encodeIfPresent(openingBalance, forKey: .openingBalance)
        try container.encodeIfPresent(closingBalance, forKey: .closingBalance)
        try container.encode(totalDebits, forKey: .totalDebits)
        try container.encode(totalCredits, forKey: .totalCredits)
        try container.encode(checksumVerified, forKey: .checksumVerified)
        try container.encode(transactions, forKey: .transactions)
    }
}

public struct ImportedTransactionItem: Codable, Identifiable, Hashable {
    public var id: String { txHash }
    public let date: String // YYYY-MM-DD
    public let merchant: String
    public let rawMerchant: String?
    public let amount: Double // Positive = expense, Negative = income
    public var category: String
    public var subCategory: String?
    public var notes: String?
    public let txHash: String
    public let isTransfer: Bool
    public let account: String?
    public let institution: String?
    public let accountHint: String?
    
    enum CodingKeys: String, CodingKey {
        case date
        case merchant
        case rawMerchant = "raw_merchant"
        case amount
        case category
        case subCategory = "sub_category"
        case notes
        case txHash = "tx_hash"
        case isTransfer = "is_transfer"
        case account
        case institution
        case accountHint = "account_hint"
    }
    
    public init(
        date: String,
        merchant: String,
        rawMerchant: String? = nil,
        amount: Double,
        category: String,
        subCategory: String? = nil,
        notes: String? = nil,
        txHash: String,
        isTransfer: Bool = false,
        account: String? = nil,
        institution: String? = nil,
        accountHint: String? = nil
    ) {
        self.date = date
        self.merchant = merchant
        self.rawMerchant = rawMerchant
        self.amount = amount
        self.category = category
        self.subCategory = subCategory
        self.notes = notes
        self.txHash = txHash
        self.isTransfer = isTransfer
        self.account = account
        self.institution = institution
        self.accountHint = accountHint
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedDate = (try? container.decode(String.self, forKey: .date)) ?? ""
        let decodedMerchant = (try? container.decode(String.self, forKey: .merchant)) ?? "Transaction"
        let decodedRawMerchant = try? container.decode(String.self, forKey: .rawMerchant)
        
        let decodedAmount: Double
        if let dbl = try? container.decode(Double.self, forKey: .amount) {
            decodedAmount = dbl
        } else if let str = try? container.decode(String.self, forKey: .amount),
                  let parsed = Double(str.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespacesAndNewlines)) {
            decodedAmount = parsed
        } else {
            decodedAmount = 0.0
        }
        
        let decodedCategory = (try? container.decode(String.self, forKey: .category)) ?? "Miscellaneous"
        let decodedSubCategory = try? container.decode(String.self, forKey: .subCategory)
        let decodedNotes = try? container.decode(String.self, forKey: .notes)
        let decodedIsTransfer = (try? container.decode(Bool.self, forKey: .isTransfer)) ?? false
        let decodedAccount = try? container.decode(String.self, forKey: .account)
        let decodedInstitution = try? container.decode(String.self, forKey: .institution)
        let decodedAccountHint = try? container.decode(String.self, forKey: .accountHint)
        
        if let existingHash = try? container.decode(String.self, forKey: .txHash), !existingHash.isEmpty {
            self.txHash = existingHash
        } else {
            let payload = "\(decodedDate)|\(String(format: "%.2f", decodedAmount))|\(decodedRawMerchant ?? decodedMerchant)|\(decodedAccount ?? "")"
            let digest = SHA256.hash(data: Data(payload.utf8))
            self.txHash = digest.map { String(format: "%02x", $0) }.joined().prefix(24).description
        }
        
        self.date = decodedDate
        self.merchant = decodedMerchant
        self.rawMerchant = decodedRawMerchant
        self.amount = decodedAmount
        self.category = decodedCategory
        self.subCategory = decodedSubCategory
        self.notes = decodedNotes
        self.isTransfer = decodedIsTransfer
        self.account = decodedAccount
        self.institution = decodedInstitution
        self.accountHint = decodedAccountHint
    }
}

public enum ReconciliationMatchType: String, Hashable {
    case exactHashDuplicate // Skip: identical tx_hash already in SQLite
    case fuzzyManualMerge   // Merge: manual entry within ±3 days with identical amount
    case newInsert          // Insert: brand new transaction
}

public struct ReconciledTransactionPreview: Identifiable, Hashable {
    public let id: String
    public var item: ImportedTransactionItem
    public let matchType: ReconciliationMatchType
    public let matchedTransactionUUID: String?
    public let matchedMerchant: String?
    public let matchedDate: String?
    public var isSelected: Bool
    
    public init(
        id: String = UUID().uuidString,
        item: ImportedTransactionItem,
        matchType: ReconciliationMatchType,
        matchedTransactionUUID: String? = nil,
        matchedMerchant: String? = nil,
        matchedDate: String? = nil,
        isSelected: Bool = true
    ) {
        self.id = id
        self.item = item
        self.matchType = matchType
        self.matchedTransactionUUID = matchedTransactionUUID
        self.matchedMerchant = matchedMerchant
        self.matchedDate = matchedDate
        self.isSelected = isSelected
    }
}

public struct StatementReconciliationPlan {
    public let bundle: ImportedStatementBundle
    public let isStatementAlreadyImported: Bool
    public var items: [ReconciledTransactionPreview]
    
    public let newCount: Int
    public let fuzzyMatchCount: Int
    public var mergedCount: Int { fuzzyMatchCount }
    public let exactDuplicateCount: Int
    public var duplicateCount: Int { exactDuplicateCount }
    
    public init(
        bundle: ImportedStatementBundle,
        isStatementAlreadyImported: Bool,
        items: [ReconciledTransactionPreview]
    ) {
        self.bundle = bundle
        self.isStatementAlreadyImported = isStatementAlreadyImported
        self.items = items
        
        var newC = 0
        var fuzzyC = 0
        var dupC = 0
        for item in items {
            switch item.matchType {
            case .newInsert: newC += 1
            case .fuzzyManualMerge: fuzzyC += 1
            case .exactHashDuplicate: dupC += 1
            }
        }
        self.newCount = newC
        self.fuzzyMatchCount = fuzzyC
        self.exactDuplicateCount = dupC
    }
}
