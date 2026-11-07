import Foundation
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - Widget Timeframe (Daily, Weekly, Monthly, Yearly)
public enum WidgetTimeframe: String, CaseIterable, Identifiable, Codable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case yearly = "Yearly"
    
    public var id: String { rawValue }
    
    public var badgeTitle: String {
        switch self {
        case .daily: return "TODAY"
        case .weekly: return "THIS WEEK"
        case .monthly: return "THIS MONTH"
        case .yearly: return "THIS YEAR"
        }
    }
    
    public func formattedFrameLabel(for date: Date = Date()) -> String {
        let calendar = Calendar.current
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        
        switch self {
        case .daily:
            fmt.dateFormat = "MMM d"
            return "TODAY • \(fmt.string(from: date).uppercased())"
        case .weekly:
            let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) ?? date
            let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek) ?? date
            fmt.dateFormat = "MMM d"
            let startStr = fmt.string(from: startOfWeek).uppercased()
            let endDayFmt = DateFormatter()
            endDayFmt.locale = Locale(identifier: "en_US_POSIX")
            endDayFmt.dateFormat = calendar.isDate(startOfWeek, equalTo: endOfWeek, toGranularity: .month) ? "d" : "MMM d"
            let endStr = endDayFmt.string(from: endOfWeek).uppercased()
            return "WEEK • \(startStr)–\(endStr)"
        case .monthly:
            fmt.dateFormat = "MMM yyyy"
            return "MONTH • \(fmt.string(from: date).uppercased())"
        case .yearly:
            fmt.dateFormat = "yyyy"
            return "YEAR • \(fmt.string(from: date))"
        }
    }
    
    public func dateRange(from now: Date = Date()) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        switch self {
        case .daily:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? now
            return (start, end)
        case .weekly:
            let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            let end = calendar.date(byAdding: DateComponents(day: 7, second: -1), to: start) ?? now
            return (start, end)
        case .monthly:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? now
            return (start, end)
        case .yearly:
            let start = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
            let end = calendar.date(byAdding: DateComponents(year: 1, second: -1), to: start) ?? now
            return (start, end)
        }
    }
}

// MARK: - Shared Widget Models & Storage (Used by Main App + Widget Extension)

public struct WidgetExpenseShortcut: Codable, Identifiable, Equatable, Hashable {
    public var id: String { name }
    public let name: String
    public let shortLabel: String
    public let iconName: String
    public let colorHex: String
    
    public init(name: String, shortLabel: String? = nil, iconName: String? = nil, colorHex: String? = nil) {
        self.name = name
        self.shortLabel = shortLabel ?? Self.defaultShortLabel(for: name)
        self.iconName = iconName ?? Self.defaultIcon(for: name)
        self.colorHex = colorHex ?? Self.defaultColorHex(for: name)
    }
    
    public var swiftUIColor: Color {
        Self.color(fromHex: colorHex)
    }
    
    public static func defaultShortLabel(for name: String) -> String {
        let lower = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.contains("grocer") { return "Grocery" }
        if lower.contains("food") || lower.contains("drink") || lower.contains("dining") { return "Food" }
        if lower.contains("social") || lower.contains("entertainment") { return "Social" }
        if lower.contains("transport") || lower.contains("transit") || lower.contains("gas") { return "Transit" }
        if lower.contains("hous") || lower.contains("utilit") || lower.contains("rent") { return "Utilities" }
        if lower.contains("personal") || lower.contains("care") { return "Personal" }
        if lower.contains("shop") { return "Shopping" }
        if lower.contains("health") || lower.contains("medic") { return "Health" }
        if lower.contains("member") || lower.contains("subscri") { return "Members" }
        if lower.contains("giving") || lower.contains("charity") { return "Giving" }
        if lower.contains("misc") { return "Misc" }
        return String(name.prefix(10))
    }
    
