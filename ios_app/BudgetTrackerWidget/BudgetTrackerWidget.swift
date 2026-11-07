import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Configurable Expense Category & Timeframe Options for Long-Press "Edit Widget"
enum WidgetCategoryChoice: String, AppEnum {
    case appSettings = "Use App Selection"
    case grocery = "Grocery"
    case foodAndDrink = "Food & Drink"
    case transportation = "Transportation"
    case shopping = "Shopping"
    case socialLife = "Social Life"
    case housingUtilities = "Housing & Utilities"
    case healthCare = "Health Care"
    case membership = "Membership"
    case personalCare = "Personal Care"
    case giving = "Giving"
    case miscellaneous = "Miscellaneous"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Expense Category"
    
    static var caseDisplayRepresentations: [WidgetCategoryChoice: DisplayRepresentation] = [
        .appSettings: "Use In-App Widget Selection",
        .grocery: "🛒 Grocery",
        .foodAndDrink: "🍽️ Food & Drink",
        .transportation: "🚇 Transportation",
        .shopping: "🛍️ Shopping",
        .socialLife: "🎉 Social Life",
        .housingUtilities: "⚡ Housing & Utilities",
        .healthCare: "🩺 Health Care",
        .membership: "🔁 Membership",
        .personalCare: "💖 Personal Care",
        .giving: "🤲 Giving",
        .miscellaneous: "🏷️ Miscellaneous"
    ]
}

enum WidgetGridCountChoice: String, AppEnum {
    case fourIcons = "4 Icons (1×4 Row)"
    case eightIcons = "8 Icons (2×4 Grid)"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Icon Layout"
    
    static var caseDisplayRepresentations: [WidgetGridCountChoice: DisplayRepresentation] = [
        .fourIcons: "4 Expense Icons (1×4 Row with Spend Values)",
        .eightIcons: "8 Expense Icons (2×4 Wider Grid)"
    ]
}

enum WidgetTimeframeChoice: String, AppEnum {
    case appSettings = "Use App Selection"
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case yearly = "Yearly"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Spend Timeframe"
    
    static var caseDisplayRepresentations: [WidgetTimeframeChoice: DisplayRepresentation] = [
        .appSettings: "Use In-App Timeframe",
        .daily: "Today (Daily)",
        .weekly: "This Week (Weekly)",
        .monthly: "This Month (Monthly)",
        .yearly: "This Year (Yearly)"
    ]
}

struct QuickExpenseWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Expense Icons & Timeframe"
    static var description = IntentDescription("Choose your expense icons and timeframe to view category spending and log transactions with 1 tap.")
    
    @Parameter(title: "Layout Style", default: .fourIcons)
    var layoutStyle: WidgetGridCountChoice
    
    @Parameter(title: "Spend Timeframe", default: .appSettings)
    var timeframe: WidgetTimeframeChoice
    
    @Parameter(title: "Icon 1", default: .appSettings)
    var slot1: WidgetCategoryChoice
    
    @Parameter(title: "Icon 2", default: .appSettings)
    var slot2: WidgetCategoryChoice
    
    @Parameter(title: "Icon 3", default: .appSettings)
    var slot3: WidgetCategoryChoice
    
    @Parameter(title: "Icon 4", default: .appSettings)
    var slot4: WidgetCategoryChoice
    
    @Parameter(title: "Icon 5", default: .appSettings)
    var slot5: WidgetCategoryChoice
    
    @Parameter(title: "Icon 6", default: .appSettings)
    var slot6: WidgetCategoryChoice
    
    @Parameter(title: "Icon 7", default: .appSettings)
    var slot7: WidgetCategoryChoice
    
    @Parameter(title: "Icon 8", default: .appSettings)
    var slot8: WidgetCategoryChoice
}

// MARK: - Timeline Entry & Provider
struct QuickExpenseWidgetEntry: TimelineEntry {
    let date: Date
    let shortcuts: [WidgetExpenseShortcut]
    let categoryAmounts: [String: Double]
    let timeframeTotalSpend: Double
    let timeframe: WidgetTimeframe
    let currencySymbol: String
    let layoutStyle: WidgetGridCountChoice
}