    public static func defaultIcon(for name: String) -> String {
        let lower = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.contains("grocer") || lower.contains("food mart") || lower.contains("market") {
            return "cart.fill"
        } else if lower.contains("food") || lower.contains("drink") || lower.contains("dining") || lower.contains("restaurant") || lower.contains("coffee") || lower.contains("cafe") {
            return "fork.knife"
        } else if lower.contains("social") || lower.contains("party") || lower.contains("nightlife") || lower.contains("entertainment") || lower.contains("fun") {
            return "sparkles"
        } else if lower.contains("transport") || lower.contains("transit") || lower.contains("bus") || lower.contains("train") || lower.contains("subway") || lower.contains("uber") || lower.contains("gas") {
            return "tram.fill"
        } else if lower.contains("hous") || lower.contains("utilit") || lower.contains("rent") || lower.contains("water") || lower.contains("power") || lower.contains("electric") {
            return "bolt.fill"
        } else if lower.contains("personal") || lower.contains("care") || lower.contains("beauty") || lower.contains("salon") || lower.contains("hair") {
            return "heart.fill"
        } else if lower.contains("shop") || lower.contains("cloth") || lower.contains("fashion") || lower.contains("retail") {
            return "bag.fill"
        } else if lower.contains("health") || lower.contains("medic") || lower.contains("doctor") || lower.contains("pharmacy") || lower.contains("dental") {
            return "cross.fill"
        } else if lower.contains("member") || lower.contains("subscri") || lower.contains("gym") || lower.contains("fitness") {
            return "repeat"
        } else if lower.contains("giving") || lower.contains("charity") || lower.contains("donation") {
            return "hand.raised.fill"
        } else {
            return "tag.fill"
        }
    }
    
    public static func defaultColorHex(for name: String) -> String {
        let lower = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.contains("grocer") || lower.contains("market") { return "#FF9F0A" }
        if lower.contains("food") || lower.contains("drink") || lower.contains("dining") || lower.contains("coffee") { return "#FF375F" }
        if lower.contains("social") || lower.contains("entertainment") { return "#BF5AF2" }
        if lower.contains("transport") || lower.contains("transit") || lower.contains("gas") { return "#64D2FF" }
        if lower.contains("hous") || lower.contains("utilit") || lower.contains("rent") { return "#FFD60A" }
        if lower.contains("personal") || lower.contains("care") { return "#FF2D55" }
        if lower.contains("shop") { return "#5E5CE6" }
        if lower.contains("health") || lower.contains("medic") { return "#FF453A" }
        if lower.contains("member") || lower.contains("subscri") { return "#0A84FF" }
        if lower.contains("giving") { return "#63E6E2" }
        return "#8E8E93"
    }
    
    public static func color(fromHex hex: String) -> Color {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let r, g, b: UInt64
        switch clean.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (10, 132, 255)
        }
        return Color(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: 1.0
        )
    }
    
    public static let defaultCatalog: [WidgetExpenseShortcut] = [
        WidgetExpenseShortcut(name: "Grocery"),
        WidgetExpenseShortcut(name: "Food & Drink"),
        WidgetExpenseShortcut(name: "Transportation"),
        WidgetExpenseShortcut(name: "Shopping"),
        WidgetExpenseShortcut(name: "Social Life"),
        WidgetExpenseShortcut(name: "Housing & Utilities"),
        WidgetExpenseShortcut(name: "Health Care"),
        WidgetExpenseShortcut(name: "Membership"),
        WidgetExpenseShortcut(name: "Personal Care"),
        WidgetExpenseShortcut(name: "Giving"),
        WidgetExpenseShortcut(name: "Miscellaneous")
    ]
    
    public static let defaultSelectedCategoryNames: [String] = [
        "Grocery",
        "Food & Drink",
        "Transportation",
        "Shopping"
    ]
}

public struct WidgetSnapshotPayload: Codable {
    public var selectedCategoryNames: [String]
    public var allExpenseCategories: [WidgetExpenseShortcut]
    public var monthlySpendTotal: Double
    public var currencySymbol: String
    public var selectedTimeframeRaw: String
    public var categorySpendByTimeframe: [String: [String: Double]]
    public var totalSpendByTimeframe: [String: Double]
    public var updatedAt: Date
    