struct QuickExpenseWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuickExpenseWidgetEntry {
        QuickExpenseWidgetEntry(
            date: Date(),
            shortcuts: Array(WidgetExpenseShortcut.defaultCatalog.prefix(4)),
            categoryAmounts: [
                "grocery": 245.0,
                "food & drink": 118.0,
                "transportation": 64.0,
                "shopping": 92.0
            ],
            timeframeTotalSpend: 519.0,
            timeframe: .monthly,
            currencySymbol: "$",
            layoutStyle: .fourIcons
        )
    }
    
    func snapshot(for configuration: QuickExpenseWidgetIntent, in context: Context) async -> QuickExpenseWidgetEntry {
        makeEntry(for: configuration)
    }
    
    func timeline(for configuration: QuickExpenseWidgetIntent, in context: Context) async -> Timeline<QuickExpenseWidgetEntry> {
        let entry = makeEntry(for: configuration)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
    
    private func makeEntry(for configuration: QuickExpenseWidgetIntent) -> QuickExpenseWidgetEntry {
        let payload = WidgetDataStore.loadSnapshot()
        let baseShortcuts = payload.selectedShortcuts
        
        let resolvedTimeframe: WidgetTimeframe = {
            if configuration.timeframe != .appSettings,
               let tf = WidgetTimeframe(rawValue: configuration.timeframe.rawValue) {
                return tf
            }
            return payload.selectedTimeframe
        }()
        
        let slotChoices = [
            configuration.slot1, configuration.slot2, configuration.slot3, configuration.slot4,
            configuration.slot5, configuration.slot6, configuration.slot7, configuration.slot8
        ]
        
        let hasAnySlotOverride = slotChoices.contains { $0 != .appSettings }
        let effectiveLayout: WidgetGridCountChoice = {
            if !hasAnySlotOverride && configuration.layoutStyle == .fourIcons && baseShortcuts.count > 4 {
                return .eightIcons
            }
            return configuration.layoutStyle
        }()
        
        let maxCount = effectiveLayout == .fourIcons ? 4 : 8
        var resolved: [WidgetExpenseShortcut] = []
        
        for idx in 0..<maxCount {
            let choice = slotChoices[idx]
            if choice != .appSettings {
                resolved.append(WidgetExpenseShortcut(name: choice.rawValue))
            } else if idx < baseShortcuts.count {
                resolved.append(baseShortcuts[idx])
            } else if idx < WidgetExpenseShortcut.defaultCatalog.count {
                resolved.append(WidgetExpenseShortcut.defaultCatalog[idx])
            }
        }
        
        var catAmounts: [String: Double] = [:]
        for item in resolved {
            let key = item.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            catAmounts[key] = payload.spend(forCategory: item.name, timeframe: resolvedTimeframe)
        }
        
        return QuickExpenseWidgetEntry(
            date: Date(),
            shortcuts: resolved,
            categoryAmounts: catAmounts,
            timeframeTotalSpend: payload.totalSpend(for: resolvedTimeframe),
            timeframe: resolvedTimeframe,
            currencySymbol: payload.currencySymbol,
            layoutStyle: effectiveLayout
        )
    }
}

// MARK: - Wider Widget View (.systemMedium & .systemLarge)
struct QuickExpenseWidgetEntryView: View {
    var entry: QuickExpenseWidgetEntry
    @Environment(\.widgetFamily) var family
    
    private var isSingleRow1x4: Bool {
        entry.layoutStyle == .fourIcons || entry.shortcuts.count <= 4
    }
    
    private var displayedShortcuts: [WidgetExpenseShortcut] {
        let limit = isSingleRow1x4 ? 4 : 8
        return Array(entry.shortcuts.prefix(limit))
    }
    
    private func spendAmount(for shortcut: WidgetExpenseShortcut) -> Double {
        let key = shortcut.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return entry.categoryAmounts[key] ?? 0.0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 14 : 9) {
            headerBar
            
            if isSingleRow1x4 {
                singleRow1x4Grid
            } else {
                twoRow2x4Grid
            }
            
            if family == .systemLarge {
                largeFooterSection
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var headerBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.22))
                        .frame(width: 20, height: 20)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(red: 0.04, green: 0.52, blue: 1.0))
                }
                
                Text("QUICK LOG")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.88))
                    .kerning(0.5)
            }
            
            Spacer()
            
            // Active Timeframe & Total Spend Badge (No Custom button)
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color(red: 0.04, green: 0.52, blue: 1.0))
                
                Text(entry.timeframe.formattedFrameLabel(for: entry.date))
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                
                Text("•")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
                
                Text(WidgetSnapshotPayload.formatCompactAmount(entry.timeframeTotalSpend, currencySymbol: entry.currencySymbol))
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(red: 0.19, green: 0.82, blue: 0.35))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
    }
    
    @ViewBuilder
    private var singleRow1x4Grid: some View {
        HStack(spacing: 8) {
            ForEach(displayedShortcuts.prefix(4)) { item in
                shortcut1x4TileWithSpend(for: item)
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var twoRow2x4Grid: some View {
        let topRow = Array(displayedShortcuts.prefix(4))
        let bottomRow = Array(displayedShortcuts.dropFirst(4).prefix(4))
        
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                ForEach(topRow) { item in
                    shortcutCompactTile(for: item)
                }
            }
            if !bottomRow.isEmpty {
                HStack(spacing: 8) {
                    ForEach(bottomRow) { item in
                        shortcutCompactTile(for: item)
                    }
                    if bottomRow.count < 4 {
                        ForEach(0..<(4 - bottomRow.count), id: \.self) { _ in
                            Spacer().frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func shortcut1x4TileWithSpend(for item: WidgetExpenseShortcut) -> some View {
        let accent = item.swiftUIColor
        let catSpend = spendAmount(for: item)
        let formattedSpend = WidgetSnapshotPayload.formatCompactAmount(catSpend, currencySymbol: entry.currencySymbol)
        
        Link(destination: WidgetDataStore.quickLogURL(for: item.name)) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.22))
                        .frame(width: 34, height: 34)
                    Image(systemName: item.iconName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(accent)
                }
                
                Text(item.shortLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                
                Text(formattedSpend)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(catSpend > 0 ? accent : .white.opacity(0.45))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(accent.opacity(catSpend > 0 ? 0.16 : 0.08))
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 7)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.11, green: 0.11, blue: 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accent.opacity(0.34), lineWidth: 0.8)
            )
        }
    }
    
    @ViewBuilder
    private func shortcutCompactTile(for item: WidgetExpenseShortcut) -> some View {
        let accent = item.swiftUIColor
        Link(destination: WidgetDataStore.quickLogURL(for: item.name)) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.22))
                        .frame(width: 28, height: 28)
                    Image(systemName: item.iconName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(accent)
                }
                
                Text(item.shortLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 5)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.11, green: 0.11, blue: 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(accent.opacity(0.32), lineWidth: 0.7)
            )
        }
    }
    
    @ViewBuilder
    private var largeFooterSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.timeframe.formattedFrameLabel(for: entry.date))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                Text("\(entry.currencySymbol)\(String(format: "%.2f", entry.timeframeTotalSpend))")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            }
            Spacer()
            Link(destination: WidgetDataStore.customizeWidgetURL) {
                HStack(spacing: 5) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Edit Icons")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.12))
        )
    }
}

// MARK: - Widget Definition & Bundle
struct QuickLogExpenseWidget: Widget {
    let kind: String = "QuickLogExpenseWidget"
    
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: QuickExpenseWidgetIntent.self,
            provider: QuickExpenseWidgetProvider()
        ) { entry in
            QuickExpenseWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(red: 0.04, green: 0.04, blue: 0.05)
                }
        }
        .configurationDisplayName("Quick Expense Logger")
        .description("Wider widget with customizable expense category icons, timeframe spend values, and 1-tap instant transaction logging.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct BudgetTrackerWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickLogExpenseWidget()
    }
}