    public init(
        selectedCategoryNames: [String] = WidgetExpenseShortcut.defaultSelectedCategoryNames,
        allExpenseCategories: [WidgetExpenseShortcut] = WidgetExpenseShortcut.defaultCatalog,
        monthlySpendTotal: Double = 0.0,
        currencySymbol: String = "$",
        selectedTimeframeRaw: String = WidgetTimeframe.monthly.rawValue,
        categorySpendByTimeframe: [String: [String: Double]] = [:],
        totalSpendByTimeframe: [String: Double] = [:],
        updatedAt: Date = Date()
    ) {
        self.selectedCategoryNames = selectedCategoryNames
        self.allExpenseCategories = allExpenseCategories
        self.monthlySpendTotal = monthlySpendTotal
        self.currencySymbol = currencySymbol
        self.selectedTimeframeRaw = selectedTimeframeRaw
        self.categorySpendByTimeframe = categorySpendByTimeframe
        self.totalSpendByTimeframe = totalSpendByTimeframe
        self.updatedAt = updatedAt
    }
    
    public var selectedTimeframe: WidgetTimeframe {
        WidgetTimeframe(rawValue: selectedTimeframeRaw) ?? .monthly
    }
    
    public var selectedShortcuts: [WidgetExpenseShortcut] {
        let lookup = Dictionary(uniqueKeysWithValues: allExpenseCategories.map { ($0.name.lowercased(), $0) })
        let resolved = selectedCategoryNames.map { name -> WidgetExpenseShortcut in
            if let match = lookup[name.lowercased()] {
                return match
            }
            return WidgetExpenseShortcut(name: name)
        }
        return resolved.isEmpty ? Array(WidgetExpenseShortcut.defaultCatalog.prefix(4)) : resolved
    }
    
    public func spend(forCategory name: String, timeframe: WidgetTimeframe) -> Double {
        let key = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return categorySpendByTimeframe[timeframe.rawValue]?[key] ?? 0.0
    }
    
    public func totalSpend(for timeframe: WidgetTimeframe) -> Double {
        if let val = totalSpendByTimeframe[timeframe.rawValue] {
            return val
        }
        return timeframe == .monthly ? monthlySpendTotal : 0.0
    }
    
    public static func formatCompactAmount(_ amount: Double, currencySymbol: String) -> String {
        if amount <= 0.005 {
            return "\(currencySymbol)0"
        } else if amount >= 1000 {
            return String(format: "%@%.1fk", currencySymbol, amount / 1000.0)
        } else if amount.truncatingRemainder(dividingBy: 1) == 0 || amount >= 100 {
            return String(format: "%@%.0f", currencySymbol, amount)
        } else {
            return String(format: "%@%.2f", currencySymbol, amount)
        }
    }
}

public enum WidgetDataStore {
    public static let appGroupIdentifier = "group.com.localfirst.BudgetTracker"
    private static let snapshotDefaultsKey = "widget_snapshot_payload_v2"
    private static let selectedCategoriesDefaultsKey = "widget_selected_expense_categories_v2"
    private static let selectedTimeframeDefaultsKey = "widget_selected_timeframe_v1"
    private static let sharedFileName = "budget_tracker_widget_snapshot.json"
    
    private static var sharedFileURLs: [URL] {
        var urls: [URL] = []
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            urls.append(groupURL.appendingPathComponent(sharedFileName))
        }
        let simTmpURL = URL(fileURLWithPath: "/tmp").appendingPathComponent(sharedFileName)
        urls.append(simTmpURL)
        return urls
    }
    
    public static func loadSelectedCategoryNames() -> [String] {
        if let groupDefaults = UserDefaults(suiteName: appGroupIdentifier),
           let saved = groupDefaults.stringArray(forKey: selectedCategoriesDefaultsKey),
           !saved.isEmpty {
            return saved
        }
        if let saved = UserDefaults.standard.stringArray(forKey: selectedCategoriesDefaultsKey),
           !saved.isEmpty {
            return saved
        }
        let snapshot = loadSnapshot()
        if !snapshot.selectedCategoryNames.isEmpty {
            return snapshot.selectedCategoryNames
        }
        return WidgetExpenseShortcut.defaultSelectedCategoryNames
    }
    
    public static func saveSelectedCategoryNames(_ names: [String]) {
        let cleaned = names.isEmpty ? WidgetExpenseShortcut.defaultSelectedCategoryNames : names
        UserDefaults.standard.set(cleaned, forKey: selectedCategoriesDefaultsKey)
        UserDefaults(suiteName: appGroupIdentifier)?.set(cleaned, forKey: selectedCategoriesDefaultsKey)
        
        var current = loadSnapshot()
        current.selectedCategoryNames = cleaned
        current.updatedAt = Date()
        saveSnapshot(current)
    }
    
    public static func loadSelectedTimeframe() -> WidgetTimeframe {
        if let groupDefaults = UserDefaults(suiteName: appGroupIdentifier),
           let raw = groupDefaults.string(forKey: selectedTimeframeDefaultsKey),
           let tf = WidgetTimeframe(rawValue: raw) {
            return tf
        }
        if let raw = UserDefaults.standard.string(forKey: selectedTimeframeDefaultsKey),
           let tf = WidgetTimeframe(rawValue: raw) {
            return tf
        }
        return loadSnapshot().selectedTimeframe
    }
    
    public static func saveSelectedTimeframe(_ timeframe: WidgetTimeframe) {
        UserDefaults.standard.set(timeframe.rawValue, forKey: selectedTimeframeDefaultsKey)
        UserDefaults(suiteName: appGroupIdentifier)?.set(timeframe.rawValue, forKey: selectedTimeframeDefaultsKey)
        
        var current = loadSnapshot()
        current.selectedTimeframeRaw = timeframe.rawValue
        current.updatedAt = Date()
        saveSnapshot(current)
    }
    
    public static func saveSnapshot(_ payload: WidgetSnapshotPayload) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload) else { return }
        
        UserDefaults.standard.set(data, forKey: snapshotDefaultsKey)
        UserDefaults(suiteName: appGroupIdentifier)?.set(data, forKey: snapshotDefaultsKey)
        
        for url in sharedFileURLs {
            try? data.write(to: url, options: .atomic)
        }
        
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
    
    public static func loadSnapshot() -> WidgetSnapshotPayload {
        let decoder = JSONDecoder()
        
        if let groupDefaults = UserDefaults(suiteName: appGroupIdentifier),
           let data = groupDefaults.data(forKey: snapshotDefaultsKey),
           let decoded = try? decoder.decode(WidgetSnapshotPayload.self, from: data) {
            return decoded
        }
        
        for url in sharedFileURLs {
            if let data = try? Data(contentsOf: url),
               let decoded = try? decoder.decode(WidgetSnapshotPayload.self, from: data) {
                return decoded
            }
        }
        
        if let data = UserDefaults.standard.data(forKey: snapshotDefaultsKey),
           let decoded = try? decoder.decode(WidgetSnapshotPayload.self, from: data) {
            return decoded
        }
        
        return WidgetSnapshotPayload()
    }
    
    // MARK: - Deep Link URL Builders & Parsers
    
    public static func quickLogURL(for categoryName: String) -> URL {
        var components = URLComponents()
        components.scheme = "budgettracker"
        components.host = "quicklog"
        components.queryItems = [
            URLQueryItem(name: "category", value: categoryName)
        ]
        return components.url ?? URL(string: "budgettracker://quicklog")!
    }
    
    public static var customizeWidgetURL: URL {
        URL(string: "budgettracker://customize-widget")!
    }
}
