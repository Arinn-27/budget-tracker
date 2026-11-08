import SwiftUI
import Charts
import UniformTypeIdentifiers
import AppIntents

// MARK: - App Navigation Tab
enum AppTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case account = "Accounts"
    case cards = "Cards"
    case transactions = "Analytics"
    case setting = "Settings"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .home: return "dollarsign.circle.fill"
        case .account: return "building.columns.fill"
        case .cards: return "creditcard.fill"
        case .transactions: return "chart.pie.fill"
        case .setting: return "gearshape.fill"
        }
    }
}


// MARK: - Root Dashboard View
struct DashboardView: View {
    @ObservedObject var db = DatabaseManager.shared
    
    @State private var selectedTab: AppTab = .home
    @State private var showingInsightsSheet = false
    @State private var showingAddAccountSheet = false
    @State private var addAccountInitialType: AccountType = .debit
    @State private var showingTransferSheet = false
    @State private var transferSheetInitialMode: TransferMode = .betweenAccounts
    @State private var transferSheetInitialTargetID: String? = nil
    @State private var showingBudgetEditorSheet = false
    @State private var showingManualEntrySheet = false
    @AppStorage("hideBalances") private var hideBalances: Bool = false
    
    // Category Keypad Entry Sheet
    @State private var selectedCategoryForKeypad: Category? = nil
    
    // Account Detail Sheet
    @State private var selectedAccountForDetail: Account? = nil
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // True OLED Black Background
            AppleTheme.bgCanvas
                .ignoresSafeArea()
            
            // Tab Content Views
            TabView(selection: $selectedTab) {
                HomeTabView(
                    db: db,
                    onSelectCategory: { category in
                        selectedCategoryForKeypad = category
                    },
                    onOpenInsights: {
                        showingInsightsSheet = true
                    },
                    onOpenManualEntry: {
                        showingManualEntrySheet = true
                    },
                    onOpenTransactions: {
                        withAnimation { selectedTab = .transactions }
                    }
                )
                .tag(AppTab.home)
                
                AccountTabView(
                    db: db,
                    hideBalances: $hideBalances,
                    onAddAccount: {
                        addAccountInitialType = .debit
                        showingAddAccountSheet = true
                    },
                    onTransfer: {
                        transferSheetInitialMode = .betweenAccounts
                        transferSheetInitialTargetID = nil
                        showingTransferSheet = true
                    },
                    onSelectAccount: { account in
                        selectedAccountForDetail = account
                    },
                    onPayCreditCard: { account in
                        transferSheetInitialMode = .payCreditCard
                        transferSheetInitialTargetID = account.id
                        showingTransferSheet = true
                    }
                )
                .tag(AppTab.account)
                
                CardsTabView(
                    db: db,
                    hideBalances: $hideBalances,
                    onAddCard: {
                        addAccountInitialType = .credit
                        showingAddAccountSheet = true
                    },
                    onSelectCard: { account in
                        selectedAccountForDetail = account
                    },
                    onPayCreditCard: { account in
                        transferSheetInitialMode = .payCreditCard
                        transferSheetInitialTargetID = account.id
                        showingTransferSheet = true
                    }
                )
                .tag(AppTab.cards)
                
                TransactionsAnalyticsTabView(
                    db: db,
                    onEditBudgets: { showingBudgetEditorSheet = true },
                    onOpenManualEntry: { showingManualEntrySheet = true }
                )
                .tag(AppTab.transactions)
                
                SettingsTabView(
                    db: db,
                    hideBalances: $hideBalances,
                    onManageBudgets: { showingBudgetEditorSheet = true }
                )
                .tag(AppTab.setting)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)
            
            // Floating Overlay Controls for Home, Account & Cards tabs
            VStack {
                Spacer()
                
                HStack(alignment: .center) {
                    if selectedTab == .home {
                        // Lightbulb Insights Button
                        Button(action: {
                            triggerHaptic()
                            showingInsightsSheet = true
                        }) {
                            ZStack {
                                Circle()
                                    .fill(AppleTheme.bgCard)
                                    .frame(width: 46, height: 46)
                                    .overlay(Circle().stroke(AppleTheme.cardStroke, lineWidth: 0.5))
                                    .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
                                
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 19))
                                    .foregroundColor(AppleTheme.accentOrange)
                            }
                        }
                        .padding(.leading, 20)
                        
                        Spacer()
                        
                        // Plus Manual Entry Button
                        Button(action: {
                            triggerHaptic()
                            showingManualEntrySheet = true
                        }) {
                            ZStack {
                                Circle()
                                    .fill(AppleTheme.bgCard)
                                    .frame(width: 46, height: 46)
                                    .overlay(Circle().stroke(AppleTheme.cardStroke, lineWidth: 0.5))
                                    .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
                                
                                Image(systemName: "plus")
                                    .font(.system(size: 19, weight: .bold))
                                    .foregroundColor(AppleTheme.accentBlue)
                            }
                        }
                        .padding(.trailing, 20)
                    } else if selectedTab == .account {
                        Spacer()
                        
                        // Transfer Funds Floating Button
                        Button(action: {
                            triggerHaptic()
                            showingTransferSheet = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Transfer")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(AppleTheme.accentBlue)
                                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                            )
                            .shadow(color: AppleTheme.accentBlue.opacity(0.35), radius: 12, x: 0, y: 6)
                        }
                        .padding(.trailing, 20)
                    } else if selectedTab == .cards {
                        Spacer()
                        
                        // Add Credit Card Floating Button
                        Button(action: {
                            triggerHaptic()
                            addAccountInitialType = .credit
                            showingAddAccountSheet = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Add Card")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(AppleTheme.accentBlue)
                                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                            )
                            .shadow(color: AppleTheme.accentBlue.opacity(0.35), radius: 12, x: 0, y: 6)
                        }
                        .padding(.trailing, 20)
                    }
                }
                .padding(.bottom, 80)
            }
            .allowsHitTesting(selectedTab == .home || selectedTab == .account || selectedTab == .cards)
            
            // Custom Floating Bottom Navigation Dock (Apple HIG Style)
            FloatingBottomDock(selectedTab: $selectedTab)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
        }
        .sheet(item: $selectedCategoryForKeypad) { cat in
            CategoryKeypadEntryView(
                db: db,
                category: cat,
                onSetBudget: {
                    selectedCategoryForKeypad = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showingBudgetEditorSheet = true
                    }
                }
            )
            .presentationDetents([.fraction(0.88), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedAccountForDetail) { acc in
            AccountDetailSheetView(
                db: db,
                account: acc,
                onLogExpense: {
                    selectedAccountForDetail = nil
                    if let firstCat = db.categories.first {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            selectedCategoryForKeypad = firstCat
                        }
                    }
                },
                onTransfer: {
                    let targetID = selectedAccountForDetail?.id
                    selectedAccountForDetail = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        transferSheetInitialMode = .betweenAccounts
                        transferSheetInitialTargetID = targetID
                        showingTransferSheet = true
                    }
                },
                onPayCreditCard: {
                    let targetID = selectedAccountForDetail?.id
                    selectedAccountForDetail = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        transferSheetInitialMode = .payCreditCard
                        transferSheetInitialTargetID = targetID
                        showingTransferSheet = true
                    }
                }
            )
            .presentationDetents([.fraction(0.8), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingInsightsSheet) {
            InsightsSheetView(db: db, isPresented: $showingInsightsSheet)
                .presentationDetents([.fraction(0.8), .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAddAccountSheet) {
            AddAccountSheetView(
                db: db,
                isPresented: $showingAddAccountSheet,
                initialAccountType: addAccountInitialType
            )
            .id("add-account-\(addAccountInitialType.rawValue)-\(showingAddAccountSheet)")
            .presentationDetents([.fraction(0.88), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingTransferSheet) {
            TransferFundsSheetView(
                db: db,
                isPresented: $showingTransferSheet,
                initialMode: transferSheetInitialMode,
                initialTargetAccountID: transferSheetInitialTargetID
            )
            .id("transfer-\(transferSheetInitialMode.rawValue)-\(transferSheetInitialTargetID ?? "all")-\(showingTransferSheet)")
            .presentationDetents([.fraction(0.82), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingBudgetEditorSheet) {
            BudgetEditorView(isPresented: $showingBudgetEditorSheet)
        }
        .sheet(isPresented: $showingManualEntrySheet) {
            ManualEntryView(isPresented: $showingManualEntrySheet)
        }
        .onOpenURL { url in
            handleWidgetDeepLink(url)
        }
        .onChange(of: db.pendingQuickLogCategoryName) { _, newCategoryName in
            if let catName = newCategoryName, !catName.isEmpty {
                openKeypadForCategoryName(catName)
                db.pendingQuickLogCategoryName = nil
            }
        }
        .onChange(of: db.pendingOpenFullExpenseForm) { _, shouldOpen in
            if shouldOpen {
                openFullExpenseForm()
                db.pendingOpenFullExpenseForm = false
            }
        }
        .onAppear {
            if let catName = db.pendingQuickLogCategoryName, !catName.isEmpty {
                openKeypadForCategoryName(catName)
                db.pendingQuickLogCategoryName = nil
            } else if db.pendingOpenFullExpenseForm {
                openFullExpenseForm()
                db.pendingOpenFullExpenseForm = false
            }
        }
    }
    
    private func openFullExpenseForm() {
        showingInsightsSheet = false
        showingAddAccountSheet = false
        showingTransferSheet = false
        showingBudgetEditorSheet = false
        selectedAccountForDetail = nil
        selectedCategoryForKeypad = nil
        selectedTab = .home
        triggerHaptic()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            showingManualEntrySheet = true
        }
    }
    
    private func openKeypadForCategoryName(_ categoryName: String) {
        showingInsightsSheet = false
        showingAddAccountSheet = false
        showingTransferSheet = false
        showingBudgetEditorSheet = false
        selectedAccountForDetail = nil
        selectedTab = .home
        
        var targetCategory = db.categories.first(where: {
            $0.name.caseInsensitiveCompare(categoryName) == .orderedSame
        })
        if targetCategory == nil {
            db.addCategory(name: categoryName)
            targetCategory = db.categories.first(where: {
                $0.name.caseInsensitiveCompare(categoryName) == .orderedSame
            }) ?? Category(id: 999, name: categoryName)
        }
        if let resolvedCategory = targetCategory {
            triggerHaptic()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                selectedCategoryForKeypad = resolvedCategory
            }
        }
    }
    
    private func handleWidgetDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "budgettracker" else { return }
        let host = url.host?.lowercased() ?? ""
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        
        // Dismiss any active modals first so the quick-log sheet presents cleanly
        showingInsightsSheet = false
        showingAddAccountSheet = false
        showingTransferSheet = false
        showingBudgetEditorSheet = false
        selectedAccountForDetail = nil
        
        if host == "customize-widget" {
            selectedTab = .setting
            return
        }
        
        if queryItems.first(where: { $0.name == "manual" })?.value == "1" {
            selectedTab = .home
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                showingManualEntrySheet = true
            }
            return
        }
        
        if let categoryName = queryItems.first(where: { $0.name == "category" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !categoryName.isEmpty {
            selectedTab = .home
            var targetCategory = db.categories.first(where: {
                $0.name.caseInsensitiveCompare(categoryName) == .orderedSame
            })
            if targetCategory == nil {
                db.addCategory(name: categoryName)
                targetCategory = db.categories.first(where: {
                    $0.name.caseInsensitiveCompare(categoryName) == .orderedSame
                }) ?? Category(id: 999, name: categoryName)
            }
            if let resolvedCategory = targetCategory {
                triggerHaptic()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    selectedCategoryForKeypad = resolvedCategory
                }
            }
        }
    }
    
    private func triggerHaptic() {
        #if os(iOS)
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        #endif
    }
}

// MARK: - Floating Bottom Navigation Dock (Apple HIG Style)
struct FloatingBottomDock: View {
    @Binding var selectedTab: AppTab
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = selectedTab == tab
                
                Button(action: {
                    #if os(iOS)
                    let selectionFeedback = UISelectionFeedbackGenerator()
                    selectionFeedback.selectionChanged()
                    #endif
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedTab = tab
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 20, weight: isSelected ? .bold : .regular))
                            .foregroundColor(isSelected ? AppleTheme.accentBlue : AppleTheme.labelSecondary)
                            .frame(height: 24)
                        
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? .white : AppleTheme.labelTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isSelected ? Color.white.opacity(0.08) : Color.clear)
                    )
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 8)
    }
}

// Scale Button Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Tab 1: Home View (Apple Card Spending Summary + Apple Health Activity Bento)
struct HomeTabView: View {
    @ObservedObject var db: DatabaseManager
    var onSelectCategory: (Category) -> Void
    var onOpenInsights: (() -> Void)? = nil
    var onOpenManualEntry: (() -> Void)? = nil
    var onOpenTransactions: (() -> Void)? = nil
    
    @State private var filterPeriod: TimePeriodFilter = .monthly
    @State private var dateOffset: Int = 0
    @State private var selectedFlow: TransactionType = .expense
    @State private var editingTx: Transaction? = nil
    @AppStorage("homeBentoTileOrder") private var homeBentoTileOrderRaw: String = "dailyAverage,safeToSpend,topCategory,netCashFlow"
    @AppStorage("homeCategoryOrder") private var homeCategoryOrderRaw: String = ""
    @State private var draggedBentoTile: String? = nil
    @State private var draggedCategoryID: Int? = nil
    @State private var isEditingTileOrder: Bool = false
    
    enum TransactionType: String, CaseIterable, Identifiable {
        case expense = "Expenses"
        case income = "Income"
        var id: String { rawValue }
    }
    
    private static let monthTitleFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMMM yyyy"
        return df
    }()
    
    private var periodHeaderTitle: String {
        switch filterPeriod {
        case .daily: return dateOffset == 0 ? "Today" : (dateOffset == -1 ? "Yesterday" : "Day \(dateOffset)")
        case .weekly: return dateOffset == 0 ? "This Week" : (dateOffset == -1 ? "Last Week" : "Week \(dateOffset > 0 ? "+\(dateOffset)" : "\(dateOffset)")")
        case .monthly:
            if dateOffset == 0 {
                return "This Month"
            } else {
                let calendar = Calendar.current
                if let targetDate = calendar.date(byAdding: .month, value: dateOffset, to: Date()) {
                    return Self.monthTitleFormatter.string(from: targetDate)
                }
                return "Month \(dateOffset)"
            }
        case .yearly: return dateOffset == 0 ? "This Year" : "Year \(dateOffset)"
        }
    }
    
    private struct PeriodSummary {
        var transactions: [Transaction] = []
        var totalExpense: Double = 0.0
        var totalIncome: Double = 0.0
        var spendingByCategory: [Int: Double] = [:]
        var incomeByCategory: [Int: Double] = [:]
    }

    private var periodDateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        switch filterPeriod {
        case .daily:
            let target = calendar.date(byAdding: .day, value: dateOffset, to: now) ?? now
            let start = calendar.startOfDay(for: target)
            let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? target
            return (start, end)
        case .weekly:
            let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            let start = calendar.date(byAdding: .weekOfYear, value: dateOffset, to: startOfWeek) ?? startOfWeek
            let end = calendar.date(byAdding: DateComponents(day: 7, second: -1), to: start) ?? start
            return (start, end)
        case .monthly:
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            let start = calendar.date(byAdding: .month, value: dateOffset, to: startOfMonth) ?? startOfMonth
            let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? start
            return (start, end)
        case .yearly:
            let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
            let start = calendar.date(byAdding: .year, value: dateOffset, to: startOfYear) ?? startOfYear
            let end = calendar.date(byAdding: DateComponents(year: 1, second: -1), to: start) ?? start
            return (start, end)
        }
    }

    private var periodSummary: PeriodSummary {
        let range = periodDateRange
        var summary = PeriodSummary()
        var rawCategorySpend: [Int: Double] = [:]
        var rawTotalExpense = 0.0
        
        for tx in db.transactions {
            guard tx.date >= range.start && tx.date <= range.end else { continue }
            summary.transactions.append(tx)
            guard tx.source != "transfer", tx.transferPairID == nil else { continue }
            if let cat = tx.categoryName?.lowercased(), cat == "transfer" || cat == "transfers" { continue }
            
            if tx.isIncome {
                let amt = abs(tx.amount)
                summary.totalIncome += amt
                if let catID = tx.categoryID {
                    summary.incomeByCategory[catID, default: 0.0] += amt
                }
            } else {
                let impact = tx.netExpenseImpact
                rawTotalExpense += impact
                if let catID = tx.categoryID {
                    rawCategorySpend[catID, default: 0.0] += impact
                }
            }
        }
        summary.totalExpense = max(0.0, rawTotalExpense)
        for (catID, val) in rawCategorySpend {
            summary.spendingByCategory[catID] = max(0.0, val)
        }
        return summary
    }
    
    private var filteredTransactions: [Transaction] {
        periodSummary.transactions
    }
    
    private var totalExpense: Double {
        periodSummary.totalExpense
    }
    
    private var totalIncome: Double {
        periodSummary.totalIncome
    }
    
    private func spending(for categoryID: Int) -> Double {
        periodSummary.spendingByCategory[categoryID] ?? 0.0
    }
    
    private func income(for categoryID: Int) -> Double {
        periodSummary.incomeByCategory[categoryID] ?? 0.0
    }
    
    private var savedCategoryIDOrder: [Int] {
        homeCategoryOrderRaw
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }
    
    private func sortCategoriesByUserOrder(_ list: [Category]) -> [Category] {
        let order = savedCategoryIDOrder
        guard !order.isEmpty else { return list }
        var indexMap: [Int: Int] = [:]
        for (idx, id) in order.enumerated() {
            indexMap[id] = idx
        }
        return list.sorted { a, b in
            let idxA = indexMap[a.id] ?? Int.max
            let idxB = indexMap[b.id] ?? Int.max
            if idxA != idxB { return idxA < idxB }
            return a.id < b.id
        }
    }
    
    private func moveCategory(fromID: Int, toID: Int, in currentList: [Category]) {
        guard fromID != toID else { return }
        var ids = currentList.map { $0.id }
        guard let fromIdx = ids.firstIndex(of: fromID),
              let toIdx = ids.firstIndex(of: toID) else { return }
        let moved = ids.remove(at: fromIdx)
        ids.insert(moved, at: toIdx)
        
        // Merge with full category order so both expense and income category orders are preserved
        let otherIDs = db.categories.map { $0.id }.filter { !ids.contains($0) }
        let orderedOthers = sortCategoriesByUserOrder(db.categories.filter { otherIDs.contains($0.id) }).map { $0.id }
        let combined = ids + orderedOthers
        homeCategoryOrderRaw = combined.map(String.init).joined(separator: ",")
    }
    
    private func stepMoveCategory(id: Int, delta: Int, in currentList: [Category]) {
        let ids = currentList.map { $0.id }
        guard let idx = ids.firstIndex(of: id) else { return }
        let newIdx = max(0, min(ids.count - 1, idx + delta))
        guard newIdx != idx else { return }
        moveCategory(fromID: id, toID: ids[newIdx], in: currentList)
    }
    
    private var orderedBentoTiles: [String] {
        let defaultTiles = ["dailyAverage", "safeToSpend", "topCategory", "netCashFlow"]
        let saved = homeBentoTileOrderRaw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { defaultTiles.contains($0) }
        var result = saved
        for t in defaultTiles where !result.contains(t) {
            result.append(t)
        }
        return result
    }
    
    private func moveBentoTile(from: String, to: String) {
        guard from != to else { return }
        var current = orderedBentoTiles
        guard let fromIdx = current.firstIndex(of: from),
              let toIdx = current.firstIndex(of: to) else { return }
        let item = current.remove(at: fromIdx)
        current.insert(item, at: toIdx)
        homeBentoTileOrderRaw = current.joined(separator: ",")
    }
    
    private func stepMoveBentoTile(id: String, delta: Int) {
        let current = orderedBentoTiles
        guard let idx = current.firstIndex(of: id) else { return }
        let newIdx = max(0, min(current.count - 1, idx + delta))
        guard newIdx != idx else { return }
        moveBentoTile(from: id, to: current[newIdx])
    }
    
    private var expenseCategories: [Category] {
        sortCategoriesByUserOrder(db.categories.filter { !CategoryStyle.style(for: $0.name).isIncome })
    }
    
    private var incomeCategories: [Category] {
        sortCategoriesByUserOrder(db.categories.filter { CategoryStyle.style(for: $0.name).isIncome })
    }
    
    // Multi-segment category spending items for Apple Card spending bar
    private var categorySegments: [(name: String, amount: Double, color: Color, percentage: Double)] {
        guard totalExpense > 0 else { return [] }
        var result: [(name: String, amount: Double, color: Color, percentage: Double)] = []
        for cat in expenseCategories {
            let sp = spending(for: cat.id)
            if sp > 0 {
                let style = CategoryStyle.style(for: cat.name)
                result.append((cat.name, sp, style.color, sp / totalExpense))
            }
        }
        return result.sorted { $0.amount > $1.amount }
    }
    
    // Top category spent
    private var topCategory: (name: String, amount: Double, color: Color)? {
        guard let first = categorySegments.first else { return nil }
        return (first.name, first.amount, first.color)
    }
    
    // Safe to Spend metrics
    private var totalMonthlyBudget: Double {
        db.budgets.reduce(0) { $0 + $1.monthlyLimit }
    }
    
    private var currentMonthExpense: Double {
        if filterPeriod == .monthly && dateOffset == 0 {
            return periodSummary.totalExpense
        }
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: Date()) else { return 0.0 }
        let sum = db.transactions
            .filter { $0.date >= interval.start && $0.date < interval.end && $0.source != "transfer" && !$0.isIncome }
            .reduce(0.0) { $0 + $1.netExpenseImpact }
        return max(0.0, sum)
    }
    
    private var daysInCurrentMonth: Int {
        let calendar = Calendar.current
        let now = Date()
        return calendar.range(of: .day, in: .month, for: now)?.count ?? 30
    }
    
    private var currentDayOfMonth: Int {
        Calendar.current.component(.day, from: Date())
    }
    
    private var remainingDaysInMonth: Int {
        max(1, daysInCurrentMonth - currentDayOfMonth + 1)
    }
    
    private var dailyAverage: Double {
        let elapsed = max(1, currentDayOfMonth)
        return currentMonthExpense / Double(elapsed)
    }
    
    private var safeToSpendPerDay: Double {
        guard totalMonthlyBudget > 0 else { return 0 }
        let remaining = max(0, totalMonthlyBudget - currentMonthExpense)
        return remaining / Double(remainingDaysInMonth)
    }
    
    private var budgetExpectedPace: Double {
        Double(currentDayOfMonth) / Double(max(1, daysInCurrentMonth))
    }
    
    private var budgetActualSpendPace: Double {
        guard totalMonthlyBudget > 0 else { return 0 }
        return currentMonthExpense / totalMonthlyBudget
    }
    
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    /// Recent non-transfer transactions (income and expense only) for the Home page
    private var recentHomeTransactions: [Transaction] {
        db.transactions.filter { $0.source != "transfer" && $0.transferPairID == nil }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    
                    // Period Navigator Bar (< This Month >)
                    HStack {
                        Menu {
                            ForEach(TimePeriodFilter.allCases) { filter in
                                Button(filter.rawValue) {
                                    filterPeriod = filter
                                    dateOffset = 0
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(filterPeriod.rawValue)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(AppleTheme.accentBlue)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(AppleTheme.accentBlue)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppleTheme.bgCard)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(AppleTheme.cardStroke, lineWidth: 0.5))
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 14) {
                            Button(action: { dateOffset -= 1 }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(AppleTheme.labelSecondary)
                            }
                            
                            Text(periodHeaderTitle)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                            
                            Button(action: { dateOffset += 1 }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(dateOffset >= 0 ? AppleTheme.labelTertiary : AppleTheme.labelSecondary)
                            }
                            .disabled(dateOffset >= 0)
                        }
                        
                        Spacer()
                        
                        Button(action: { onOpenInsights?() }) {
                            ZStack {
                                Circle()
                                    .fill(AppleTheme.bgCard)
                                    .frame(width: 32, height: 32)
                                    .overlay(Circle().stroke(AppleTheme.cardStroke, lineWidth: 0.5))
                                
                                Image(systemName: "sparkles")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppleTheme.accentIndigo)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    
                    // MARK: - Apple Card Spending Summary Card
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedFlow == .expense ? "TOTAL SPENT" : "TOTAL INCOME")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(AppleTheme.labelSecondary)
                                    .kerning(0.8)
                                
                                Text(formatCurrencyWithCommas(selectedFlow == .expense ? totalExpense : totalIncome))
                                    .font(.system(size: 38, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(.white)
                                    .contentTransition(.numericText())
                            }
                            
                            Spacer()
                            
                            // Flow Picker (Expense vs Income)
                            HStack(spacing: 2) {
                                ForEach(TransactionType.allCases) { flow in
                                    let isSelected = selectedFlow == flow
                                    Button(action: {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                            selectedFlow = flow
                                        }
                                    }) {
                                        Text(flow.rawValue)
                                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                            .foregroundColor(isSelected ? .white : AppleTheme.labelSecondary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule()
                                                    .fill(isSelected ? (flow == .expense ? AppleTheme.accentRed : AppleTheme.accentGreen) : Color.clear)
                                            )
                                    }
                                }
                            }
                            .padding(3)
                            .background(AppleTheme.bgTertiary)
                            .clipShape(Capsule())
                        }
                        
                        // Apple Card Multi-Segment Horizontal Category Bar
                        if selectedFlow == .expense && !categorySegments.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                GeometryReader { geo in
                                    let totalW = geo.size.width
                                    HStack(spacing: 2) {
                                        ForEach(categorySegments, id: \.name) { seg in
                                            let segW = max(4, totalW * CGFloat(seg.percentage) - 2)
                                            Rectangle()
                                                .fill(seg.color)
                                                .frame(width: segW)
                                        }
                                    }
                                    .clipShape(Capsule())
                                }
                                .frame(height: 10)
                                
                                // Legend of Top 3 Categories
                                HStack(spacing: 12) {
                                    ForEach(categorySegments.prefix(3), id: \.name) { seg in
                                        HStack(spacing: 5) {
                                            Circle()
                                                .fill(seg.color)
                                                .frame(width: 7, height: 7)
                                            Text(seg.name)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(AppleTheme.labelSecondary)
                                            Text("\(Int(seg.percentage * 100))%")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                        } else if selectedFlow == .expense {
                            Text("No expenses logged for this period.")
                                .font(.system(size: 13))
                                .foregroundColor(AppleTheme.labelSecondary)
                        }
                    }
                    .padding(20)
                    .background(AppleTheme.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                            .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                    )
                    .padding(.horizontal, 20)
                    
                    // MARK: - 2-Column Bento Summary Tiles (Reorderable via Drag & Drop)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        ForEach(orderedBentoTiles, id: \.self) { tileID in
                            bentoTileView(for: tileID)
                                .overlay(alignment: .topTrailing) {
                                    if isEditingTileOrder {
                                        HStack(spacing: 4) {
                                            Button(action: {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                                    stepMoveBentoTile(id: tileID, delta: -1)
                                                }
                                            }) {
                                                Image(systemName: "arrow.left")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundColor(.white)
                                                    .padding(5)
                                                    .background(AppleTheme.bgTertiary)
                                                    .clipShape(Circle())
                                            }
                                            Button(action: {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                                    stepMoveBentoTile(id: tileID, delta: 1)
                                                }
                                            }) {
                                                Image(systemName: "arrow.right")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundColor(.white)
                                                    .padding(5)
                                                    .background(AppleTheme.bgTertiary)
                                                    .clipShape(Circle())
                                            }
                                        }
                                        .padding(6)
                                    }
                                }
                                .onDrag {
                                    draggedBentoTile = tileID
                                    return NSItemProvider(object: tileID as NSString)
                                }
                                .onDrop(
                                    of: [UTType.text],
                                    delegate: BentoTileDropDelegate(
                                        targetTile: tileID,
                                        draggedTile: $draggedBentoTile,
                                        onMove: { from, to in
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                                moveBentoTile(from: from, to: to)
                                            }
                                        }
                                    )
                                )
                                .contextMenu {
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                            stepMoveBentoTile(id: tileID, delta: -1)
                                        }
                                    } label: {
                                        Label("Move Earlier", systemImage: "arrow.up.left")
                                    }
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                            stepMoveBentoTile(id: tileID, delta: 1)
                                        }
                                    } label: {
                                        Label("Move Later", systemImage: "arrow.down.right")
                                    }
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                            isEditingTileOrder.toggle()
                                        }
                                    } label: {
                                        Label(isEditingTileOrder ? "Done Moving Tiles" : "Move Tiles Mode", systemImage: "square.grid.2x2")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // MARK: - Category Grid Section (Apple Fitness Activity Rings Style, Reorderable)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(selectedFlow == .expense ? "EXPENSE CATEGORIES" : "INCOME CATEGORIES")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(AppleTheme.labelSecondary)
                                .kerning(0.8)
                            
                            Spacer()
                            
                            Button(action: {
                                #if os(iOS)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    isEditingTileOrder.toggle()
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: isEditingTileOrder ? "checkmark.circle.fill" : "arrow.up.and.down.and.arrow.left.and.right")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(isEditingTileOrder ? "Done Moving" : "Move Tiles")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(isEditingTileOrder ? AppleTheme.accentGreen : AppleTheme.accentBlue)
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        let activeCategoryList = selectedFlow == .expense ? expenseCategories : incomeCategories
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(activeCategoryList) { cat in
                                let style = CategoryStyle.style(for: cat.name)
                                let amt = selectedFlow == .expense ? spending(for: cat.id) : income(for: cat.id)
                                let limit = selectedFlow == .expense ? (db.budgetsByCategoryID[cat.id] ?? 0.0) : 0.0
                                
                                CategoryCardView(
                                    name: cat.name,
                                    iconName: style.icon,
                                    badgeColor: style.color,
                                    amount: amt,
                                    budgetLimit: limit,
                                    onTap: {
                                        if isEditingTileOrder {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                                stepMoveCategory(id: cat.id, delta: -1, in: activeCategoryList)
                                            }
                                        } else {
                                            onSelectCategory(cat)
                                        }
                                    }
                                )
                                .overlay(alignment: .topTrailing) {
                                    if isEditingTileOrder {
                                        HStack(spacing: 2) {
                                            Button(action: {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                                    stepMoveCategory(id: cat.id, delta: -1, in: activeCategoryList)
                                                }
                                            }) {
                                                Image(systemName: "chevron.left")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .foregroundColor(.white)
                                                    .padding(4)
                                                    .background(AppleTheme.bgTertiary)
                                                    .clipShape(Circle())
                                            }
                                            Button(action: {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                                    stepMoveCategory(id: cat.id, delta: 1, in: activeCategoryList)
                                                }
                                            }) {
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .foregroundColor(.white)
                                                    .padding(4)
                                                    .background(AppleTheme.bgTertiary)
                                                    .clipShape(Circle())
                                            }
                                        }
                                        .padding(4)
                                    }
                                }
                                .onDrag {
                                    draggedCategoryID = cat.id
                                    return NSItemProvider(object: String(cat.id) as NSString)
                                }
                                .onDrop(
                                    of: [UTType.text],
                                    delegate: CategoryTileDropDelegate(
                                        targetCategoryID: cat.id,
                                        draggedCategoryID: $draggedCategoryID,
                                        onMove: { fromID, toID in
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                                moveCategory(fromID: fromID, toID: toID, in: activeCategoryList)
                                            }
                                        }
                                    )
                                )
                                .contextMenu {
                                    Button {
                                        onSelectCategory(cat)
                                    } label: {
                                        Label("Log \(cat.name)", systemImage: "plus.circle")
                                    }
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                            stepMoveCategory(id: cat.id, delta: -1, in: activeCategoryList)
                                        }
                                    } label: {
                                        Label("Move Left", systemImage: "arrow.left")
                                    }
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                            stepMoveCategory(id: cat.id, delta: 1, in: activeCategoryList)
                                        }
                                    } label: {
                                        Label("Move Right", systemImage: "arrow.right")
                                    }
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                            isEditingTileOrder.toggle()
                                        }
                                    } label: {
                                        Label(isEditingTileOrder ? "Done Moving Tiles" : "Move Tiles Mode", systemImage: "square.grid.2x2")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // MARK: - Recent Transactions Section (Apple HIG Inset Grouped, Income & Expense ONLY)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("RECENT TRANSACTIONS")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(AppleTheme.labelSecondary)
                                .kerning(0.8)
                            
                            Spacer()
                            
                            Button(action: { onOpenTransactions?() }) {
                                Text("See All")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(AppleTheme.accentBlue)
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        if recentHomeTransactions.isEmpty {
                            Text("No transactions yet. Tap '+' to create one.")
                                .font(.system(size: 14))
                                .foregroundColor(AppleTheme.labelSecondary)
                                .padding(.horizontal, 24)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(recentHomeTransactions.prefix(5).enumerated()), id: \.element.id) { index, tx in
                                    TransactionRowView(
                                        transaction: tx,
                                        db: db,
                                        onEdit: { editingTx = tx }
                                    )
                                    
                                    if index < min(recentHomeTransactions.count, 5) - 1 {
                                        Divider()
                                            .background(Color.white.opacity(0.06))
                                            .padding(.leading, 56)
                                    }
                                }
                            }
                            .background(AppleTheme.bgCard)
                            .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                                    .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                            )
                            .padding(.horizontal, 20)
                        }
                    }
                    
                    Spacer(minLength: 120)
                }
            }
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingTx) { tx in
                ManualEntryView(isPresented: Binding(
                    get: { editingTx != nil },
                    set: { if !$0 { editingTx = nil } }
                ), editingTransaction: tx)
            }
        }
    }
    
    @ViewBuilder
    private func bentoTileView(for tileID: String) -> some View {
        switch tileID {
        case "dailyAverage":
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("DAILY AVERAGE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppleTheme.labelSecondary)
                        .kerning(0.5)
                    Spacer()
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 12))
                        .foregroundColor(AppleTheme.accentBlue)
                }
                
                Text(formatCurrencyWithCommas(dailyAverage))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
                
                Text("Day \(currentDayOfMonth) of \(daysInCurrentMonth)")
                    .font(.system(size: 11))
                    .foregroundColor(AppleTheme.labelTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(AppleTheme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: AppleTheme.compactCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppleTheme.compactCornerRadius, style: .continuous)
                    .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
            )
            
        case "safeToSpend":
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("SAFE TO SPEND")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppleTheme.labelSecondary)
                        .kerning(0.5)
                    Spacer()
                    
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 3)
                            .frame(width: 18, height: 18)
                        Circle()
                            .trim(from: 0, to: CGFloat(min(1.0, budgetActualSpendPace)))
                            .stroke(
                                budgetActualSpendPace >= 1.0 ? AppleTheme.accentRed :
                                    (budgetActualSpendPace > budgetExpectedPace * 1.15 ? AppleTheme.accentOrange : AppleTheme.accentGreen),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 18, height: 18)
                    }
                }
                
                Text(totalMonthlyBudget > 0 ? "\(formatWholeWithCommas(safeToSpendPerDay))/day" : "No budget")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
                
                let isOver = budgetActualSpendPace > budgetExpectedPace * 1.15
                Text(totalMonthlyBudget > 0 ? (isOver ? "Pace: Ahead of Budget" : "Pace: On Track") : "Tap to configure")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(totalMonthlyBudget > 0 ? (isOver ? AppleTheme.accentOrange : AppleTheme.accentGreen) : AppleTheme.labelTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(AppleTheme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: AppleTheme.compactCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppleTheme.compactCornerRadius, style: .continuous)
                    .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
            )
            
        case "topCategory":
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("TOP CATEGORY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppleTheme.labelSecondary)
                        .kerning(0.5)
                    Spacer()
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                        .foregroundColor(topCategory?.color ?? AppleTheme.accentIndigo)
                }
                
                Text(topCategory?.name ?? "None")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(topCategory != nil ? formatCurrencyWithCommas(topCategory!.amount) : "$0.00")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(AppleTheme.labelSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(AppleTheme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: AppleTheme.compactCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppleTheme.compactCornerRadius, style: .continuous)
                    .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
            )
            
        default: // "netCashFlow"
            let netFlow = totalIncome - totalExpense
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("NET CASH FLOW")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppleTheme.labelSecondary)
                        .kerning(0.5)
                    Spacer()
                    Image(systemName: netFlow >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(netFlow >= 0 ? AppleTheme.accentGreen : AppleTheme.accentRed)
                }
                
                Text(formatCurrencyWithCommas(netFlow, showSign: true))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(netFlow >= 0 ? AppleTheme.accentGreen : AppleTheme.accentRed)
                    .contentTransition(.numericText())
                
                Text(netFlow >= 0 ? "Surplus saved" : "Deficit this period")
                    .font(.system(size: 11))
                    .foregroundColor(AppleTheme.labelTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(AppleTheme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: AppleTheme.compactCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppleTheme.compactCornerRadius, style: .continuous)
                    .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
            )
        }
    }
}


// MARK: - Home Page Tile Drop Delegates
struct BentoTileDropDelegate: DropDelegate {
    let targetTile: String
    @Binding var draggedTile: String?
    let onMove: (String, String) -> Void
    
    func dropEntered(info: DropInfo) {
        guard let dragged = draggedTile, dragged != targetTile else { return }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        onMove(dragged, targetTile)
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        draggedTile = nil
        return true
    }
}

struct CategoryTileDropDelegate: DropDelegate {
    let targetCategoryID: Int
    @Binding var draggedCategoryID: Int?
    let onMove: (Int, Int) -> Void
    
    func dropEntered(info: DropInfo) {
        guard let dragged = draggedCategoryID, dragged != targetCategoryID else { return }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        onMove(dragged, targetCategoryID)
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        draggedCategoryID = nil
        return true
    }
}

// MARK: - Category Card View (Apple Fitness Rings Style)
struct CategoryCardView: View {
    let name: String
    let iconName: String
    let badgeColor: Color
    let amount: Double
    var budgetLimit: Double = 0.0
    let onTap: () -> Void
    
    private var hasBudget: Bool {
        budgetLimit > 0
    }
    
    private var spendRatio: Double {
        hasBudget ? amount / budgetLimit : 0.0
    }
    
    private var ringColor: Color {
        if !hasBudget { return Color.clear }
        if spendRatio >= 1.0 {
            return AppleTheme.accentRed
        } else if spendRatio >= 0.8 {
            return AppleTheme.accentOrange
        } else {
            return badgeColor
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                // Title
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppleTheme.labelPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                
                // Icon with Circular Progress Ring (Apple Fitness Activity Ring style)
                ZStack {
                    if hasBudget {
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 3)
                            .frame(width: 44, height: 44)
                        
                        Circle()
                            .trim(from: 0, to: CGFloat(min(1.0, spendRatio)))
                            .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 44, height: 44)
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: spendRatio)
                    }
                    
                    Circle()
                        .fill(badgeColor)
                        .frame(width: 36, height: 36)
                        .shadow(color: badgeColor.opacity(0.3), radius: 6, x: 0, y: 3)
                    
                    Image(systemName: iconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(width: 46, height: 46)
                
                // Spent Amount
                VStack(spacing: 1) {
                    Text(formatWholeWithCommas(amount))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    if hasBudget {
                        Text(spendRatio >= 1.0 ? "Over" : "\(Int(spendRatio * 100))%")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(spendRatio >= 1.0 ? AppleTheme.accentRed : AppleTheme.labelSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .background(AppleTheme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: AppleTheme.compactCornerRadius, style: .continuous))
            .overlay {
                if hasBudget && spendRatio >= 1.0 {
                    RoundedRectangle(cornerRadius: AppleTheme.compactCornerRadius, style: .continuous)
                        .stroke(AppleTheme.accentRed.opacity(0.5), lineWidth: 0.5)
                } else {
                    RoundedRectangle(cornerRadius: AppleTheme.compactCornerRadius, style: .continuous)
                        .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Tab 2: Accounts Tab (Apple Wallet / Apple Card Style)
struct AccountTabView: View {
    @ObservedObject var db: DatabaseManager
    @Binding var hideBalances: Bool
    var onAddAccount: () -> Void
    var onTransfer: () -> Void
    var onSelectAccount: (Account) -> Void
    var onPayCreditCard: ((Account) -> Void)? = nil
    
    @State private var filterAccountType: String = "All"
    @State private var showingNetWorthHistory = false
    @State private var editingAccount: Account? = nil
    @State private var addingSubAccountParent: Account? = nil
    @State private var showingStatementImport = false
    
    private var totalAssets: Double {
        db.totalAssets
    }
    
    private var totalLiabilities: Double {
        db.totalLiabilities
    }
    
    private var netWorth: Double {
        db.netWorth
    }
    
    private var displayedAccounts: [Account] {
        if filterAccountType == "All" {
            return db.accounts
        }
        return db.accounts.filter { $0.type.rawValue == filterAccountType }
    }
    
    private var cashAccounts: [Account] {
        if filterAccountType == "All" || filterAccountType == AccountType.debit.rawValue {
            return db.rootAccounts(for: .debit)
        }
        return []
    }
    
    private var savingsInvestAccounts: [Account] {
        displayedAccounts.filter { $0.type == .savings || $0.type == .investment }
    }
    
    private var creditAccounts: [Account] {
        displayedAccounts.filter { $0.type == .credit }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    
                    // Top Actions: Filter & Add Account
                    HStack(spacing: 10) {
                        Menu {
                            Button("All Accounts") { filterAccountType = "All" }
                            ForEach(AccountType.allCases) { type in
                                Button(type.rawValue) { filterAccountType = type.rawValue }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(filterAccountType == "All" ? "All Accounts" : filterAccountType)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(AppleTheme.accentBlue)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(AppleTheme.accentBlue)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(AppleTheme.bgCard)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(AppleTheme.cardStroke, lineWidth: 0.5))
                        }
                        
                        Spacer()
                        
                        Button(action: { showingStatementImport = true }) {
                            HStack(spacing: 5) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Import Statement")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(AppleTheme.accentBlue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppleTheme.bgCard)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(AppleTheme.cardStroke, lineWidth: 0.5))
                        }
                        
                        Button(action: onAddAccount) {
                            ZStack {
                                Circle()
                                    .fill(AppleTheme.bgCard)
                                    .frame(width: 32, height: 32)
                                    .overlay(Circle().stroke(AppleTheme.cardStroke, lineWidth: 0.5))
                                
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(AppleTheme.accentBlue)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    
                    // MARK: - Net Worth Hero Card (Apple Card Aesthetics)
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("TOTAL NET WORTH")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppleTheme.labelSecondary)
                                .kerning(0.8)
                            
                            Spacer()
                            
                            Button(action: {
                                #if os(iOS)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                                hideBalances.toggle()
                            }) {
                                Image(systemName: hideBalances ? "eye.slash.fill" : "eye.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppleTheme.labelSecondary)
                            }
                        }
                        
                        Text(hideBalances ? "••••••••" : formatCurrencyWithCommas(netWorth))
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .contentTransition(.numericText())
                        
                        Divider().background(Color.white.opacity(0.08))
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Circle().fill(AppleTheme.accentGreen).frame(width: 6, height: 6)
                                    Text("Assets")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(AppleTheme.labelSecondary)
                                }
                                Text(hideBalances ? "••••••" : formatCurrencyWithCommas(totalAssets))
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                HStack(spacing: 5) {
                                    Circle().fill(AppleTheme.accentRed).frame(width: 6, height: 6)
                                    Text("Liabilities")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(AppleTheme.labelSecondary)
                                }
                                Text(hideBalances ? "••••••" : formatCurrencyWithCommas(totalLiabilities))
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(AppleTheme.accentRed)
                            }
                        }
                    }
                    .padding(20)
                    .background(AppleTheme.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                            .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                    )
                    .padding(.horizontal, 20)
                    
                    // MARK: - Physical Apple Card Stack / Sections
                    if displayedAccounts.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "creditcard")
                                .font(.system(size: 40))
                                .foregroundColor(AppleTheme.labelTertiary)
                                .padding(.top, 24)
                            Text("No Accounts Added")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Add your bank accounts, savings, or credit cards to track balances and net worth.")
                                .font(.subheadline)
                                .foregroundColor(AppleTheme.labelSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                            
                            Button(action: onAddAccount) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus")
                                    Text("Add Account")
                                }
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 10)
                                .background(AppleTheme.accentBlue)
                                .clipShape(Capsule())
                            }
                            .padding(.top, 6)
                        }
                        .padding(.vertical, 20)
                    } else {
                        // CASH & BANKING: Debit Accounts with Parent/Child Hierarchy
                        if !cashAccounts.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("CASH & BANKING")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(AppleTheme.labelSecondary)
                                    .kerning(0.8)
                                    .padding(.horizontal, 24)
                                
                                VStack(spacing: 14) {
                                    ForEach(cashAccounts) { acc in
                                        HierarchicalAccountCardView(
                                            db: db,
                                            account: acc,
                                            depth: 0,
                                            hideBalance: hideBalances,
                                            onSelectAccount: onSelectAccount,
                                            onEditAccount: { editingAccount = $0 },
                                            onAddSubAccount: { addingSubAccountParent = $0 }
                                        )
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        
                        if !savingsInvestAccounts.isEmpty {
                            AccountCardSection(
                                title: "SAVINGS & INVESTMENTS",
                                accounts: savingsInvestAccounts,
                                hideBalance: hideBalances,
                                onSelectAccount: onSelectAccount,
                                onEditAccount: { editingAccount = $0 }
                            )
                        }
                        
                        if !creditAccounts.isEmpty {
                            AccountCardSection(
                                title: "CREDIT CARDS & LIABILITIES",
                                accounts: creditAccounts,
                                hideBalance: hideBalances,
                                onSelectAccount: onSelectAccount,
                                onEditAccount: { editingAccount = $0 },
                                onPayAccount: onPayCreditCard
                            )
                        }
                    }
                    
                    Spacer(minLength: 120)
                }
            }
            .navigationTitle("Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingAccount) { acc in
                EditAccountSheetView(
                    db: db,
                    account: acc,
                    isPresented: Binding(
                        get: { editingAccount != nil },
                        set: { if !$0 { editingAccount = nil } }
                    )
                )
                .presentationDetents([.fraction(0.85), .large])
            }
            .sheet(item: $addingSubAccountParent) { parentAcc in
                AddAccountSheetView(
                    db: db,
                    isPresented: Binding(
                        get: { addingSubAccountParent != nil },
                        set: { if !$0 { addingSubAccountParent = nil } }
                    ),
                    initialParentID: parentAcc.id,
                    initialAccountType: .debit
                )
                .presentationDetents([.fraction(0.85), .large])
            }
            .sheet(isPresented: $showingStatementImport) {
                StatementImportSheet(db: db, isPresented: $showingStatementImport)
            }
        }
    }
}


// MARK: - Recursive view supporting Root Debit Accounts -> Sub-Accounts -> Sub-Sub-Accounts (Collapsible)
struct HierarchicalAccountCardView: View {
    @ObservedObject var db: DatabaseManager
    let account: Account
    let depth: Int
    let hideBalance: Bool
    let onSelectAccount: (Account) -> Void
    var onEditAccount: ((Account) -> Void)? = nil
    var onAddSubAccount: ((Account) -> Void)? = nil
    
    @State private var isExpanded: Bool = true
    
    private var children: [Account] {
        db.subAccounts(of: account.id)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if depth > 0 {
                    HStack(spacing: 4) {
                        ForEach(0..<depth, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(AppleTheme.accentBlue.opacity(0.45))
                                .frame(width: 2, height: 64)
                                .padding(.leading, 8)
                        }
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppleTheme.labelSecondary)
                    }
                }
                
                PhysicalAccountCardView(
                    account: account,
                    hideBalance: hideBalance,
                    isSubAccount: depth > 0,
                    subAccountCount: children.count,
                    cumulativeBalance: db.effectiveBalance(for: account.id),
                    isExpanded: isExpanded,
                    onTap: { onSelectAccount(account) },
                    onEdit: { onEditAccount?(account) },
                    onAddSubAccount: (account.type == .debit && depth < 2) ? { onAddSubAccount?(account) } : nil,
                    onToggleExpand: children.isEmpty ? nil : {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            isExpanded.toggle()
                        }
                    },
                    onToggleIncludeInNetWorth: {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        db.toggleAccountIncludeInNetWorth(id: account.id)
                    }
                )
            }
            
            if !children.isEmpty && isExpanded {
                VStack(spacing: 8) {
                    ForEach(children) { child in
                        HierarchicalAccountCardView(
                            db: db,
                            account: child,
                            depth: depth + 1,
                            hideBalance: hideBalance,
                            onSelectAccount: onSelectAccount,
                            onEditAccount: onEditAccount,
                            onAddSubAccount: onAddSubAccount
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}


// Section of Physical Apple Cards for Non-Debit Accounts (Flat, no sub-account nesting)
struct AccountCardSection: View {
    let title: String
    let accounts: [Account]
    let hideBalance: Bool
    let onSelectAccount: (Account) -> Void
    var onEditAccount: ((Account) -> Void)? = nil
    var onPayAccount: ((Account) -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(AppleTheme.labelSecondary)
                .kerning(0.8)
                .padding(.horizontal, 24)
            
            VStack(spacing: 14) {
                ForEach(accounts) { acc in
                    PhysicalAccountCardView(
                        account: acc,
                        hideBalance: hideBalance,
                        onTap: { onSelectAccount(acc) },
                        onEdit: { onEditAccount?(acc) },
                        onPay: (acc.isLiability && onPayAccount != nil) ? { onPayAccount?(acc) } : nil
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }
}


// MARK: - Physical Apple Card View (Authentic Apple Card Aesthetic)
struct PhysicalAccountCardView: View {
    let account: Account
    let hideBalance: Bool
    var isSubAccount: Bool = false
    var subAccountCount: Int = 0
    var cumulativeBalance: Double? = nil
    var isExpanded: Bool = true
    let onTap: () -> Void
    var onEdit: (() -> Void)? = nil
    var onAddSubAccount: (() -> Void)? = nil
    var onToggleExpand: (() -> Void)? = nil
    var onToggleIncludeInNetWorth: (() -> Void)? = nil
    var onPay: (() -> Void)? = nil
    
    /// For parent debit accounts with children, displayed balance is the sum of its included children.
    private var displayedBalance: Double {
        if subAccountCount > 0, let total = cumulativeBalance {
            return total
        }
        return account.balance
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Main card body button
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 0) {
                    // Top row: Account Name + Badges + Sub-account indicator
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(account.name)
                                    .font(.system(size: isSubAccount ? 15 : 17, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                
                                if isSubAccount {
                                    Text("SUB")
                                        .font(.system(size: 8, weight: .heavy))
                                        .foregroundColor(AppleTheme.accentBlue)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(AppleTheme.accentBlue.opacity(0.18))
                                        .clipShape(Capsule())
                                }
                                
                                if !account.includeInNetWorth {
                                    HStack(spacing: 3) {
                                        Image(systemName: "eye.slash.fill")
                                            .font(.system(size: 8))
                                        Text("Excluded")
                                            .font(.system(size: 8, weight: .bold))
                                    }
                                    .foregroundColor(AppleTheme.accentOrange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppleTheme.accentOrange.opacity(0.18))
                                    .clipShape(Capsule())
                                }
                                
                                if subAccountCount > 0 {
                                    if let onToggleExpand = onToggleExpand {
                                        Button(action: onToggleExpand) {
                                            HStack(spacing: 4) {
                                                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                                    .font(.system(size: 8, weight: .heavy))
                                                Text("\(subAccountCount) sub\(subAccountCount == 1 ? "" : "s")")
                                                    .font(.system(size: 9, weight: .bold))
                                            }
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(Color.white.opacity(0.2))
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        Text("\(subAccountCount) sub\(subAccountCount == 1 ? "" : "s")")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.white.opacity(0.8))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.white.opacity(0.15))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            
                            if !account.institution.isEmpty {
                                Text(account.institution)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.65))
                                    .lineLimit(1)
                            }
                            
                            if account.type == .credit && account.hasRewardRatesConfigured {
                                HStack(spacing: 6) {
                                    Text("\(Account.formatRate(account.baseRate)) Base")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white.opacity(0.9))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.15))
                                        .clipShape(Capsule())
                                    
                                    if let topTier = account.activeBonusTiers.max(by: { $0.rate < $1.rate }) {
                                        Text("\(Account.formatRate(topTier.rate)) Bonus (\(topTier.categories.prefix(2).joined(separator: ", "))\(topTier.categories.count > 2 ? " +\(topTier.categories.count - 2)" : ""))")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(AppleTheme.accentGreen)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(AppleTheme.accentGreen.opacity(0.18))
                                            .clipShape(Capsule())
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.top, 2)
                            }
                        }
                        
                        Spacer()
                    }
                    
                    Spacer(minLength: isSubAccount ? 12 : 22)
                    
                    // Bottom row: Masked Account Number & Balance
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.type.rawValue.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Color.white.opacity(0.6))
                                .kerning(0.8)
                            
                            Text(account.maskedNumber)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.7))
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(subAccountCount > 0 ? "TOTAL OF SUB-ACCOUNTS" : (account.isLiability ? "CURRENT BALANCE" : "AVAILABLE"))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Color.white.opacity(0.6))
                                .kerning(0.8)
                            
                            Text(hideBalance ? "••••••" : formatCurrencyWithCommas(displayedBalance))
                                .font(.system(size: isSubAccount ? 17 : 20, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(account.includeInNetWorth ? .white : .white.opacity(0.65))
                        }
                    }
                }
                .padding(isSubAccount ? 14 : 18)
                .frame(maxWidth: .infinity)
                .background(account.cardGradient)
                .opacity(account.includeInNetWorth ? 1.0 : 0.78)
                .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                        .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(ScaleButtonStyle())
            
            // Top-Trailing Card Controls
            HStack(spacing: 8) {
                if subAccountCount > 0, let onToggleExpand = onToggleExpand {
                    Button(action: onToggleExpand) {
                        Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                }
                
                if account.isLiability, let onPay = onPay {
                    // Quick "Pay" pill button directly on the credit card banner
                    Button(action: {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                        onPay()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "creditcard.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("Pay")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppleTheme.accentGreen)
                        .clipShape(Capsule())
                        .shadow(color: AppleTheme.accentGreen.opacity(0.4), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
                
                if onEdit != nil || onAddSubAccount != nil || onToggleIncludeInNetWorth != nil || (account.isLiability && onPay != nil) {
                    Menu {
                        if let onPay = onPay, account.isLiability {
                            Button(action: onPay) {
                                Label("Make a Payment", systemImage: "creditcard.fill")
                            }
                        }
                        if let onEdit = onEdit {
                            Button(action: onEdit) {
                                Label("Rename / Edit Account", systemImage: "pencil")
                            }
                        }
                        if let onAddSubAccount = onAddSubAccount {
                            Button(action: onAddSubAccount) {
                                Label("Add Sub-Account", systemImage: "plus.rectangle.on.folder")
                            }
                        }
                        if subAccountCount > 0, let onToggleExpand = onToggleExpand {
                            Button(action: onToggleExpand) {
                                Label(
                                    isExpanded ? "Collapse Sub-Accounts" : "Expand Sub-Accounts",
                                    systemImage: isExpanded ? "chevron.up" : "chevron.down"
                                )
                            }
                        }
                        if let onToggleInclude = onToggleIncludeInNetWorth {
                            Divider()
                            Button(action: onToggleInclude) {
                                Label(
                                    account.includeInNetWorth ? "Exclude from Parent & Net Worth" : "Include in Parent & Net Worth",
                                    systemImage: account.includeInNetWorth ? "eye.slash" : "eye"
                                )
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
        }
        .contextMenu {
            if let onPay = onPay, account.isLiability {
                Button(action: onPay) {
                    Label("Make a Payment", systemImage: "creditcard.fill")
                }
            }
            if let onEdit = onEdit {
                Button(action: onEdit) {
                    Label("Rename / Edit Account", systemImage: "pencil")
                }
            }
            if let onAddSubAccount = onAddSubAccount {
                Button(action: onAddSubAccount) {
                    Label("Add Sub-Account", systemImage: "plus.rectangle.on.folder")
                }
            }
        }
    }
}


// MARK: - Tab 2.5: Credit Cards & Category Rewards Optimizer Tab
struct CardsTabView: View {
    @ObservedObject var db: DatabaseManager
    @Binding var hideBalances: Bool
    var onAddCard: () -> Void
    var onSelectCard: (Account) -> Void
    var onPayCreditCard: ((Account) -> Void)? = nil
    
    @State private var selectedCategoryName: String = ""
    @State private var editingCard: Account? = nil
    @State private var isCheatSheetExpanded: Bool = true
    
    private var creditCards: [Account] {
        db.creditCards
    }
    
    private var expenseCategories: [Category] {
        db.categories.filter { !CategoryStyle.style(for: $0.name).isIncome }
    }
    
    private var activeCategoryName: String {
        if !selectedCategoryName.isEmpty,
           expenseCategories.contains(where: { $0.name.caseInsensitiveCompare(selectedCategoryName) == .orderedSame }) {
            return selectedCategoryName
        }
        return expenseCategories.first?.name ?? "Grocery"
    }
    
    private var rankedCardsForActiveCategory: [(card: Account, rate: Double, isBonus: Bool)] {
        db.rankedCreditCards(forCategory: activeCategoryName)
    }
    
    private var topRateForActiveCategory: Double {
        rankedCardsForActiveCategory.first?.rate ?? 0.0
    }
    
    private var winningCardsForActiveCategory: [(card: Account, rate: Double, isBonus: Bool)] {
        guard let first = rankedCardsForActiveCategory.first else { return [] }
        return rankedCardsForActiveCategory.filter { abs($0.rate - first.rate) < 0.0001 }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    
                    // Top Bar: Summary Pill & Add Card Action
                    HStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "creditcard.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(AppleTheme.accentBlue)
                            Text("\(creditCards.count) \(creditCards.count == 1 ? "Credit Card" : "Credit Cards")")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppleTheme.bgCard)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(AppleTheme.cardStroke, lineWidth: 0.5))
                        
                        Spacer()
                        
                        Button(action: {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            hideBalances.toggle()
                        }) {
                            Image(systemName: hideBalances ? "eye.slash.fill" : "eye.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppleTheme.labelSecondary)
                                .frame(width: 32, height: 32)
                                .background(AppleTheme.bgCard)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(AppleTheme.cardStroke, lineWidth: 0.5))
                        }
                        
                        Button(action: onAddCard) {
                            HStack(spacing: 5) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Add Card")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(AppleTheme.accentBlue)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    
                    if creditCards.isEmpty {
                        // Empty State
                        VStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(AppleTheme.accentBlue.opacity(0.15))
                                    .frame(width: 72, height: 72)
                                Image(systemName: "creditcard.and.123")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundColor(AppleTheme.accentBlue)
                            }
                            .padding(.top, 20)
                            
                            Text("No Credit Cards Yet")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("Add your credit cards with their base rate, bonus rate, and bonus categories to automatically see which card gives you the best % back for every purchase.")
                                .font(.subheadline)
                                .foregroundColor(AppleTheme.labelSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            
                            Button(action: onAddCard) {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Your First Credit Card")
                                }
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(AppleTheme.accentBlue)
                                .clipShape(Capsule())
                                .shadow(color: AppleTheme.accentBlue.opacity(0.35), radius: 10, x: 0, y: 5)
                            }
                            .padding(.top, 6)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .background(AppleTheme.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                                .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                        )
                        .padding(.horizontal, 20)
                    } else {
                        // MARK: - 1. Best Card Finder by Category
                        bestCardFinderSection
                        
                        // MARK: - 2. All Categories Best-% Cheat Sheet
                        allCategoriesCheatSheetSection
                        
                        // MARK: - 3. My Credit Cards List
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("MY CREDIT CARDS (\(creditCards.count))")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(AppleTheme.labelSecondary)
                                    .kerning(0.8)
                                
                                Spacer()
                                
                                Button(action: onAddCard) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 12))
                                        Text("Add Card")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .foregroundColor(AppleTheme.accentBlue)
                                }
                            }
                            .padding(.horizontal, 24)
                            
                            VStack(spacing: 16) {
                                ForEach(creditCards) { card in
                                    CreditCardRewardCardView(
                                        card: card,
                                        hideBalance: hideBalances,
                                        onTap: { onSelectCard(card) },
                                        onEdit: { editingCard = card },
                                        onPay: onPayCreditCard != nil ? { onPayCreditCard?(card) } : nil
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    
                    Spacer(minLength: 120)
                }
            }
            .navigationTitle("Cards")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingCard) { card in
                EditAccountSheetView(
                    db: db,
                    account: card,
                    isPresented: Binding(
                        get: { editingCard != nil },
                        set: { if !$0 { editingCard = nil } }
                    )
                )
                .presentationDetents([.fraction(0.88), .large])
            }
            .onAppear {
                if selectedCategoryName.isEmpty, let first = expenseCategories.first {
                    selectedCategoryName = first.name
                }
            }
        }
    }
    
    // MARK: - Best Card Finder Spotlight View
    @ViewBuilder
    private var bestCardFinderSection: some View {
        let style = CategoryStyle.style(for: activeCategoryName)
        let winners = winningCardsForActiveCategory
        
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BEST CARD FINDER")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppleTheme.labelSecondary)
                        .kerning(0.8)
                    Text("Select a category to see which card gives the highest %")
                        .font(.system(size: 12))
                        .foregroundColor(AppleTheme.labelTertiary)
                }
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppleTheme.accentYellow)
            }
            
            // Horizontal Category Selector Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(expenseCategories) { cat in
                        let isSelected = cat.name.caseInsensitiveCompare(activeCategoryName) == .orderedSame
                        let catStyle = CategoryStyle.style(for: cat.name)
                        
                        Button(action: {
                            #if os(iOS)
                            UISelectionFeedbackGenerator().selectionChanged()
                            #endif
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                selectedCategoryName = cat.name
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: catStyle.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(isSelected ? .white : catStyle.color)
                                Text(cat.name)
                                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                    .foregroundColor(isSelected ? .white : AppleTheme.labelPrimary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(isSelected ? catStyle.color : AppleTheme.bgTertiary)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? Color.white.opacity(0.25) : Color.clear, lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Winning Card Hero Box
            if let primaryWinner = winners.first {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(AppleTheme.accentYellow)
                                Text(winners.count > 1 ? "TOP TIED CARDS FOR \(activeCategoryName.uppercased())" : "BEST CARD FOR \(activeCategoryName.uppercased())")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundColor(AppleTheme.accentYellow)
                                    .kerning(0.6)
                            }
                            
                            if winners.count == 1 {
                                Text(primaryWinner.card.name)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(.white)
                                
                                HStack(spacing: 6) {
                                    if !primaryWinner.card.institution.isEmpty {
                                        Text(primaryWinner.card.institution)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.white.opacity(0.75))
                                        Text("•")
                                            .foregroundColor(.white.opacity(0.4))
                                    }
                                    Text(primaryWinner.card.maskedNumber)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.75))
                                }
                            } else {
                                Text(winners.map { $0.card.name }.joined(separator: " & "))
                                    .font(.system(size: 19, weight: .bold))
                                    .foregroundColor(.white)
                                Text("\(winners.count) cards tied at \(Account.formatRate(primaryWinner.rate))")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.75))
                            }
                        }
                        
                        Spacer()
                        
                        // Big % Rate Badge
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(Account.formatRate(primaryWinner.rate))
                                .font(.system(size: 32, weight: .heavy, design: .rounded))
                                .foregroundColor(primaryWinner.isBonus ? AppleTheme.accentGreen : .white)
                            
                            Text(primaryWinner.isBonus ? "BONUS RATE" : "BASE RATE")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundColor(primaryWinner.isBonus ? AppleTheme.accentGreen : AppleTheme.labelSecondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(primaryWinner.isBonus ? AppleTheme.accentGreen.opacity(0.18) : Color.white.opacity(0.12))
                                )
                        }
                    }
                    
                    // Ranked comparison of all cards for this category
                    if rankedCardsForActiveCategory.count > 1 {
                        Divider().background(Color.white.opacity(0.1))
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ALL CARDS RANKED FOR \(activeCategoryName.uppercased())")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                                .kerning(0.6)
                            
                            ForEach(Array(rankedCardsForActiveCategory.enumerated()), id: \.element.card.id) { idx, entry in
                                let isTop = abs(entry.rate - topRateForActiveCategory) < 0.0001 && topRateForActiveCategory > 0
                                HStack(spacing: 10) {
                                    Text("#\(idx + 1)")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundColor(isTop ? AppleTheme.accentYellow : AppleTheme.labelSecondary)
                                        .frame(width: 22, alignment: .leading)
                                    
                                    Circle()
                                        .fill(entry.card.institutionColor)
                                        .frame(width: 8, height: 8)
                                    
                                    Text(entry.card.name)
                                        .font(.system(size: 13, weight: isTop ? .bold : .medium))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    Text(entry.isBonus ? "Bonus" : "Base")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(entry.isBonus ? AppleTheme.accentGreen : AppleTheme.labelSecondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(entry.isBonus ? AppleTheme.accentGreen.opacity(0.15) : Color.white.opacity(0.08))
                                        )
                                    
                                    Text(Account.formatRate(entry.rate))
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(entry.isBonus ? AppleTheme.accentGreen : .white)
                                        .frame(minWidth: 42, alignment: .trailing)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                .padding(16)
                .background(
                    LinearGradient(
                        colors: [
                            style.color.opacity(0.28),
                            primaryWinner.card.institutionColor.opacity(0.22),
                            Color(red: 0.1, green: 0.1, blue: 0.13)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(style.color.opacity(0.45), lineWidth: 1)
                )
            }
        }
        .padding(20)
        .background(AppleTheme.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
        )
        .padding(.horizontal, 20)
    }
    
    // MARK: - All Categories Best-% Cheat Sheet Section
    @ViewBuilder
    private var allCategoriesCheatSheetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isCheatSheetExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "list.star")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppleTheme.accentGreen)
                    Text("BEST CARD BY CATEGORY CHEAT SHEET")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppleTheme.labelSecondary)
                        .kerning(0.8)
                    Spacer()
                    Image(systemName: isCheatSheetExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppleTheme.labelSecondary)
                }
                .padding(.horizontal, 24)
            }
            .buttonStyle(.plain)
            
            if isCheatSheetExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(expenseCategories.enumerated()), id: \.element.id) { index, cat in
                        let style = CategoryStyle.style(for: cat.name)
                        let best = db.bestCreditCard(forCategory: cat.name)
                        let isSelected = cat.name.caseInsensitiveCompare(activeCategoryName) == .orderedSame
                        
                        Button(action: {
                            #if os(iOS)
                            UISelectionFeedbackGenerator().selectionChanged()
                            #endif
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                selectedCategoryName = cat.name
                            }
                        }) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(style.color.opacity(0.22))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: style.icon)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(style.color)
                                }
                                
                                Text(cat.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                if let winner = best {
                                    HStack(spacing: 8) {
                                        Text(winner.card.name)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(AppleTheme.labelPrimary)
                                            .lineLimit(1)
                                        
                                        Text(Account.formatRate(winner.rate))
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                            .foregroundColor(winner.isBonus ? AppleTheme.accentGreen : .white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                Capsule()
                                                    .fill(winner.isBonus ? AppleTheme.accentGreen.opacity(0.18) : AppleTheme.bgTertiary)
                                            )
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(isSelected ? style.color.opacity(0.1) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        if index < expenseCategories.count - 1 {
                            Divider()
                                .background(Color.white.opacity(0.06))
                                .padding(.leading, 60)
                        }
                    }
                }
                .background(AppleTheme.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                        .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                )
                .padding(.horizontal, 20)
            }
        }
    }
}


// MARK: - Credit Card with Rewards Breakdown View
struct CreditCardRewardCardView: View {
    let card: Account
    let hideBalance: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    var onPay: (() -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Physical Card Top
            PhysicalAccountCardView(
                account: card,
                hideBalance: hideBalance,
                onTap: onTap,
                onEdit: onEdit,
                onPay: onPay
            )
            
            // Rewards Details Strip underneath the card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "percent")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppleTheme.accentBlue)
                        Text("Base Rate:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppleTheme.labelSecondary)
                        Text(Account.formatRate(card.baseRate))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("on all purchases")
                            .font(.system(size: 11))
                            .foregroundColor(AppleTheme.labelTertiary)
                    }
                    
                    Spacer()
                    
                    Button(action: onEdit) {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 10, weight: .bold))
                            Text(card.hasRewardRatesConfigured ? "Edit Rates" : "Set Rates")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(AppleTheme.accentBlue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AppleTheme.accentBlue.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                
                if !card.activeBonusTiers.isEmpty {
                    Divider().background(Color.white.opacity(0.06))
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(card.activeBonusTiers) { tier in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(Account.formatRate(tier.rate)) BONUS")
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .foregroundColor(AppleTheme.accentGreen)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(AppleTheme.accentGreen.opacity(0.16))
                                    .clipShape(Capsule())
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(tier.categories, id: \.self) { catName in
                                            let style = CategoryStyle.style(for: catName)
                                            HStack(spacing: 4) {
                                                Image(systemName: style.icon)
                                                    .font(.system(size: 9, weight: .semibold))
                                                    .foregroundColor(style.color)
                                                Text(catName)
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundColor(.white)
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(AppleTheme.bgTertiary)
                                            .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Text("No bonus categories configured yet — tap 'Edit Rates' to add bonus % categories.")
                        .font(.system(size: 11))
                        .foregroundColor(AppleTheme.labelTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppleTheme.bgCard)
            .clipShape(
                .rect(
                    topLeadingRadius: 8,
                    bottomLeadingRadius: AppleTheme.cardCornerRadius,
                    bottomTrailingRadius: AppleTheme.cardCornerRadius,
                    topTrailingRadius: 8
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                    .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
            )
            .padding(.top, 4)
        }
    }
}


// MARK: - Tab 3: Transactions & Analytics View (Swift Charts SectorMark & InsetGrouped)
struct TransactionsAnalyticsTabView: View {
    @ObservedObject var db: DatabaseManager
    var onEditBudgets: () -> Void
    var onOpenManualEntry: () -> Void
    
    @State private var filterPeriod: TimePeriodFilter = .monthly
    @State private var dateOffset: Int = 0
    @State private var selectedSubtab: BreakdownSubtab = .analytics
    @State private var searchText: String = ""
    @State private var editingTx: Transaction? = nil
    @State private var selectedCalendarDay: Date? = nil
    @State private var isCalendarExpanded: Bool = true
    @State private var selectedDonutCategory: String? = nil
    @State private var expandedCategories: Set<String> = []
    
    enum BreakdownSubtab: String, CaseIterable, Identifiable {
        case analytics = "Analytics"
        case records = "Records"
        var id: String { rawValue }
    }
    
    struct CalendarDayItem: Identifiable {
        let id: String
        let dayNumber: Int
        let date: Date?
    }
    
    private var daysWithTransactions: (expenses: Set<Int>, incomes: Set<Int>, transfers: Set<Int>) {
        let calendar = Calendar.current
        var expDays = Set<Int>()
        var incDays = Set<Int>()
        var trfDays = Set<Int>()
        for tx in periodTransactions {
            let day = calendar.component(.day, from: tx.date)
            if tx.source == "transfer" || tx.transferPairID != nil {
                trfDays.insert(day)
            } else if tx.isIncome {
                incDays.insert(day)
            } else {
                expDays.insert(day)
            }
        }
        return (expDays, incDays, trfDays)
    }
    
    private func daysInCurrentMonth() -> [CalendarDayItem] {
        let calendar = Calendar.current
        let startOfMonth = dateInterval.start
        guard let monthRange = calendar.range(of: .day, in: .month, for: startOfMonth) else { return [] }
        
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        var items: [CalendarDayItem] = []
        
        for i in 1..<firstWeekday {
            items.append(CalendarDayItem(id: "empty-\(i)", dayNumber: 0, date: nil))
        }
        
        for day in monthRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                items.append(CalendarDayItem(id: "day-\(day)", dayNumber: day, date: date))
            }
        }
        
        return items
    }
    
    private var dateInterval: (start: Date, end: Date, title: String) {
        let calendar = Calendar.current
        let now = Date()
        
        switch filterPeriod {
        case .daily:
            guard let targetDate = calendar.date(byAdding: .day, value: dateOffset, to: now),
                  let start = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: targetDate)),
                  let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) else {
                return (now, now, "Today")
            }
            return (start, end, dateOffset == 0 ? "Today" : "Day \(dateOffset)")
        case .weekly:
            let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            guard let targetWeekStart = calendar.date(byAdding: .weekOfYear, value: dateOffset, to: startOfWeek),
                  let end = calendar.date(byAdding: DateComponents(day: 7, second: -1), to: targetWeekStart) else {
                return (now, now, "This Week")
            }
            return (targetWeekStart, end, dateOffset == 0 ? "This Week" : "Week \(dateOffset)")
        case .monthly:
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            guard let targetMonthStart = calendar.date(byAdding: .month, value: dateOffset, to: startOfMonth),
                  let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: targetMonthStart) else {
                return (now, now, "This Month")
            }
            let f = DateFormatter()
            f.dateFormat = "MMMM yyyy"
            return (targetMonthStart, end, f.string(from: targetMonthStart))
        case .yearly:
            let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
            guard let targetYearStart = calendar.date(byAdding: .year, value: dateOffset, to: startOfYear),
                  let end = calendar.date(byAdding: DateComponents(year: 1, second: -1), to: targetYearStart) else {
                return (now, now, "This Year")
            }
            let f = DateFormatter()
            f.dateFormat = "yyyy"
            return (targetYearStart, end, f.string(from: targetYearStart))
        }
    }
    
    private var periodTransactions: [Transaction] {
        let interval = dateInterval
        return db.transactions.filter { tx in
            tx.date >= interval.start && tx.date <= interval.end
        }
    }
    
    private var activeTransactions: [Transaction] {
        if let day = selectedCalendarDay {
            let calendar = Calendar.current
            return periodTransactions.filter { calendar.isDate($0.date, inSameDayAs: day) }
        }
        return periodTransactions
    }
    
    private var availablePeriodMerchants: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tx in activeTransactions where tx.source != "transfer" {
            let trimmed = tx.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                result.append(trimmed)
            }
        }
        return result
    }
    
    private var filteredRecords: [Transaction] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return activeTransactions
        }
        let lower = searchText.lowercased()
        return activeTransactions.filter {
            $0.merchant.lowercased().contains(lower) ||
            ($0.categoryName?.lowercased().contains(lower) ?? false) ||
            ($0.notes?.lowercased().contains(lower) ?? false)
        }
    }
    
    private var totalExpense: Double {
        let sum = activeTransactions.reduce(0.0) { sum, tx in
            guard tx.source != "transfer", tx.transferPairID == nil, !tx.isIncome else { return sum }
            if let cat = tx.categoryName?.lowercased(), cat == "transfer" || cat == "transfers" { return sum }
            return sum + tx.netExpenseImpact
        }
        return max(0.0, sum)
    }
    
    struct CategorySpendingItem: Identifiable {
        var id: String { name }
        let name: String
        let amount: Double
        let count: Int
        let style: CategoryStyle
        var percentage: Double = 0.0
        var transactions: [Transaction] = []
    }
    
    private var categoryBreakdown: [CategorySpendingItem] {
        var groups: [String: (amount: Double, count: Int, txs: [Transaction])] = [:]
        for tx in activeTransactions {
            guard tx.source != "transfer", tx.transferPairID == nil, !tx.isIncome else { continue }
            let cat = tx.categoryName ?? "Miscellaneous"
            let catLower = cat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if catLower == "transfer" || catLower == "transfers" { continue }
            var current = groups[cat, default: (0.0, 0, [])]
            let impact = tx.netExpenseImpact
            current.amount += impact
            current.count += 1
            current.txs.append(tx)
            groups[cat] = current
        }
        let total = totalExpense > 0 ? totalExpense : 1.0
        return groups.compactMap { key, val in
            let clampedAmount = max(0.0, val.amount)
            guard clampedAmount > 0 else { return nil }
            return CategorySpendingItem(
                name: key,
                amount: clampedAmount,
                count: val.count,
                style: CategoryStyle.style(for: key),
                percentage: clampedAmount / total,
                transactions: val.txs
            )
        }
        .sorted { $0.amount > $1.amount }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    
                    // Period Navigator
                    HStack {
                        Menu {
                            ForEach(TimePeriodFilter.allCases) { filter in
                                Button(filter.rawValue) {
                                    filterPeriod = filter
                                    dateOffset = 0
                                    selectedCalendarDay = nil
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(filterPeriod.rawValue)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(AppleTheme.accentBlue)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(AppleTheme.accentBlue)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(AppleTheme.bgCard)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(AppleTheme.cardStroke, lineWidth: 0.5))
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 14) {
                            Button(action: {
                                dateOffset -= 1
                                selectedCalendarDay = nil
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(AppleTheme.labelSecondary)
                            }
                            
                            Text(dateInterval.title)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                            
                            Button(action: {
                                dateOffset += 1
                                selectedCalendarDay = nil
                            }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(dateOffset >= 0 ? AppleTheme.labelTertiary : AppleTheme.labelSecondary)
                            }
                            .disabled(dateOffset >= 0)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            // Calendar Toggle Pill
                            Button(action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    if filterPeriod != .monthly {
                                        filterPeriod = .monthly
                                        isCalendarExpanded = true
                                    } else {
                                        isCalendarExpanded.toggle()
                                    }
                                }
                            }) {
                                ZStack {
                                    Circle()
                                        .fill((isCalendarExpanded && filterPeriod == .monthly) ? AppleTheme.accentBlue : AppleTheme.bgCard)
                                        .frame(width: 32, height: 32)
                                        .overlay(Circle().stroke(AppleTheme.cardStroke, lineWidth: 0.5))
                                    
                                    Image(systemName: "calendar")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor((isCalendarExpanded && filterPeriod == .monthly) ? .white : AppleTheme.accentBlue)
                                }
                            }
                            
                            Button(action: onOpenManualEntry) {
                                ZStack {
                                    Circle()
                                        .fill(AppleTheme.bgCard)
                                        .frame(width: 32, height: 32)
                                        .overlay(Circle().stroke(AppleTheme.cardStroke, lineWidth: 0.5))
                                    
                                    Image(systemName: "plus")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(AppleTheme.accentBlue)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    
                    // Month Calendar View Card (Apple Calendar Style)
                    if filterPeriod == .monthly && isCalendarExpanded {
                        monthCalendarViewCard
                    }
                    
                    // Subtab Picker (Analytics vs Records)
                    Picker("View Mode", selection: $selectedSubtab) {
                        ForEach(BreakdownSubtab.allCases) { sub in
                            Text(sub.rawValue).tag(sub)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal, 20)
                    
                    if selectedSubtab == .analytics {
                        // MARK: - Swift Charts SectorMark Donut Chart
                        VStack(spacing: 16) {
                            HStack {
                                Text("SPENDING BREAKDOWN")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(AppleTheme.labelSecondary)
                                    .kerning(0.8)
                                Spacer()
                                if selectedDonutCategory != nil {
                                    Button(action: {
                                        #if os(iOS)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        #endif
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                            selectedDonutCategory = nil
                                        }
                                    }) {
                                        HStack(spacing: 4) {
                                            Text("Reset")
                                                .font(.system(size: 11, weight: .semibold))
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 11))
                                        }
                                        .foregroundColor(AppleTheme.accentBlue)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(AppleTheme.accentBlue.opacity(0.15))
                                        .clipShape(Capsule())
                                    }
                                } else {
                                    Text(formatCurrencyWithCommas(totalExpense))
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            
                            if !categoryBreakdown.isEmpty {
                                let selectedDonutItem = categoryBreakdown.first(where: { $0.name == selectedDonutCategory })
                                
                                ZStack {
                                    Chart(categoryBreakdown) { item in
                                        let isSelected = selectedDonutItem?.name == item.name
                                        let hasSelection = selectedDonutItem != nil
                                        SectorMark(
                                            angle: .value("Amount", item.amount),
                                            innerRadius: .ratio(0.65),
                                            outerRadius: .ratio(isSelected ? 1.0 : (hasSelection ? 0.90 : 0.96)),
                                            angularInset: 2.0
                                        )
                                        .cornerRadius(4)
                                        .foregroundStyle(item.style.color)
                                        .opacity(hasSelection && !isSelected ? 0.42 : 1.0)
                                    }
                                    .frame(height: 220)
                                    .chartOverlay { _ in
                                        GeometryReader { geo in
                                            Color.clear
                                                .contentShape(Rectangle())
                                                .onTapGesture { location in
                                                    handleDonutTap(at: location, in: geo.size)
                                                }
                                        }
                                    }
                                    
                                    // Center text (shows selected slice or overall total)
                                    if let sel = selectedDonutItem {
                                        VStack(spacing: 3) {
                                            HStack(spacing: 4) {
                                                Image(systemName: sel.style.icon)
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundColor(sel.style.color)
                                                Text(sel.name)
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundColor(sel.style.color)
                                                    .lineLimit(1)
                                            }
                                            .padding(.horizontal, 8)
                                            
                                            Text(formatCurrencyWithCommas(sel.amount))
                                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                                .foregroundColor(.white)
                                            
                                            Text("\(Int(round(sel.percentage * 100)))% • \(sel.count) tx")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(AppleTheme.labelSecondary)
                                        }
                                        .frame(maxWidth: 126)
                                        .allowsHitTesting(false)
                                    } else {
                                        VStack(spacing: 2) {
                                            Text("Total")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(AppleTheme.labelSecondary)
                                            Text(formatWholeWithCommas(totalExpense))
                                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                                .foregroundColor(.white)
                                            Text("Tap slice to view")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundColor(AppleTheme.labelTertiary)
                                        }
                                        .allowsHitTesting(false)
                                    }
                                }
                                
                                // Collapsible Transaction Drawer for Selected Donut Slice
                                if let sel = selectedDonutItem {
                                    VStack(spacing: 0) {
                                        Divider()
                                            .background(Color.white.opacity(0.08))
                                            .padding(.bottom, 10)
                                        
                                        HStack(spacing: 10) {
                                            ZStack {
                                                Circle()
                                                    .fill(sel.style.color)
                                                    .frame(width: 26, height: 26)
                                                Image(systemName: sel.style.icon)
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(.white)
                                            }
                                            
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text("\(sel.name) Transactions")
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundColor(.white)
                                                Text("\(sel.count) \(sel.count == 1 ? "transaction" : "transactions") • \(Int(round(sel.percentage * 100)))% of spending")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(AppleTheme.labelSecondary)
                                            }
                                            
                                            Spacer()
                                            
                                            Button(action: {
                                                #if os(iOS)
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                #endif
                                                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                                    selectedDonutCategory = nil
                                                }
                                            }) {
                                                Image(systemName: "chevron.up.circle.fill")
                                                    .font(.system(size: 18))
                                                    .foregroundColor(AppleTheme.labelSecondary)
                                            }
                                        }
                                        .padding(.bottom, 10)
                                        
                                        VStack(spacing: 0) {
                                            ForEach(Array(sel.transactions.enumerated()), id: \.element.id) { txIdx, tx in
                                                TransactionRowView(
                                                    transaction: tx,
                                                    db: db,
                                                    onEdit: { editingTx = tx }
                                                )
                                                
                                                if txIdx < sel.transactions.count - 1 {
                                                    Divider()
                                                        .background(Color.white.opacity(0.06))
                                                        .padding(.leading, 56)
                                                }
                                            }
                                        }
                                        .background(Color.black.opacity(0.24))
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(sel.style.color.opacity(0.35), lineWidth: 0.8)
                                        )
                                    }
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            } else {
                                Text("No spending records for this period.")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppleTheme.labelSecondary)
                                    .frame(height: 180)
                            }
                        }
                        .padding(20)
                        .background(AppleTheme.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                                .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                        )
                        .padding(.horizontal, 20)
                        
                        // Category Breakdown List (Collapsible Accordion)
                        if !categoryBreakdown.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("CATEGORIES")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(AppleTheme.labelSecondary)
                                        .kerning(0.8)
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        #if os(iOS)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        #endif
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                            if expandedCategories.count == categoryBreakdown.count {
                                                expandedCategories.removeAll()
                                            } else {
                                                expandedCategories = Set(categoryBreakdown.map { $0.name })
                                            }
                                        }
                                    }) {
                                        Text(expandedCategories.count == categoryBreakdown.count ? "Collapse All" : "Expand All")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(AppleTheme.accentBlue)
                                    }
                                }
                                .padding(.horizontal, 24)
                                
                                VStack(spacing: 0) {
                                    ForEach(Array(categoryBreakdown.enumerated()), id: \.element.id) { index, item in
                                        let isExpanded = expandedCategories.contains(item.name)
                                        
                                        VStack(spacing: 0) {
                                            Button(action: {
                                                #if os(iOS)
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                #endif
                                                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                                    if isExpanded {
                                                        expandedCategories.remove(item.name)
                                                        if selectedDonutCategory == item.name {
                                                            selectedDonutCategory = nil
                                                        }
                                                    } else {
                                                        expandedCategories.insert(item.name)
                                                        selectedDonutCategory = item.name
                                                    }
                                                }
                                            }) {
                                                HStack(spacing: 12) {
                                                    ZStack {
                                                        Circle()
                                                            .fill(item.style.color)
                                                            .frame(width: 32, height: 32)
                                                        Image(systemName: item.style.icon)
                                                            .font(.system(size: 14, weight: .semibold))
                                                            .foregroundColor(.white)
                                                    }
                                                    
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(item.name)
                                                            .font(.system(size: 15, weight: .semibold))
                                                            .foregroundColor(.white)
                                                        Text("\(item.count) \(item.count == 1 ? "transaction" : "transactions") • \(Int(round(item.percentage * 100)))%")
                                                            .font(.system(size: 11))
                                                            .foregroundColor(AppleTheme.labelSecondary)
                                                    }
                                                    
                                                    Spacer()
                                                    
                                                    Text(formatCurrencyWithCommas(item.amount))
                                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                                        .foregroundColor(.white)
                                                    
                                                    Image(systemName: "chevron.right")
                                                        .font(.system(size: 12, weight: .bold))
                                                        .foregroundColor(isExpanded ? item.style.color : AppleTheme.labelTertiary)
                                                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                                }
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 12)
                                                .background(isExpanded ? item.style.color.opacity(0.08) : Color.clear)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            
                                            if isExpanded {
                                                VStack(spacing: 0) {
                                                    Divider()
                                                        .background(item.style.color.opacity(0.25))
                                                    
                                                    ForEach(Array(item.transactions.enumerated()), id: \.element.id) { txIdx, tx in
                                                        TransactionRowView(
                                                            transaction: tx,
                                                            db: db,
                                                            onEdit: { editingTx = tx }
                                                        )
                                                        
                                                        if txIdx < item.transactions.count - 1 {
                                                            Divider()
                                                                .background(Color.white.opacity(0.06))
                                                                .padding(.leading, 56)
                                                        }
                                                    }
                                                }
                                                .background(Color.black.opacity(0.24))
                                                .overlay(alignment: .leading) {
                                                    Rectangle()
                                                        .fill(item.style.color)
                                                        .frame(width: 3)
                                                }
                                                .transition(.opacity.combined(with: .move(edge: .top)))
                                            }
                                            
                                            if index < categoryBreakdown.count - 1 {
                                                Divider()
                                                    .background(Color.white.opacity(0.06))
                                                    .padding(.leading, isExpanded ? 0 : 60)
                                            }
                                        }
                                    }
                                }
                                .background(AppleTheme.bgCard)
                                .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                                        .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                                )
                                .padding(.horizontal, 20)
                            }
                        }
                    } else {
                        // MARK: - Records Subtab (Searchable Inset Grouped List)
                        VStack(spacing: 14) {
                            // Search Bar
                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(AppleTheme.labelSecondary)
                                
                                TextField("Search tag, category, or notes", text: $searchText)
                                    .foregroundColor(.white)
                                
                                if !searchText.isEmpty {
                                    Button(action: { searchText = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(AppleTheme.labelSecondary)
                                    }
                                }
                            }
                            .padding(12)
                            .background(AppleTheme.bgCard)
                            .clipShape(RoundedRectangle(cornerRadius: AppleTheme.compactCornerRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppleTheme.compactCornerRadius, style: .continuous)
                                    .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                            )
                            .padding(.horizontal, 20)
                            
                            // Interactive Merchant Sliding Filter Pills
                            if !availablePeriodMerchants.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(availablePeriodMerchants, id: \.self) { merch in
                                            let isSelected = searchText.caseInsensitiveCompare(merch) == .orderedSame
                                            Button(action: {
                                                #if os(iOS)
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                #endif
                                                searchText = isSelected ? "" : merch
                                            }) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "storefront.fill")
                                                        .font(.system(size: 8))
                                                    Text(merch)
                                                        .font(.system(size: 11, weight: .semibold))
                                                }
                                                .foregroundColor(isSelected ? .white : AppleTheme.accentBlue)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(isSelected ? AppleTheme.accentBlue : AppleTheme.accentBlue.opacity(0.14))
                                                .clipShape(Capsule())
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                            
                            // Grouped Records
                            if filteredRecords.isEmpty {
                                Text("No transactions found.")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppleTheme.labelSecondary)
                                    .padding(.top, 40)
                            } else {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(filteredRecords.enumerated()), id: \.element.id) { index, tx in
                                        TransactionRowView(
                                            transaction: tx,
                                            db: db,
                                            onEdit: { editingTx = tx }
                                        )
                                        
                                        if index < filteredRecords.count - 1 {
                                            Divider()
                                                .background(Color.white.opacity(0.06))
                                                .padding(.leading, 56)
                                        }
                                    }
                                }
                                .background(AppleTheme.bgCard)
                                .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                                        .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                                    )
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                    
                    Spacer(minLength: 120)
                }
            }
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingTx) { tx in
                ManualEntryView(isPresented: Binding(
                    get: { editingTx != nil },
                    set: { if !$0 { editingTx = nil } }
                ), editingTransaction: tx)
            }
        }
    }
    
    private func handleDonutTap(at location: CGPoint, in size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = hypot(dx, dy)
        let maxRadius = min(size.width, size.height) / 2
        
        // Tapping inside the donut center hole resets selection
        if distance < maxRadius * 0.58 {
            if let current = selectedDonutCategory {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    expandedCategories.remove(current)
                    selectedDonutCategory = nil
                }
            }
            return
        }
        
        guard distance <= maxRadius * 1.08 else { return }
        
        // Angle from 12 o'clock (0 rad) moving clockwise to 2π
        var angle = atan2(dx, -dy)
        if angle < 0 { angle += 2 * .pi }
        let fraction = angle / (2 * .pi)
        let totalAmt = categoryBreakdown.reduce(0.0) { $0 + $1.amount }
        guard totalAmt > 0 else { return }
        let targetValue = fraction * totalAmt
        
        var cumulative = 0.0
        var tappedItem: CategorySpendingItem? = nil
        for item in categoryBreakdown {
            cumulative += item.amount
            if targetValue <= cumulative {
                tappedItem = item
                break
            }
        }
        if tappedItem == nil {
            tappedItem = categoryBreakdown.last
        }
        
        if let item = tappedItem {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                if selectedDonutCategory == item.name {
                    selectedDonutCategory = nil
                    expandedCategories.remove(item.name)
                } else {
                    selectedDonutCategory = item.name
                    expandedCategories.insert(item.name)
                }
            }
        }
    }
    
    // MARK: - Month Calendar View Card
    @ViewBuilder
    private var monthCalendarViewCard: some View {
        VStack(spacing: 12) {
            // Weekday Headers: SUN MON TUE WED THU FRI SAT
            HStack {
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                    Text(day)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppleTheme.labelTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 6)
            
            // Days Grid
            let days = daysInCurrentMonth()
            let txSummary = daysWithTransactions
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(days) { item in
                    if let date = item.date {
                        let isSelected = selectedCalendarDay != nil && Calendar.current.isDate(selectedCalendarDay!, inSameDayAs: date)
                        let isToday = Calendar.current.isDateInToday(date)
                        let hasExpense = txSummary.expenses.contains(item.dayNumber)
                        let hasIncome = txSummary.incomes.contains(item.dayNumber)
                        let hasTransfer = txSummary.transfers.contains(item.dayNumber)
                        
                        Button(action: {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if isSelected {
                                    selectedCalendarDay = nil
                                } else {
                                    selectedCalendarDay = date
                                }
                            }
                        }) {
                            VStack(spacing: 2) {
                                Text("\(item.dayNumber)")
                                    .font(.system(size: 13, weight: isSelected || isToday ? .bold : .medium))
                                    .foregroundColor(isSelected ? .black : (isToday ? AppleTheme.accentBlue : .white))
                                
                                HStack(spacing: 2) {
                                    if hasExpense {
                                        Circle()
                                            .fill(isSelected ? Color.black : AppleTheme.accentOrange)
                                            .frame(width: 4, height: 4)
                                    }
                                    if hasIncome {
                                        Circle()
                                            .fill(isSelected ? Color.black : AppleTheme.accentGreen)
                                            .frame(width: 4, height: 4)
                                    }
                                    if hasTransfer {
                                        Circle()
                                            .fill(isSelected ? Color.black : AppleTheme.accentBlue)
                                            .frame(width: 4, height: 4)
                                    }
                                    if !hasExpense && !hasIncome && !hasTransfer {
                                        Circle()
                                            .fill(Color.clear)
                                            .frame(width: 4, height: 4)
                                    }
                                }
                            }
                            .frame(height: 38)
                            .frame(maxWidth: .infinity)
                            .background(
                                isSelected ? Color.white : (isToday ? AppleTheme.accentBlue.opacity(0.18) : Color.clear)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isToday && !isSelected ? AppleTheme.accentBlue.opacity(0.6) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear
                            .frame(height: 38)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 4)
            
            // Bottom Day Filter Strip (if day is clicked)
            if let sel = selectedCalendarDay {
                let dayTxs = db.transactions.filter { Calendar.current.isDate($0.date, inSameDayAs: sel) }
                let dayExpense = dayTxs.filter { !$0.isIncome && $0.source != "transfer" && $0.transferPairID == nil }.reduce(0) { $0 + abs($1.amount) }
                let dayTransfers = dayTxs.filter { ($0.source == "transfer" || $0.transferPairID != nil) && $0.amount > 0 }.reduce(0) { $0 + $1.amount }
                let f = DateFormatter()
                let formattedSelectedDay: String = {
                    f.dateFormat = "EEEE, MMM d"
                    return f.string(from: sel)
                }()
                
                Divider().background(Color.white.opacity(0.06))
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formattedSelectedDay)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                        let spentSummary = formatCurrencyWithCommas(dayExpense) + " spent"
                        let transferSummary = dayTransfers > 0 ? " • " + formatCurrencyWithCommas(dayTransfers) + " transferred" : ""
                        Text("\(dayTxs.count) transactions • \(spentSummary)\(transferSummary)")
                            .font(.system(size: 11))
                            .foregroundColor(AppleTheme.labelSecondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation { selectedCalendarDay = nil }
                    }) {
                        HStack(spacing: 4) {
                            Text("Full Month")
                                .font(.system(size: 11, weight: .bold))
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(AppleTheme.accentBlue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppleTheme.accentBlue.opacity(0.15))
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(AppleTheme.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - Transaction Row View with Swipe Actions & Sensory Feedback
struct TransactionRowView: View {
    let transaction: Transaction
    @ObservedObject var db: DatabaseManager
    var onEdit: (() -> Void)? = nil
    
    var body: some View {
        let style = CategoryStyle.style(for: transaction.categoryName ?? "")
        let acc = db.accountsByID[transaction.accountID ?? ""]
        
        let isBalAdjustment = transaction.merchant == "Balance Adjustment" || transaction.subCategory == "Balance Adjustment"
        let isCardPayment = transaction.subCategory == "Credit Card Payment" || transaction.merchant.contains("Payment Received") || transaction.merchant.contains("Credit Card Payment")
        let isRefundTx = transaction.source == "refund"
        
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isRefundTx ? AppleTheme.accentGreen :
                            (isCardPayment ? AppleTheme.accentGreen :
                                (isBalAdjustment ? AppleTheme.accentIndigo :
                                    (transaction.source == "transfer" ? AppleTheme.accentBlue : style.color))))
                    .frame(width: 36, height: 36)
                Image(systemName: isRefundTx ? "arrow.uturn.backward" :
                        (isCardPayment ? "creditcard.fill" :
                            (isBalAdjustment ? "slider.horizontal.3" :
                                (transaction.source == "transfer" ? "arrow.left.arrow.right" : style.icon))))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(transaction.merchant)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    if isBalAdjustment {
                        Text("Adjustment")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(AppleTheme.accentIndigo)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppleTheme.accentIndigo.opacity(0.18))
                            .clipShape(Capsule())
                    } else if isCardPayment {
                        Text("Card Payment")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(AppleTheme.accentGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppleTheme.accentGreen.opacity(0.18))
                            .clipShape(Capsule())
                    }
                    
                    if transaction.isRecurring {
                        HStack(spacing: 3) {
                            Image(systemName: "repeat")
                                .font(.system(size: 8, weight: .bold))
                            if let freq = transaction.recurringFrequency, !freq.isEmpty {
                                Text(freq)
                                    .font(.system(size: 9, weight: .semibold))
                            }
                        }
                        .foregroundColor(AppleTheme.accentBlue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppleTheme.accentBlue.opacity(0.18))
                        .clipShape(Capsule())
                    }
                }
                
                HStack(spacing: 6) {
                    Text(transaction.relativeDateString)
                        .font(.system(size: 12))
                        .foregroundColor(AppleTheme.labelSecondary)
                    
                    if let accName = acc?.name {
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(AppleTheme.labelTertiary)
                        Text(accName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppleTheme.labelSecondary)
                            .lineLimit(1)
                    }
                }
                
                if let notes = transaction.notes, !notes.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text")
                            .font(.system(size: 9))
                            .foregroundColor(AppleTheme.accentOrange)
                        Text(notes)
                            .font(.system(size: 11))
                            .foregroundColor(AppleTheme.labelSecondary)
                            .lineLimit(2)
                    }
                    .padding(.top, 1)
                }
            }
            
            Spacer()
            
            Text(formatCurrencyWithCommas(transaction.amount, showSign: transaction.isIncome))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(transaction.isIncome ? AppleTheme.accentGreen : .white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit?()
        }
        .contextMenu {
            if let onEdit = onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
            Button(role: .destructive) {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                db.deleteTransaction(uuid: transaction.uuid)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                db.deleteTransaction(uuid: transaction.uuid)
            } label: {
                Label("Delete", systemImage: "trash.fill")
            }
        }
        .swipeActions(edge: .leading) {
            if let onEdit = onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(AppleTheme.accentBlue)
            }
        }
    }
}


// MARK: - Lazy Transactions CSV Export Transferable
struct TransactionsCSVExport: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { _ in
            let csv = DatabaseManager.shared.generateCSVExport()
            return Data(csv.utf8)
        }
        .suggestedFileName("BudgetTracker_Transactions.csv")
    }
}

// MARK: - Tab 4: Settings View (Apple Settings .insetGrouped Style)
struct SettingsTabView: View {
    @ObservedObject var db: DatabaseManager
    @Binding var hideBalances: Bool
    var onManageBudgets: () -> Void
    
    @AppStorage("selectedCurrencySymbol") private var selectedCurrencySymbol: String = "$"
    @State private var showingResetAlert = false
    @State private var showingStatementImport = false
    @State private var showingRecurringManager = false
    @State private var showingWidgetCustomizer = false
    @State private var showingShortcutsGuide = false
    
    let currencies: [(symbol: String, label: String)] = [
        ("$", "USD / CAD ($)"),
        ("€", "EUR (€)"),
        ("£", "GBP (£)"),
        ("¥", "JPY (¥)"),
        ("₹", "INR (₹)")
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    
                    // Budgets & Recurring Group
                    VStack(alignment: .leading, spacing: 8) {
                        Text("BUDGET & RECURRING")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(AppleTheme.labelSecondary)
                            .kerning(0.8)
                            .padding(.horizontal, 24)
                        
                        VStack(spacing: 0) {
                            Button(action: onManageBudgets) {
                                HStack {
                                    Label("Manage Monthly Budgets", systemImage: "slider.horizontal.3")
                                        .foregroundColor(.white)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(AppleTheme.labelTertiary)
                                }
                                .padding()
                            }
                            
                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
                            
                            Button(action: { showingRecurringManager = true }) {
                                HStack {
                                    Label("Manage Recurring Transactions", systemImage: "repeat.circle.fill")
                                        .foregroundColor(.white)
                                    Spacer()
                                    let activeCount = db.recurringPayments.filter { $0.isActive }.count
                                    if activeCount > 0 {
                                        Text("\(activeCount) active")
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundColor(AppleTheme.accentBlue)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(AppleTheme.accentBlue.opacity(0.16))
                                            .clipShape(Capsule())
                                    }
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(AppleTheme.labelTertiary)
                                }
                                .padding()
                            }
                            
                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
                            
                            Button(action: { showingWidgetCustomizer = true }) {
                                HStack {
                                    Label("Customize Home Screen Widget", systemImage: "square.grid.4x3.fill")
                                        .foregroundColor(.white)
                                    Spacer()
                                    let widgetIconCount = WidgetDataStore.loadSelectedCategoryNames().count
                                    Text("\(widgetIconCount) icons")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(AppleTheme.accentGreen)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(AppleTheme.accentGreen.opacity(0.16))
                                        .clipShape(Capsule())
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(AppleTheme.labelTertiary)
                                }
                                .padding()
                            }
                            
                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
                            
                            Button(action: { showingShortcutsGuide = true }) {
                                HStack {
                                    Label("Apple Shortcuts", systemImage: "bolt.horizontal.circle.fill")
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text("Log Transaction")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(AppleTheme.accentOrange)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(AppleTheme.accentOrange.opacity(0.16))
                                        .clipShape(Capsule())
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(AppleTheme.labelTertiary)
                                }
                                .padding()
                            }
                        }
                        .background(AppleTheme.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                                .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                        )
                        .padding(.horizontal, 20)
                    }
                    .padding(.top, 10)
                    
                    // Preferences Group
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PREFERENCES")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(AppleTheme.labelSecondary)
                            .kerning(0.8)
                            .padding(.horizontal, 24)
                        
                        VStack(spacing: 0) {
                            HStack {
                                Label("Hide Balances by Default", systemImage: "eye.slash.fill")
                                    .foregroundColor(.white)
                                Spacer()
                                Toggle("", isOn: $hideBalances)
                                    .labelsHidden()
                                    .tint(AppleTheme.accentGreen)
                            }
                            .padding()
                            
                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
                            
                            HStack {
                                Label("Preferred Currency", systemImage: "dollarsign.circle.fill")
                                    .foregroundColor(.white)
                                Spacer()
                                Picker("Currency", selection: $selectedCurrencySymbol) {
                                    ForEach(currencies, id: \.symbol) { c in
                                        Text(c.label).tag(c.symbol)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .tint(AppleTheme.labelSecondary)
                            }
                            .padding()
                        }
                        .background(AppleTheme.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                                .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                        )
                        .padding(.horizontal, 20)
                    }
                    
                    // Database Stats & Export
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DATA & SYSTEM")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(AppleTheme.labelSecondary)
                            .kerning(0.8)
                            .padding(.horizontal, 24)
                        
                        VStack(spacing: 0) {
                            HStack {
                                Label("Total Transactions", systemImage: "tray.full.fill")
                                    .foregroundColor(.white)
                                Spacer()
                                Text("\(db.transactions.count)")
                                    .font(.system(.body, design: .rounded, weight: .bold))
                                    .foregroundColor(AppleTheme.accentBlue)
                            }
                            .padding()
                            
                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
                            
                            HStack {
                                Label("Linked Accounts", systemImage: "creditcard.fill")
                                    .foregroundColor(.white)
                                Spacer()
                                Text("\(db.accounts.count)")
                                    .font(.system(.body, design: .rounded, weight: .bold))
                                    .foregroundColor(AppleTheme.accentGreen)
                            }
                            .padding()
                            
                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
                            
                            Button(action: { showingStatementImport = true }) {
                                HStack {
                                    Label("Import Statement (.json / .csv)", systemImage: "square.and.arrow.down")
                                        .foregroundColor(.white)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(AppleTheme.labelTertiary)
                                }
                                .padding()
                            }
                            
                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
                            
                            ShareLink(
                                item: TransactionsCSVExport(),
                                subject: Text("BudgetTracker Export"),
                                message: Text("Exported \(db.transactions.count) transactions from BudgetTracker"),
                                preview: SharePreview("BudgetTracker_Transactions.csv")
                            ) {
                                HStack {
                                    Label("Export Transactions to CSV", systemImage: "square.and.arrow.up")
                                        .foregroundColor(.white)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(AppleTheme.labelTertiary)
                                }
                                .padding()
                            }
                            
                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
                            
                            Button(role: .destructive, action: {
                                showingResetAlert = true
                            }) {
                                HStack {
                                    Label("Clear All Transactions & Accounts", systemImage: "trash")
                                        .foregroundColor(AppleTheme.accentRed)
                                    Spacer()
                                }
                                .padding()
                            }
                        }
                        .background(AppleTheme.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                                .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                        )
                        .padding(.horizontal, 20)
                    }
                    
                    Spacer(minLength: 120)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingStatementImport) {
                StatementImportSheet(db: db, isPresented: $showingStatementImport)
            }
            .sheet(isPresented: $showingRecurringManager) {
                RecurringTransactionsManagerView(db: db, isPresented: $showingRecurringManager)
            }
            .sheet(isPresented: $showingWidgetCustomizer) {
                WidgetCustomizerSheetView(db: db, isPresented: $showingWidgetCustomizer)
            }
            .sheet(isPresented: $showingShortcutsGuide) {
                ShortcutsGuideSheetView(isPresented: $showingShortcutsGuide)
            }
            .alert("Reset Database?", isPresented: $showingResetAlert) {
                Button("Clear Everything", role: .destructive) {
                    db.clearAllData()
                    #if os(iOS)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    #endif
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will remove all accounts, transactions, and budgets, leaving a clean slate.")
            }
        }
    }
}

// MARK: - Apple Shortcuts Guide Sheet (Pick Transaction Fields Inside Shortcuts App)
struct ShortcutsGuideSheetView: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppleTheme.bgCanvas.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        headerBanner
                        availableFieldsSection
                        HStack {
                            Spacer()
                            ShortcutsLink()
                                .shortcutsLinkStyle(.dark)
                            Spacer()
                        }
                        .padding(.top, 4)
                        Spacer(minLength: 40)
                    }
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Apple Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                        .fontWeight(.bold)
                        .foregroundColor(AppleTheme.accentBlue)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    @ViewBuilder
    private var headerBanner: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppleTheme.accentBlue.opacity(0.2))
                    .frame(width: 48, height: 48)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(AppleTheme.accentBlue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\"Log Transaction\" Shortcut Action")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Text("In the Apple Shortcuts app, add the \"Log Transaction\" action from BudgetTracker to pick or map every field of a transaction directly in your shortcut.")
                    .font(.system(size: 12))
                    .foregroundColor(AppleTheme.labelSecondary)
            }
        }
        .padding(16)
        .background(AppleTheme.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
        )
        .padding(.horizontal, 20)
    }
    
    @ViewBuilder
    private var availableFieldsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SELECTABLE FIELDS IN THE SHORTCUT BLOCK")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(AppleTheme.labelSecondary)
                .kerning(0.8)
                .padding(.horizontal, 24)
            
            VStack(spacing: 0) {
                shortcutActionRow(
                    icon: "arrow.left.arrow.right.circle.fill",
                    color: AppleTheme.accentBlue,
                    title: "Type",
                    subtitle: "Pick Expense, Income, or Refund."
                )
                Divider().background(Color.white.opacity(0.06)).padding(.leading, 56)
                shortcutActionRow(
                    icon: "dollarsign.circle.fill",
                    color: AppleTheme.accentGreen,
                    title: "Amount",
                    subtitle: "Enter a fixed amount, pass a Shortcut variable, or set to Ask Each Time."
                )
                Divider().background(Color.white.opacity(0.06)).padding(.leading, 56)
                shortcutActionRow(
                    icon: "square.grid.2x2.fill",
                    color: AppleTheme.accentOrange,
                    title: "Category",
                    subtitle: "Prompted dynamically from all your BudgetTracker categories when you run the shortcut (no need to pre-specify)."
                )
                Divider().background(Color.white.opacity(0.06)).padding(.leading, 56)
                shortcutActionRow(
                    icon: "tag.fill",
                    color: AppleTheme.accentPurple,
                    title: "Tag",
                    subtitle: "Pick a tag or pass a Shortcut variable."
                )
                Divider().background(Color.white.opacity(0.06)).padding(.leading, 56)
                shortcutActionRow(
                    icon: "creditcard.fill",
                    color: AppleTheme.accentMint,
                    title: "Account",
                    subtitle: "Dynamic dropdown of all your linked bank accounts and credit cards."
                )
                Divider().background(Color.white.opacity(0.06)).padding(.leading, 56)
                shortcutActionRow(
                    icon: "calendar",
                    color: AppleTheme.accentRed,
                    title: "Date, Recurring & Notes",
                    subtitle: "Pick the transaction Date, Recurring frequency (One-Time, Daily, Weekly, Bi-Weekly, Monthly, Yearly), and Notes."
                )
            }
            .background(AppleTheme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                    .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
            )
            .padding(.horizontal, 20)
        }
    }
    
    @ViewBuilder
    private func shortcutActionRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(AppleTheme.labelSecondary)
            }
            Spacer()
        }
        .padding(14)
    }
}

// MARK: - Customize Home Screen Widget View (Wider Expense Quick-Log Widget)
struct WidgetCustomizerSheetView: View {
    @ObservedObject var db: DatabaseManager
    @Binding var isPresented: Bool
    
    @AppStorage("selectedCurrencySymbol") private var currencySymbol: String = "$"
    @State private var selectedNames: [String] = WidgetDataStore.loadSelectedCategoryNames()
    @State private var selectedTimeframe: WidgetTimeframe = WidgetDataStore.loadSelectedTimeframe()
    @State private var quickLogCategoryForTest: Category? = nil
    
    private var allExpenseCategories: [Category] {
        db.categories.filter { !CategoryStyle.style(for: $0.name).isIncome && !$0.name.lowercased().contains("transfer") }
    }
    
    private var selectedShortcuts: [WidgetExpenseShortcut] {
        selectedNames.map { WidgetExpenseShortcut(name: $0) }
    }
    
    private func categorySpend(for categoryName: String) -> Double {
        let range = selectedTimeframe.dateRange()
        let raw = db.transactions.reduce(0.0) { acc, tx in
            guard tx.date >= range.start && tx.date <= range.end else { return acc }
            guard tx.source != "transfer", !tx.isIncome else { return acc }
            guard (tx.categoryName ?? "").caseInsensitiveCompare(categoryName) == .orderedSame else { return acc }
            return acc + tx.netExpenseImpact
        }
        return max(0.0, raw)
    }
    
    private var totalTimeframeSpend: Double {
        let range = selectedTimeframe.dateRange()
        let raw = db.transactions.reduce(0.0) { acc, tx in
            guard tx.date >= range.start && tx.date <= range.end else { return acc }
            guard tx.source != "transfer", !tx.isIncome else { return acc }
            return acc + tx.netExpenseImpact
        }
        return max(0.0, raw)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppleTheme.bgCanvas.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        liveWidgetPreviewSection
                        timeframePickerSection
                        selectedIconsOrderSection
                        availableCategoriesSection
                        howToAddWidgetBanner
                        Spacer(minLength: 40)
                    }
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Home Screen Widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedNames = WidgetExpenseShortcut.defaultSelectedCategoryNames
                            selectedTimeframe = .monthly
                            persistSelection()
                        }
                    }
                    .foregroundColor(AppleTheme.labelSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        persistSelection()
                        isPresented = false
                    }
                    .fontWeight(.bold)
                    .foregroundColor(AppleTheme.accentBlue)
                }
            }
            .sheet(item: $quickLogCategoryForTest) { cat in
                CategoryKeypadEntryView(
                    db: db,
                    category: cat,
                    onSetBudget: { quickLogCategoryForTest = nil }
                )
                .presentationDetents([.fraction(0.88), .large])
                .presentationDragIndicator(.visible)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    @ViewBuilder
    private var liveWidgetPreviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LIVE WIDER WIDGET PREVIEW (TAP ANY ICON TO TEST)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(AppleTheme.labelSecondary)
                    .kerning(0.8)
                Spacer()
                Text(selectedShortcuts.count <= 4 ? "1×4 Row (Shows Values)" : "2×4 Grid (\(selectedShortcuts.count) Icons)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(AppleTheme.accentBlue)
            }
            .padding(.horizontal, 24)
            
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    HStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(AppleTheme.accentBlue.opacity(0.22))
                                .frame(width: 22, height: 22)
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppleTheme.accentBlue)
                        }
                        Text("QUICK LOG")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                            .kerning(0.5)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(AppleTheme.accentBlue)
                        Text(selectedTimeframe.formattedFrameLabel())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                        Text("•")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.35))
                        Text(WidgetSnapshotPayload.formatCompactAmount(totalTimeframeSpend, currencySymbol: currencySymbol))
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundColor(AppleTheme.accentGreen)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                
                let topRow = Array(selectedShortcuts.prefix(4))
                let bottomRow = Array(selectedShortcuts.dropFirst(4).prefix(4))
                
                if selectedShortcuts.count <= 4 {
                    HStack(spacing: 8) {
                        ForEach(topRow) { item in
                            previewShortcutButton(for: item, isTall: true)
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(topRow) { item in
                                previewShortcutButton(for: item, isTall: false)
                            }
                        }
                        HStack(spacing: 8) {
                            ForEach(bottomRow) { item in
                                previewShortcutButton(for: item, isTall: false)
                            }
                            if bottomRow.count < 4 {
                                ForEach(0..<(4 - bottomRow.count), id: \.self) { _ in
                                    Spacer().frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(Color(red: 0.05, green: 0.05, blue: 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.5), radius: 14, x: 0, y: 6)
            .padding(.horizontal, 20)
        }
    }
    
    @ViewBuilder
    private var timeframePickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("1×4 WIDGET SPEND TIMEFRAME")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(AppleTheme.labelSecondary)
                    .kerning(0.8)
                Spacer()
                if selectedShortcuts.count > 4 {
                    Button("Switch to 1×4 (4 Icons)") {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selectedNames = Array(selectedNames.prefix(4))
                            persistSelection()
                        }
                    }
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(AppleTheme.accentBlue)
                }
            }
            .padding(.horizontal, 24)
            
            Picker("Timeframe", selection: $selectedTimeframe) {
                ForEach(WidgetTimeframe.allCases) { tf in
                    Text(tf.rawValue).tag(tf)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal, 20)
            .onChange(of: selectedTimeframe) { _, _ in
                persistSelection()
            }
        }
    }
    
    @ViewBuilder
    private func previewShortcutButton(for item: WidgetExpenseShortcut, isTall: Bool) -> some View {
        let accent = item.swiftUIColor
        let catSpend = categorySpend(for: item.name)
        let formattedSpend = WidgetSnapshotPayload.formatCompactAmount(catSpend, currencySymbol: currencySymbol)
        
        Button(action: {
            if let cat = db.categories.first(where: { $0.name.caseInsensitiveCompare(item.name) == .orderedSame }) {
                quickLogCategoryForTest = cat
            }
        }) {
            VStack(spacing: isTall ? 6 : 5) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.22))
                        .frame(width: isTall ? 36 : 30, height: isTall ? 36 : 30)
                    Image(systemName: item.iconName)
                        .font(.system(size: isTall ? 15 : 13, weight: .bold))
                        .foregroundColor(accent)
                }
                Text(item.shortLabel)
                    .font(.system(size: isTall ? 11 : 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                
                if isTall {
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
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, isTall ? 9 : 7)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accent.opacity(0.35), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var selectedIconsOrderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CHOSEN WIDGET ICONS (REORDER OR REMOVE)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(AppleTheme.labelSecondary)
                .kerning(0.8)
                .padding(.horizontal, 24)
            
            VStack(spacing: 0) {
                ForEach(Array(selectedNames.enumerated()), id: \.element) { idx, name in
                    let style = CategoryStyle.style(for: name)
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Text("#\(idx + 1)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(AppleTheme.labelTertiary)
                                .frame(width: 24, alignment: .leading)
                            
                            ZStack {
                                Circle()
                                    .fill(style.color.opacity(0.18))
                                    .frame(width: 32, height: 32)
                                Image(systemName: style.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(style.color)
                            }
                            
                            Text(name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Button(action: { moveUp(at: idx) }) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(idx > 0 ? AppleTheme.labelSecondary : AppleTheme.labelTertiary.opacity(0.3))
                            }
                            .disabled(idx == 0)
                            .buttonStyle(.plain)
                            
                            Button(action: { moveDown(at: idx) }) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(idx < selectedNames.count - 1 ? AppleTheme.labelSecondary : AppleTheme.labelTertiary.opacity(0.3))
                            }
                            .disabled(idx >= selectedNames.count - 1)
                            .buttonStyle(.plain)
                            
                            Button(action: { toggleCategory(name) }) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(selectedNames.count > 1 ? AppleTheme.accentRed : AppleTheme.labelTertiary.opacity(0.3))
                            }
                            .disabled(selectedNames.count <= 1)
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        
                        if idx < selectedNames.count - 1 {
                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 56)
                        }
                    }
                }
            }
            .background(AppleTheme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                    .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
            )
            .padding(.horizontal, 20)
        }
    }
    
    @ViewBuilder
    private var availableCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ALL EXPENSE CATEGORIES (TAP TO ADD UP TO 8)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(AppleTheme.labelSecondary)
                .kerning(0.8)
                .padding(.horizontal, 24)
            
            VStack(spacing: 0) {
                ForEach(Array(allExpenseCategories.enumerated()), id: \.element.id) { idx, cat in
                    let isSelected = selectedNames.contains(where: { $0.caseInsensitiveCompare(cat.name) == .orderedSame })
                    let style = CategoryStyle.style(for: cat.name)
                    VStack(spacing: 0) {
                        Button(action: { toggleCategory(cat.name) }) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(style.color.opacity(0.18))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: style.icon)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(style.color)
                                }
                                
                                Text(cat.name)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                                    .font(.system(size: 20))
                                    .foregroundColor(isSelected ? AppleTheme.accentGreen : (selectedNames.count >= 8 ? AppleTheme.labelTertiary.opacity(0.35) : AppleTheme.accentBlue))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                        }
                        .buttonStyle(.plain)
                        
                        if idx < allExpenseCategories.count - 1 {
                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 60)
                        }
                    }
                }
            }
            .background(AppleTheme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                    .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
            )
            .padding(.horizontal, 20)
        }
    }
    
    @ViewBuilder
    private var howToAddWidgetBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 20))
                .foregroundColor(AppleTheme.accentBlue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Add to Your iPhone Home Screen")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text("Long-press your iPhone Home Screen → tap Edit (+) → search for BudgetTracker → choose the Medium (Wider) Quick Expense Logger widget. Tapping any icon opens that category's keypad immediately.")
                    .font(.system(size: 12))
                    .foregroundColor(AppleTheme.labelSecondary)
            }
        }
        .padding(16)
        .background(AppleTheme.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
        )
        .padding(.horizontal, 20)
    }
    
    private func toggleCategory(_ name: String) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            if let existingIdx = selectedNames.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                if selectedNames.count > 1 {
                    selectedNames.remove(at: existingIdx)
                }
            } else if selectedNames.count < 8 {
                selectedNames.append(name)
            }
            persistSelection()
        }
    }
    
    private func moveUp(at idx: Int) {
        guard idx > 0 else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            selectedNames.swapAt(idx, idx - 1)
            persistSelection()
        }
    }
    
    private func moveDown(at idx: Int) {
        guard idx < selectedNames.count - 1 else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            selectedNames.swapAt(idx, idx + 1)
            persistSelection()
        }
    }
    
    private func persistSelection() {
        WidgetDataStore.saveSelectedCategoryNames(selectedNames)
        WidgetDataStore.saveSelectedTimeframe(selectedTimeframe)
        db.syncWidgetSnapshot()
    }
}

// MARK: - Recurring Transactions Manager View (3 Sub-Columns: Exp, Income, Transfer)
struct RecurringTransactionsManagerView: View {
    @ObservedObject var db: DatabaseManager
    @Binding var isPresented: Bool
    
    @State private var selectedColumn: RecurringTransactionType = .expense
    @State private var showingAddSheet: Bool = false
    @State private var editingItem: RecurringPayment? = nil
    
    private var expenseItems: [RecurringPayment] {
        db.recurringPayments.filter { $0.type == .expense }
    }
    
    private var incomeItems: [RecurringPayment] {
        db.recurringPayments.filter { $0.type == .income }
    }
    
    private var transferItems: [RecurringPayment] {
        db.recurringPayments.filter { $0.type == .transfer }
    }
    
    private var activeColumnItems: [RecurringPayment] {
        switch selectedColumn {
        case .expense: return expenseItems
        case .income: return incomeItems
        case .transfer: return transferItems
        }
    }
    
    private func monthlyTotal(for type: RecurringTransactionType) -> Double {
        db.recurringPayments
            .filter { $0.type == type && $0.isActive }
            .reduce(0.0) { $0 + $1.normalizedMonthlyAmount }
    }
    
    private func itemsCount(for type: RecurringTransactionType) -> Int {
        switch type {
        case .expense: return expenseItems.count
        case .income: return incomeItems.count
        case .transfer: return transferItems.count
        }
    }
    
    private func accentColor(for type: RecurringTransactionType) -> Color {
        switch type {
        case .expense: return AppleTheme.accentRed
        case .income: return AppleTheme.accentGreen
        case .transfer: return AppleTheme.accentBlue
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppleTheme.bgCanvas.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        summaryColumnsBar
                        
                        // 3 Sub-Columns Segmented Picker: Exp | Income | Transfer
                        Picker("Recurring Type", selection: $selectedColumn) {
                            ForEach(RecurringTransactionType.allCases) { col in
                                Text(col.rawValue).tag(col)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal, 20)
                        
                        sectionHeaderRow
                        
                        if activeColumnItems.isEmpty {
                            emptyStateCard
                        } else {
                            recurringListCard
                        }
                        
                        Spacer(minLength: 60)
                    }
                }
            }
            .navigationTitle("Recurring Transactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { isPresented = false }
                        .foregroundColor(AppleTheme.accentBlue)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(AppleTheme.accentBlue)
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                RecurringPaymentEditorSheet(
                    db: db,
                    isPresented: $showingAddSheet,
                    initialType: selectedColumn,
                    editingItem: nil
                )
            }
            .sheet(item: $editingItem) { item in
                RecurringPaymentEditorSheet(
                    db: db,
                    isPresented: Binding(
                        get: { editingItem != nil },
                        set: { if !$0 { editingItem = nil } }
                    ),
                    initialType: item.type,
                    editingItem: item
                )
            }
        }
        .preferredColorScheme(.dark)
    }
    
    @ViewBuilder
    private var summaryColumnsBar: some View {
        HStack(spacing: 10) {
            ForEach(RecurringTransactionType.allCases) { col in
                summaryColumnCard(for: col)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
    
    @ViewBuilder
    private func summaryColumnCard(for col: RecurringTransactionType) -> some View {
        let isSelected = selectedColumn == col
        let colColor = accentColor(for: col)
        let total = monthlyTotal(for: col)
        let count = itemsCount(for: col)
        let countLabel = count == 1 ? "1 item / mo" : "\(count) items / mo"
        
        Button(action: {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                selectedColumn = col
            }
        }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(colColor)
                        .frame(width: 7, height: 7)
                    Text(col.rawValue.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isSelected ? .white : AppleTheme.labelSecondary)
                        .kerning(0.5)
                    Spacer(minLength: 0)
                }
                
                Text(formatWholeWithCommas(total))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                
                Text(countLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isSelected ? colColor : AppleTheme.labelTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(isSelected ? colColor.opacity(0.16) : AppleTheme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? colColor : Color.white.opacity(0.08), lineWidth: isSelected ? 1.2 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var sectionHeaderRow: some View {
        HStack {
            Text("RECURRING \(selectedColumn.displayTitle.uppercased())S (\(activeColumnItems.count))")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(AppleTheme.labelSecondary)
                .kerning(0.8)
            
            Spacer()
            
            Button(action: { showingAddSheet = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("Add \(selectedColumn.rawValue)")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(accentColor(for: selectedColumn))
            }
        }
        .padding(.horizontal, 24)
    }
    
    @ViewBuilder
    private var emptyStateCard: some View {
        let colColor = accentColor(for: selectedColumn)
        let iconName = selectedColumn == .transfer ? "arrow.left.arrow.right" : "repeat"
        
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(colColor.opacity(0.14))
                    .frame(width: 54, height: 54)
                Image(systemName: iconName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(colColor)
            }
            
            Text("No Recurring \(selectedColumn.displayTitle)s")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            
            Text("Add a recurring \(selectedColumn.displayTitle.lowercased()) here or toggle 'Repeat' when logging a transaction.")
                .font(.system(size: 13))
                .foregroundColor(AppleTheme.labelSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button(action: { showingAddSheet = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add Recurring \(selectedColumn.displayTitle)")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(colColor)
                .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(AppleTheme.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
        )
        .padding(.horizontal, 20)
    }
    
    @ViewBuilder
    private var recurringListCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(activeColumnItems.enumerated()), id: \.element.id) { idx, item in
                recurringRowView(for: item)
                
                if idx < activeColumnItems.count - 1 {
                    Divider()
                        .background(Color.white.opacity(0.06))
                        .padding(.leading, 66)
                }
            }
        }
        .background(AppleTheme.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
        )
        .padding(.horizontal, 20)
    }
    
    @ViewBuilder
    private func recurringRowView(for item: RecurringPayment) -> some View {
        let style = item.type == .transfer
            ? CategoryStyle(icon: "arrow.left.arrow.right", color: AppleTheme.accentBlue, emoji: "🔄")
            : CategoryStyle.style(for: item.categoryName ?? item.name)
        let accName = db.accountsByID[item.accountID ?? ""]?.name
        let typeColor = accentColor(for: item.type)
        let amtColor: Color = !item.isActive ? AppleTheme.labelSecondary : (item.type == .income ? AppleTheme.accentGreen : .white)
        
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(item.isActive ? style.color : AppleTheme.bgTertiary)
                    .frame(width: 38, height: 38)
                Image(systemName: style.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(item.isActive ? .white : AppleTheme.labelSecondary)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(item.isActive ? .white : AppleTheme.labelSecondary)
                        .lineLimit(1)
                    
                    Text(item.frequency.rawValue)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(typeColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(typeColor.opacity(0.16))
                        .clipShape(Capsule())
                    
                    if !item.isActive {
                        Text("Paused")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(AppleTheme.accentOrange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppleTheme.accentOrange.opacity(0.16))
                            .clipShape(Capsule())
                    }
                }
                
                HStack(spacing: 6) {
                    if let catName = item.categoryName, !catName.isEmpty, item.type != .transfer {
                        Text(catName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppleTheme.labelSecondary)
                    } else if item.type == .transfer {
                        Text("Transfer")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppleTheme.labelSecondary)
                    }
                    
                    if let acc = accName {
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(AppleTheme.labelTertiary)
                        Text(acc)
                            .font(.system(size: 11))
                            .foregroundColor(AppleTheme.labelSecondary)
                            .lineLimit(1)
                    }
                    
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(AppleTheme.labelTertiary)
                    Text("Next: \(item.nextDueDate)")
                        .font(.system(size: 11))
                        .foregroundColor(AppleTheme.labelTertiary)
                        .lineLimit(1)
                }
                
                if let n = item.notes, !n.isEmpty {
                    Text(n)
                        .font(.system(size: 11))
                        .foregroundColor(AppleTheme.labelSecondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatCurrencyWithCommas(item.amount, showSign: item.type == .income))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(amtColor)
                
                if item.frequency != .monthly {
                    Text("\(formatCurrencyWithCommas(item.normalizedMonthlyAmount))/mo")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(AppleTheme.labelTertiary)
                }
            }
            
            Menu {
                Button {
                    editingItem = item
                } label: {
                    Label("Edit Recurring", systemImage: "pencil")
                }
                
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    db.toggleRecurringPaymentActive(id: item.id)
                } label: {
                    Label(item.isActive ? "Pause Recurring" : "Resume Recurring", systemImage: item.isActive ? "pause.circle" : "play.circle")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    db.deleteRecurringPayment(id: item.id)
                } label: {
                    Label("Delete Recurring", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 17))
                    .foregroundColor(AppleTheme.labelSecondary)
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .onTapGesture {
            editingItem = item
        }
        .contextMenu {
            Button {
                editingItem = item
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button {
                db.toggleRecurringPaymentActive(id: item.id)
            } label: {
                Label(item.isActive ? "Pause" : "Resume", systemImage: item.isActive ? "pause.circle" : "play.circle")
            }
            Button(role: .destructive) {
                db.deleteRecurringPayment(id: item.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Add / Edit Recurring Payment Sheet
struct RecurringPaymentEditorSheet: View {
    @ObservedObject var db: DatabaseManager
    @Binding var isPresented: Bool
    var initialType: RecurringTransactionType = .expense
    var editingItem: RecurringPayment? = nil
    
    @AppStorage("selectedCurrencySymbol") private var currencySymbol: String = "$"
    
    @State private var type: RecurringTransactionType = .expense
    @State private var name: String = ""
    @State private var amountString: String = ""
    @State private var selectedCategoryID: Int? = nil
    @State private var selectedAccountID: String? = nil
    @State private var frequency: RecurringFrequency = .monthly
    @State private var isActive: Bool = true
    @State private var notes: String = ""
    
    private var filteredCategories: [Category] {
        switch type {
        case .expense:
            return db.categories.filter { !CategoryStyle.style(for: $0.name).isIncome }
        case .income:
            return db.categories.filter { CategoryStyle.style(for: $0.name).isIncome }
        case .transfer:
            return []
        }
    }
    
    private var selectedCategoryName: String? {
        db.categories.first(where: { $0.id == selectedCategoryID })?.name
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppleTheme.bgCanvas.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        typePickerSection
                        amountHeaderCard
                        detailsFormCard
                        actionButtonsSection
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle(editingItem == nil ? "New Recurring" : "Edit Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .foregroundColor(AppleTheme.accentBlue)
                }
            }
            .onAppear(perform: configureInitialState)
        }
        .preferredColorScheme(.dark)
    }
    
    @ViewBuilder
    private var typePickerSection: some View {
        Picker("Type", selection: $type) {
            ForEach(RecurringTransactionType.allCases) { t in
                Text(t.rawValue).tag(t)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .onChange(of: type) { _, newType in
            if newType == .transfer {
                selectedCategoryID = nil
            } else if let firstCat = filteredCategories.first {
                if selectedCategoryID == nil || !filteredCategories.contains(where: { $0.id == selectedCategoryID }) {
                    selectedCategoryID = firstCat.id
                }
            }
        }
    }
    
    @ViewBuilder
    private var amountHeaderCard: some View {
        let accentColor: Color = type == .income ? AppleTheme.accentGreen : (type == .transfer ? AppleTheme.accentBlue : AppleTheme.accentRed)
        VStack(spacing: 6) {
            Text("RECURRING \(type.displayTitle.uppercased()) AMOUNT")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppleTheme.labelSecondary)
                .kerning(0.8)
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(currencySymbol)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(accentColor)
                
                TextField("0.00", text: $amountString)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .keyboardType(.decimalPad)
            }
        }
        .padding(18)
        .background(AppleTheme.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
        )
        .padding(.horizontal, 20)
    }
    
    @ViewBuilder
    private var merchantSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(type == .transfer ? "Transfer Name" : "Tag / Name")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                TextField(type == .transfer ? "e.g. Rent Transfer, TFSA" : "e.g. Netflix, Gym, Salary", text: $name)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.white)
            }
            
            if type != .transfer {
                let merchants = db.allKnownMerchants(for: selectedCategoryName)
                if !merchants.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(merchants, id: \.self) { merch in
                                let isSel = name.caseInsensitiveCompare(merch) == .orderedSame
                                Button(action: {
                                    name = isSel ? "" : merch
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "tag.fill")
                                            .font(.system(size: 9))
                                        Text(merch)
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .foregroundColor(isSel ? .white : AppleTheme.accentBlue)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(isSel ? AppleTheme.accentBlue : AppleTheme.accentBlue.opacity(0.15))
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }
    
    @ViewBuilder
    private var detailsFormCard: some View {
        VStack(spacing: 0) {
            merchantSection
            
            Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
            
            // Frequency Picker
            HStack {
                Text("Frequency")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                Picker("Frequency", selection: $frequency) {
                    ForEach(RecurringFrequency.allCases) { freq in
                        Text(freq.rawValue).tag(freq)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .tint(AppleTheme.accentBlue)
            }
            .padding()
            
            if type != .transfer {
                Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
                
                HStack {
                    Text("Category")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Picker("Category", selection: $selectedCategoryID) {
                        ForEach(filteredCategories) { cat in
                            Text(cat.name).tag(cat.id as Int?)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .tint(AppleTheme.labelSecondary)
                }
                .padding()
            }
            
            Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
            
            HStack {
                Text("Account")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                Picker("Account", selection: $selectedAccountID) {
                    Text("None").tag(nil as String?)
                    ForEach(db.accounts) { acc in
                        Text(db.accountBreadcrumb(for: acc.id)).tag(acc.id as String?)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .tint(AppleTheme.labelSecondary)
            }
            .padding()
            
            Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
            
            HStack {
                Text("Notes")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                TextField("Optional note", text: $notes)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(AppleTheme.labelSecondary)
            }
            .padding()
            
            if editingItem != nil {
                Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
                
                HStack {
                    Text("Active Schedule")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Toggle("", isOn: $isActive)
                        .labelsHidden()
                        .tint(AppleTheme.accentGreen)
                }
                .padding()
            }
        }
        .background(AppleTheme.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
        )
        .padding(.horizontal, 20)
    }
    
    @ViewBuilder
    private var actionButtonsSection: some View {
        let isInvalid = name.trimmingCharacters(in: .whitespaces).isEmpty || (Double(amountString) ?? 0) <= 0
        Button(action: saveItem) {
            Text(editingItem == nil ? "Add Recurring \(type.displayTitle)" : "Save Changes")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AppleTheme.accentBlue)
                .clipShape(RoundedRectangle(cornerRadius: AppleTheme.buttonCornerRadius, style: .continuous))
        }
        .disabled(isInvalid)
        .opacity(isInvalid ? 0.4 : 1.0)
        .padding(.horizontal, 20)
        
        if let existing = editingItem {
            Button(role: .destructive, action: {
                db.deleteRecurringPayment(id: existing.id)
                isPresented = false
            }) {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete Recurring Transaction")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppleTheme.accentRed)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppleTheme.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: AppleTheme.buttonCornerRadius, style: .continuous))
            }
            .padding(.horizontal, 20)
        }
    }
    
    private func configureInitialState() {
        if let item = editingItem {
            type = item.type
            name = item.name
            amountString = String(format: "%.2f", item.amount)
            selectedCategoryID = item.categoryID ?? filteredCategories.first?.id
            selectedAccountID = item.accountID
            frequency = item.frequency
            isActive = item.isActive
            notes = item.notes ?? ""
        } else {
            type = initialType
            selectedCategoryID = filteredCategories.first?.id
            selectedAccountID = db.accounts.first?.id
        }
    }
    
    private func saveItem() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let amt = Double(amountString), amt > 0 else { return }
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let catToSave = type == .transfer ? nil : selectedCategoryID
        
        if let existing = editingItem {
            db.updateRecurringPayment(
                id: existing.id,
                name: trimmedName,
                amount: amt,
                categoryID: catToSave,
                accountID: selectedAccountID,
                frequency: frequency,
                isActive: isActive,
                notes: cleanNotes.isEmpty ? nil : cleanNotes,
                type: type
            )
        } else {
            db.addRecurringPayment(
                name: trimmedName,
                amount: amt,
                categoryID: catToSave,
                accountID: selectedAccountID,
                frequency: frequency,
                startDate: Date(),
                notes: cleanNotes.isEmpty ? nil : cleanNotes,
                type: type
            )
        }
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        isPresented = false
    }
}


// MARK: - Category Keypad Entry View (Apple Cash Style Borderless Keypad with Live Math)
struct CategoryKeypadEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var db: DatabaseManager
    let category: Category
    var onSetBudget: () -> Void
    
    @AppStorage("selectedCurrencySymbol") private var currencySymbol: String = "$"
    
    @State private var amountString: String = "0"
    @State private var merchantName: String = ""
    @State private var transactionNotes: String = ""
    @State private var selectedAccount: Account? = nil
    @State private var selectedDate: Date = Date()
    @State private var isIncome: Bool = false
    @State private var isRecurring: Bool = false
    @State private var recurringFrequency: RecurringFrequency = .monthly
    @State private var showingDatePicker = false
    @State private var showingMerchantPrompt = false
    @State private var showingNotePrompt = false
    @State private var showingManageSubCategories = false
    @State private var customMerchantInput = ""
    
    private var isMathExpression: Bool {
        let trimmed = amountString.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("+") || trimmed.contains("-") || trimmed.contains("×") || trimmed.contains("÷")
    }
    
    private var evaluatedAmount: Double {
        if let val = evaluateMathExpressionSafely(amountString) {
            return max(0.0, val)
        }
        return Double(amountString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
    }
    
    private var datePillText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(selectedDate) {
            return "Today"
        } else if calendar.isDateInYesterday(selectedDate) {
            return "Yesterday"
        } else {
            let df = DateFormatter()
            df.dateFormat = "MMM d"
            return df.string(from: selectedDate)
        }
    }
    
    var body: some View {
        ZStack {
            AppleTheme.bgCanvas.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top Header: Cancel, Title, Budget Info
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppleTheme.labelSecondary)
                            .padding(8)
                            .background(AppleTheme.bgTertiary)
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    // Category Badge Header
                    HStack(spacing: 6) {
                        let style = CategoryStyle.style(for: category.name)
                        Circle().fill(style.color).frame(width: 8, height: 8)
                        Text(category.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Button(action: onSetBudget) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppleTheme.accentBlue)
                            .padding(8)
                            .background(AppleTheme.bgTertiary)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                
                Spacer()
                
                // Huge Apple Cash Amount Figure
                VStack(spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(isIncome ? "+\(currencySymbol)" : "-\(currencySymbol)")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(isIncome ? AppleTheme.accentGreen : AppleTheme.accentRed)
                        
                        Text(amountString)
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .contentTransition(.numericText())
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(.horizontal, 24)
                    
                    // Live Math evaluation preview
                    if isMathExpression {
                        Text("= \(currencySymbol)\(String(format: "%.2f", evaluatedAmount))")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(AppleTheme.accentOrange)
                    }
                }
                
                Spacer()
                
                // Compact Apple HIG Option Pills: Tag Sliding Pill Row above (Payment Method | Date | Repeat | Notes | Type)
                VStack(spacing: 10) {
                    // Row 1: Sliding Tag Pills (Above Payment Method, Date, Repeat, Notes)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            let knownMerchants = db.allKnownMerchants(for: category.name)
                            
                            // Primary Tag Menu Pill
                            Menu {
                                if !knownMerchants.isEmpty {
                                    Text("SAVED TAGS")
                                    ForEach(knownMerchants, id: \.self) { merch in
                                        Button {
                                            merchantName = (merchantName.caseInsensitiveCompare(merch) == .orderedSame ? "" : merch)
                                        } label: {
                                            if merchantName.caseInsensitiveCompare(merch) == .orderedSame {
                                                Label(merch, systemImage: "checkmark")
                                            } else {
                                                Text(merch)
                                            }
                                        }
                                    }
                                    Divider()
                                }
                                Button {
                                    customMerchantInput = merchantName
                                    showingMerchantPrompt = true
                                } label: {
                                    Label("Custom Tag...", systemImage: "plus")
                                }
                                Button {
                                    showingManageSubCategories = true
                                } label: {
                                    Label("Manage Tags...", systemImage: "slider.horizontal.3")
                                }
                                if !merchantName.isEmpty {
                                    Button(role: .destructive) {
                                        merchantName = ""
                                    } label: {
                                        Label("Clear Tag", systemImage: "trash")
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "tag.fill")
                                        .font(.system(size: 11))
                                    Text(merchantName.isEmpty ? "Tag" : merchantName)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                }
                                .foregroundColor(merchantName.isEmpty ? .white : AppleTheme.accentBlue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(merchantName.isEmpty ? AppleTheme.bgTertiary : AppleTheme.accentBlue.opacity(0.2))
                                .clipShape(Capsule())
                            }
                            
                            // Quick-Select Sliding Tag Pills for this Category
                            ForEach(knownMerchants, id: \.self) { merch in
                                let isSelected = merchantName.caseInsensitiveCompare(merch) == .orderedSame
                                Button(action: {
                                    triggerKeyHaptic()
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        merchantName = isSelected ? "" : merch
                                    }
                                }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "tag.fill")
                                            .font(.system(size: 10))
                                        Text(merch)
                                            .font(.system(size: 12, weight: .semibold))
                                            .lineLimit(1)
                                    }
                                    .foregroundColor(isSelected ? .white : AppleTheme.labelSecondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(isSelected ? AppleTheme.accentBlue : AppleTheme.bgTertiary)
                                    .clipShape(Capsule())
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        if isSelected { merchantName = "" }
                                        db.deleteMerchant(name: merch, for: category.name)
                                    } label: {
                                        Label("Remove Tag Pill", systemImage: "trash")
                                    }
                                }
                            }
                            
                            // Quick "+ New Tag" Pill
                            Button(action: {
                                triggerKeyHaptic()
                                customMerchantInput = ""
                                showingMerchantPrompt = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("New Tag")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(AppleTheme.accentBlue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppleTheme.bgTertiary)
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // Row 2: Payment Method (Account) | Date | Repeat (Recurring) | Notes | Expense/Income
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // Account (Payment Method) Selector Pill
                            Menu {
                                if db.accounts.isEmpty {
                                    Text("No Accounts Configured")
                                } else {
                                    ForEach(db.accounts) { acc in
                                        Button("\(acc.name) (\(formatCurrencyWithCommas(acc.balance)))") {
                                            selectedAccount = acc
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "creditcard.fill")
                                        .font(.system(size: 11))
                                    Text(selectedAccount?.name ?? (db.accounts.isEmpty ? "No Account" : "Account"))
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppleTheme.bgTertiary)
                                .clipShape(Capsule())
                            }
                            
                            // Date Selector Pill
                            Button(action: { showingDatePicker = true }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 11))
                                    Text(datePillText)
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppleTheme.bgTertiary)
                                .clipShape(Capsule())
                            }
                            
                            // Repeat / Recurring Selector Pill
                            Menu {
                                Button {
                                    isRecurring = false
                                } label: {
                                    if !isRecurring {
                                        Label("One-Time (Not Recurring)", systemImage: "checkmark")
                                    } else {
                                        Text("One-Time (Not Recurring)")
                                    }
                                }
                                Divider()
                                ForEach(RecurringFrequency.allCases) { freq in
                                    Button {
                                        isRecurring = true
                                        recurringFrequency = freq
                                    } label: {
                                        if isRecurring && recurringFrequency == freq {
                                            Label("Repeat \(freq.rawValue)", systemImage: "checkmark")
                                        } else {
                                            Text("Repeat \(freq.rawValue)")
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "repeat")
                                        .font(.system(size: 11, weight: .bold))
                                    Text(isRecurring ? recurringFrequency.rawValue : "Repeat")
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                }
                                .foregroundColor(isRecurring ? AppleTheme.accentBlue : .white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(isRecurring ? AppleTheme.accentBlue.opacity(0.2) : AppleTheme.bgTertiary)
                                .clipShape(Capsule())
                            }
                            
                            // Note / Memo Pill
                            Button(action: { showingNotePrompt = true }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "note.text")
                                        .font(.system(size: 11))
                                    Text(transactionNotes.isEmpty ? "Notes" : String(transactionNotes.prefix(8)))
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                }
                                .foregroundColor(transactionNotes.isEmpty ? .white : AppleTheme.accentOrange)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(transactionNotes.isEmpty ? AppleTheme.bgTertiary : AppleTheme.accentOrange.opacity(0.2))
                                .clipShape(Capsule())
                            }
                            
                            // Expense vs Income toggle
                            Button(action: {
                                #if os(iOS)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                                withAnimation { isIncome.toggle() }
                            }) {
                                Text(isIncome ? "Income" : "Expense")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(isIncome ? AppleTheme.accentGreen : AppleTheme.accentRed)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(AppleTheme.bgTertiary)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // Borderless Numeric Keypad with Live Math (Apple Cash Style)
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            AppleKeypadButton(title: "1", action: { appendDigit("1") })
                            AppleKeypadButton(title: "2", action: { appendDigit("2") })
                            AppleKeypadButton(title: "3", action: { appendDigit("3") })
                            AppleKeypadButton(title: "÷", tint: AppleTheme.accentBlue, action: { appendOperator("÷") })
                        }
                        
                        HStack(spacing: 12) {
                            AppleKeypadButton(title: "4", action: { appendDigit("4") })
                            AppleKeypadButton(title: "5", action: { appendDigit("5") })
                            AppleKeypadButton(title: "6", action: { appendDigit("6") })
                            AppleKeypadButton(title: "×", tint: AppleTheme.accentBlue, action: { appendOperator("×") })
                        }
                        
                        HStack(spacing: 12) {
                            AppleKeypadButton(title: "7", action: { appendDigit("7") })
                            AppleKeypadButton(title: "8", action: { appendDigit("8") })
                            AppleKeypadButton(title: "9", action: { appendDigit("9") })
                            AppleKeypadButton(title: "-", tint: AppleTheme.accentBlue, action: { appendOperator("-") })
                        }
                        
                        HStack(spacing: 12) {
                            AppleKeypadButton(title: ".", action: appendDot)
                            AppleKeypadButton(title: "0", action: { appendDigit("0") })
                            AppleKeypadIconButton(systemName: "delete.backward.fill", action: deleteDigit)
                            AppleKeypadButton(title: "+", tint: AppleTheme.accentBlue, action: { appendOperator("+") })
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Primary Log Button (Apple Pay rounded button)
                    Button(action: saveTransaction) {
                        HStack {
                            Image(systemName: isRecurring ? "repeat" : "checkmark")
                                .font(.system(size: 16, weight: .bold))
                            Text(isRecurring ? (isIncome ? "Log Recurring Income (\(recurringFrequency.rawValue))" : "Log Recurring Expense (\(recurringFrequency.rawValue))") : (isIncome ? "Log Income" : "Log Expense"))
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(isIncome ? AppleTheme.accentGreen : AppleTheme.accentBlue)
                        .clipShape(RoundedRectangle(cornerRadius: AppleTheme.buttonCornerRadius, style: .continuous))
                        .shadow(color: (isIncome ? AppleTheme.accentGreen : AppleTheme.accentBlue).opacity(0.35), radius: 10, x: 0, y: 5)
                    }
                    .disabled(evaluatedAmount <= 0)
                    .opacity(evaluatedAmount <= 0 ? 0.4 : 1.0)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                }
            }
        }
        .onAppear {
            let catStyle = CategoryStyle.style(for: category.name)
            isIncome = catStyle.isIncome
            if selectedAccount == nil {
                selectedAccount = db.accounts.first
            }
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Transaction Date")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingDatePicker = false }
                        }
                    }
            }
            .presentationDetents([.fraction(0.55)])
        }
        .alert("New Tag", isPresented: $showingMerchantPrompt) {
            TextField("e.g. Costco, Rent, Gym", text: $customMerchantInput)
            Button("Save Tag") {
                let trimmed = customMerchantInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    merchantName = trimmed
                    db.addMerchant(name: trimmed, for: category.name)
                }
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Transaction Notes", isPresented: $showingNotePrompt) {
            TextField("Add a note, context, or receipt memo...", text: $transactionNotes)
            Button("Done", role: .cancel) { }
        }
        .sheet(isPresented: $showingManageSubCategories) {
            ManageSubCategoriesSheetView(
                db: db,
                initialCategoryName: category.name,
                selectedSubCategory: $merchantName
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
    
    private func appendDigit(_ digit: String) {
        triggerKeyHaptic()
        if amountString == "0" {
            amountString = digit
        } else {
            amountString += digit
        }
    }
    
    private func appendDot() {
        triggerKeyHaptic()
        let trimmed = amountString.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastSegment = trimmed.components(separatedBy: CharacterSet(charactersIn: "+-×÷*/ ")).last ?? ""
        if !lastSegment.contains(".") {
            if lastSegment.isEmpty {
                amountString += "0."
            } else {
                amountString += "."
            }
        }
    }
    
    private func appendOperator(_ op: String) {
        triggerKeyHaptic()
        var trimmed = amountString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "0" {
            return
        }
        // If it already ends with an operator, replace it cleanly
        while let last = trimmed.last, last == "+" || last == "-" || last == "×" || last == "÷" || last == "*" || last == "/" {
            trimmed.removeLast()
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        amountString = "\(trimmed) \(op) "
    }
    
    private func deleteDigit() {
        triggerKeyHaptic()
        var trimmed = amountString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 1 {
            amountString = "0"
            return
        }
        trimmed.removeLast()
        trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        amountString = trimmed.isEmpty ? "0" : trimmed
    }
    
    private func triggerKeyHaptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    
    private func saveTransaction() {
        let finalAmount = isIncome ? -evaluatedAmount : evaluatedAmount
        guard finalAmount != 0 else { return }
        
        let trimmedMerchant = merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalMerchant = trimmedMerchant.isEmpty ? category.name : trimmedMerchant
        let cleanNotes = transactionNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        
        db.addTransaction(
            date: selectedDate,
            amount: finalAmount,
            categoryID: category.id,
            merchant: finalMerchant,
            subCategory: nil,
            notes: cleanNotes.isEmpty ? nil : cleanNotes,
            source: "manual",
            accountID: selectedAccount?.id,
            isRecurring: isRecurring,
            recurringFrequency: isRecurring ? recurringFrequency.rawValue : nil
        )
        
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        dismiss()
    }
}

// Borderless Keypad Button
struct AppleKeypadButton: View {
    let title: String
    var tint: Color = .white
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 26, weight: .regular, design: .rounded))
                .foregroundColor(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(AppleTheme.bgTertiary.opacity(0.8))
                .clipShape(Circle())
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct AppleKeypadIconButton: View {
    let systemName: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(AppleTheme.labelSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(AppleTheme.bgTertiary.opacity(0.8))
                .clipShape(Circle())
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Crash-Proof Pure-Swift Math Evaluator
public func evaluateMathExpressionSafely(_ input: String) -> Double? {
    let sanitized = input
        .replacingOccurrences(of: "×", with: "*")
        .replacingOccurrences(of: "÷", with: "/")
        .replacingOccurrences(of: ",", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    
    guard !sanitized.isEmpty else { return nil }
    
    var tokens: [String] = []
    var currentNumber = ""
    
    var index = sanitized.startIndex
    while index < sanitized.endIndex {
        let char = sanitized[index]
        if char == " " {
            index = sanitized.index(after: index)
            continue
        }
        
        if char == "+" || char == "-" || char == "*" || char == "/" {
            if !currentNumber.isEmpty {
                tokens.append(currentNumber)
                currentNumber = ""
            }
            if char == "-" && (tokens.isEmpty || ["+", "-", "*", "/"].contains(tokens.last ?? "")) {
                currentNumber.append("-")
            } else {
                tokens.append(String(char))
            }
        } else if char.isNumber || char == "." {
            currentNumber.append(char)
        }
        index = sanitized.index(after: index)
    }
    
    if !currentNumber.isEmpty {
        tokens.append(currentNumber)
    }
    
    // Ignore trailing operators while user is still typing (e.g. ["5", "*"])
    while let last = tokens.last, ["+", "-", "*", "/"].contains(last) {
        tokens.removeLast()
    }
    
    guard !tokens.isEmpty else { return nil }
    
    // Pass 1: Handle multiplication (*) and division (/) with operator precedence
    var pass1Tokens: [String] = []
    var i = 0
    while i < tokens.count {
        let token = tokens[i]
        if token == "*" || token == "/" {
            guard let leftStr = pass1Tokens.popLast(),
                  let leftVal = Double(leftStr),
                  i + 1 < tokens.count,
                  let rightVal = Double(tokens[i + 1]) else {
                return nil
            }
            let res: Double
            if token == "*" {
                res = leftVal * rightVal
            } else {
                guard rightVal != 0 else { return nil }
                res = leftVal / rightVal
            }
            pass1Tokens.append(String(res))
            i += 2
        } else {
            pass1Tokens.append(token)
            i += 1
        }
    }
    
    guard let firstStr = pass1Tokens.first, var result = Double(firstStr) else {
        return nil
    }
    
    // Pass 2: Handle addition (+) and subtraction (-)
    var j = 1
    while j < pass1Tokens.count {
        let op = pass1Tokens[j]
        guard j + 1 < pass1Tokens.count, let nextVal = Double(pass1Tokens[j + 1]) else {
            break
        }
        if op == "+" {
            result += nextVal
        } else if op == "-" {
            result -= nextVal
        }
        j += 2
    }
    
    return result
}

// MARK: - Account Detail Sheet View
struct AccountDetailSheetView: View {
    @ObservedObject var db: DatabaseManager
    let account: Account
    var onLogExpense: () -> Void
    var onTransfer: () -> Void
    var onPayCreditCard: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditBalance = false
    @State private var balanceInput = ""
    @State private var showingDeleteConfirm = false
    @State private var showingEditAccount = false
    @State private var showingAddSubAccount = false
    @State private var isSubAccountsExpanded = true
    @State private var editingTx: Transaction? = nil
    
    /// Always read live account from db so balance adjustments reflect immediately
    private var liveAccount: Account {
        db.accounts.first(where: { $0.id == account.id }) ?? account
    }
    
    private var accountTransactions: [Transaction] {
        db.transactions(for: liveAccount.id)
    }
    
    private var directSubAccounts: [Account] {
        db.subAccounts(of: liveAccount.id)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppleTheme.bgCanvas.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Hierarchy Breadcrumb if nested debit account
                        if liveAccount.type == .debit && liveAccount.parentID != nil {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(AppleTheme.accentBlue)
                                Text(db.accountBreadcrumb(for: liveAccount.id))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(AppleTheme.labelSecondary)
                                Spacer()
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 6)
                        }
                        
                        // Physical Card Header Preview
                        PhysicalAccountCardView(
                            account: liveAccount,
                            hideBalance: false,
                            isSubAccount: liveAccount.type == .debit && liveAccount.parentID != nil,
                            subAccountCount: liveAccount.type == .debit ? directSubAccounts.count : 0,
                            cumulativeBalance: db.effectiveBalance(for: liveAccount.id),
                            isExpanded: isSubAccountsExpanded,
                            onTap: {},
                            onEdit: { showingEditAccount = true },
                            onAddSubAccount: (liveAccount.type == .debit && db.accountHierarchyDepth(for: liveAccount.id) < 2) ? { showingAddSubAccount = true } : nil,
                            onToggleExpand: (liveAccount.type == .debit && !directSubAccounts.isEmpty) ? {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isSubAccountsExpanded.toggle()
                                }
                            } : nil,
                            onToggleIncludeInNetWorth: {
                                db.toggleAccountIncludeInNetWorth(id: liveAccount.id)
                            },
                            onPay: liveAccount.isLiability ? {
                                if let onPay = onPayCreditCard {
                                    onPay()
                                } else {
                                    onTransfer()
                                }
                            } : nil
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, (liveAccount.type == .debit && liveAccount.parentID != nil) ? 0 : 10)
                        
                        // Include in Parent & Net Worth quick toggle bar (Debit Accounts ONLY)
                        if liveAccount.type == .debit {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Include in Parent & Net Worth")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                    Text(liveAccount.includeInNetWorth ? "Counted toward parent account & Net Worth" : "Excluded from parent account & Net Worth")
                                        .font(.system(size: 11))
                                        .foregroundColor(liveAccount.includeInNetWorth ? AppleTheme.labelSecondary : AppleTheme.accentOrange)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { liveAccount.includeInNetWorth },
                                    set: { _ in
                                        db.toggleAccountIncludeInNetWorth(id: liveAccount.id)
                                    }
                                ))
                                .labelsHidden()
                                .tint(AppleTheme.accentGreen)
                            }
                            .padding(14)
                            .background(AppleTheme.bgCard)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                            )
                            .padding(.horizontal, 20)
                        }
                        
                        // Credit Card Rewards Summary Card (Credit Accounts ONLY)
                        if liveAccount.type == .credit {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    HStack(spacing: 6) {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(AppleTheme.accentYellow)
                                        Text("REWARD RATES & BONUS CATEGORIES")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(AppleTheme.labelSecondary)
                                            .kerning(0.8)
                                    }
                                    Spacer()
                                    Button(action: { showingEditAccount = true }) {
                                        Text(liveAccount.hasRewardRatesConfigured ? "Edit Rates" : "Set Rates")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(AppleTheme.accentBlue)
                                    }
                                }
                                
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Base Rate")
                                            .font(.system(size: 11))
                                            .foregroundColor(AppleTheme.labelSecondary)
                                        Text(Account.formatRate(liveAccount.baseRate))
                                            .font(.system(size: 18, weight: .bold, design: .rounded))
                                            .foregroundColor(.white)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(AppleTheme.bgTertiary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    
                                    if let topTier = liveAccount.activeBonusTiers.max(by: { $0.rate < $1.rate }) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Top Bonus Rate")
                                                .font(.system(size: 11))
                                                .foregroundColor(AppleTheme.labelSecondary)
                                            Text(Account.formatRate(topTier.rate))
                                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                                .foregroundColor(AppleTheme.accentGreen)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(AppleTheme.accentGreen.opacity(0.14))
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    
                                    Spacer()
                                }
                                
                                if !liveAccount.activeBonusTiers.isEmpty {
                                    ForEach(liveAccount.activeBonusTiers) { tier in
                                        HStack(spacing: 6) {
                                            Text("\(Account.formatRate(tier.rate)):")
                                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                                .foregroundColor(AppleTheme.accentGreen)
                                            Text(tier.categories.joined(separator: ", "))
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(.white)
                                        }
                                    }
                                } else {
                                    Text("Tap 'Set Rates' to configure Base Rate, Bonus Rate, and Bonus Categories.")
                                        .font(.system(size: 12))
                                        .foregroundColor(AppleTheme.labelTertiary)
                                }
                            }
                            .padding(14)
                            .background(AppleTheme.bgCard)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                            )
                            .padding(.horizontal, 20)
                        }
                        
                        // Action Buttons: Pay Card (if liability), Rename/Edit, Add Sub-Account (debit only), Transfer, Adjust, Delete
                        VStack(spacing: 10) {
                            HStack(spacing: 10) {
                                Button(action: { showingEditAccount = true }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "pencil")
                                        Text("Rename / Edit")
                                    }
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(AppleTheme.accentBlue)
                                    .clipShape(Capsule())
                                }
                                
                                if liveAccount.type == .debit && db.accountHierarchyDepth(for: liveAccount.id) < 2 {
                                    Button(action: { showingAddSubAccount = true }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "plus.rectangle.on.folder")
                                            Text("Add Sub-Account")
                                        }
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(AppleTheme.bgTertiary)
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                            
                            HStack(spacing: 10) {
                                if liveAccount.isLiability {
                                    Button(action: {
                                        if let onPay = onPayCreditCard {
                                            onPay()
                                        } else {
                                            onTransfer()
                                        }
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "creditcard.fill")
                                            Text("Pay Card")
                                        }
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(AppleTheme.accentGreen)
                                        .clipShape(Capsule())
                                    }
                                }
                                
                                Button(action: onTransfer) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.left.arrow.right")
                                        Text(liveAccount.isLiability ? "Transfer" : "Transfer Funds")
                                    }
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(AppleTheme.bgTertiary)
                                    .clipShape(Capsule())
                                }
                                
                                if directSubAccounts.isEmpty {
                                    Button(action: {
                                        balanceInput = String(format: "%.2f", liveAccount.balance)
                                        showingEditBalance = true
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "slider.horizontal.3")
                                            Text("Adjust")
                                        }
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(AppleTheme.bgTertiary)
                                        .clipShape(Capsule())
                                    }
                                }
                                
                                Button(action: { showingDeleteConfirm = true }) {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(AppleTheme.accentRed)
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 14)
                                        .background(AppleTheme.bgTertiary)
                                        .clipShape(Circle())
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Collapsible Sub-Accounts Section (Debit accounts ONLY)
                        if liveAccount.type == .debit && !directSubAccounts.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        isSubAccountsExpanded.toggle()
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: isSubAccountsExpanded ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(AppleTheme.accentBlue)
                                        Text("SUB-ACCOUNTS (\(directSubAccounts.count))")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(AppleTheme.labelSecondary)
                                            .kerning(0.8)
                                        Spacer()
                                        Text("Parent Total: \(formatCurrencyWithCommas(db.effectiveBalance(for: liveAccount.id)))")
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .foregroundColor(AppleTheme.accentBlue)
                                    }
                                    .padding(.horizontal, 24)
                                }
                                .buttonStyle(.plain)
                                
                                if isSubAccountsExpanded {
                                    VStack(spacing: 8) {
                                        ForEach(directSubAccounts) { sub in
                                            let subChildren = db.subAccounts(of: sub.id)
                                            VStack(alignment: .leading, spacing: 6) {
                                                HStack {
                                                    Image(systemName: "arrow.turn.down.right")
                                                        .font(.system(size: 12, weight: .bold))
                                                        .foregroundColor(AppleTheme.accentBlue)
                                                    Text(sub.name)
                                                        .font(.system(size: 14, weight: .semibold))
                                                        .foregroundColor(.white)
                                                    if !sub.includeInNetWorth {
                                                        Text("Excluded")
                                                            .font(.system(size: 9, weight: .bold))
                                                            .foregroundColor(AppleTheme.accentOrange)
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(AppleTheme.accentOrange.opacity(0.16))
                                                            .clipShape(Capsule())
                                                    }
                                                    if !subChildren.isEmpty {
                                                        Text("\(subChildren.count) sub")
                                                            .font(.system(size: 10, weight: .bold))
                                                            .foregroundColor(AppleTheme.accentBlue)
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(AppleTheme.accentBlue.opacity(0.15))
                                                            .clipShape(Capsule())
                                                    }
                                                    Spacer()
                                                    Text(formatCurrencyWithCommas(db.effectiveBalance(for: sub.id)))
                                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                                        .foregroundColor(sub.includeInNetWorth ? .white : AppleTheme.labelSecondary)
                                                }
                                                .padding(12)
                                                .background(AppleTheme.bgCard)
                                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                                                )
                                                
                                                // Display sub-sub-accounts if present
                                                ForEach(subChildren) { subSub in
                                                    HStack {
                                                        Image(systemName: "arrow.turn.down.right")
                                                            .font(.system(size: 10, weight: .semibold))
                                                            .foregroundColor(AppleTheme.labelSecondary)
                                                            .padding(.leading, 18)
                                                        Text(subSub.name)
                                                            .font(.system(size: 13, weight: .medium))
                                                            .foregroundColor(.white.opacity(0.85))
                                                        Spacer()
                                                        Text(formatCurrencyWithCommas(db.effectiveBalance(for: subSub.id)))
                                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                            .foregroundColor(subSub.includeInNetWorth ? .white : AppleTheme.labelSecondary)
                                                    }
                                                    .padding(10)
                                                    .background(AppleTheme.bgCard.opacity(0.7))
                                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                        
                        // Transaction History for Account
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ACCOUNT TRANSACTIONS (\(accountTransactions.count))")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(AppleTheme.labelSecondary)
                                .kerning(0.8)
                                .padding(.horizontal, 24)
                            
                            if accountTransactions.isEmpty {
                                Text("No transactions recorded on this account.")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppleTheme.labelSecondary)
                                    .padding(.horizontal, 24)
                            } else {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(accountTransactions.enumerated()), id: \.element.id) { index, tx in
                                        TransactionRowView(
                                            transaction: tx,
                                            db: db,
                                            onEdit: { editingTx = tx }
                                        )
                                        
                                        if index < accountTransactions.count - 1 {
                                            Divider()
                                                .background(Color.white.opacity(0.06))
                                                .padding(.leading, 56)
                                        }
                                    }
                                }
                                .background(AppleTheme.bgCard)
                                .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                                        .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                                )
                                .padding(.horizontal, 20)
                            }
                        }
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle(liveAccount.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppleTheme.accentBlue)
                }
            }
            .alert("Adjust Account Balance", isPresented: $showingEditBalance) {
                TextField("New Balance", text: $balanceInput)
                    .keyboardType(.decimalPad)
                Button("Update") {
                    if let newBal = Double(balanceInput) {
                        db.updateAccountBalance(id: liveAccount.id, newBalance: newBal)
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
            .alert("Delete Account?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    db.deleteAccount(id: liveAccount.id)
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will remove the account from your dashboard. Transactions associated with it will remain.")
            }
            .sheet(isPresented: $showingEditAccount) {
                EditAccountSheetView(
                    db: db,
                    account: liveAccount,
                    isPresented: $showingEditAccount
                )
                .presentationDetents([.fraction(0.85), .large])
            }
            .sheet(isPresented: $showingAddSubAccount) {
                AddAccountSheetView(
                    db: db,
                    isPresented: $showingAddSubAccount,
                    initialParentID: liveAccount.id,
                    initialAccountType: .debit
                )
                .presentationDetents([.fraction(0.85), .large])
            }
            .sheet(item: $editingTx) { tx in
                ManualEntryView(isPresented: Binding(
                    get: { editingTx != nil },
                    set: { if !$0 { editingTx = nil } }
                ), editingTransaction: tx)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Transfer Mode
enum TransferMode: String, CaseIterable, Identifiable {
    case betweenAccounts = "Between Accounts"
    case payCreditCard = "Pay Credit Card"
    case otherTransfer = "Other Transfer"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .betweenAccounts: return "arrow.left.arrow.right"
        case .payCreditCard: return "creditcard.fill"
        case .otherTransfer: return "paperplane.fill"
        }
    }
}


// MARK: - Transfer Funds & Card Payment Sheet
struct TransferFundsSheetView: View {
    @ObservedObject var db: DatabaseManager
    @Binding var isPresented: Bool
    var initialMode: TransferMode = .betweenAccounts
    var initialTargetAccountID: String? = nil
    
    @State private var mode: TransferMode
    @State private var fromAccountID: String
    @State private var toAccountID: String
    @State private var amountString: String = ""
    
    // For Other Transfer
    @State private var otherRecipient: String = ""
    @State private var otherCategoryID: Int? = nil
    @State private var otherNotes: String = ""
    
    // For External / Cash Card Payment
    private let externalSourceID = "__other__"
    @State private var externalPayerName: String = ""
    
    // Recurring Transfer Toggle & Frequency
    @State private var isRecurring: Bool = false
    @State private var recurringFrequency: RecurringFrequency = .monthly
    
    init(
        db: DatabaseManager,
        isPresented: Binding<Bool>,
        initialMode: TransferMode = .betweenAccounts,
        initialTargetAccountID: String? = nil
    ) {
        self.db = db
        self._isPresented = isPresented
        self.initialMode = initialMode
        self.initialTargetAccountID = initialTargetAccountID
        _mode = State(initialValue: initialMode)
        
        let debits = db.accounts.filter { $0.type == .debit }
        let liabilities = db.accounts.filter { $0.isLiability }
        let assets = db.accounts.filter { !$0.isLiability }
        
        let initialFrom: String
        if initialMode == .payCreditCard {
            initialFrom = debits.first?.id ?? "__other__"
        } else {
            initialFrom = assets.first?.id ?? db.accounts.first?.id ?? ""
        }
        _fromAccountID = State(initialValue: initialFrom)
        
        let initialTo: String
        if let target = initialTargetAccountID, !target.isEmpty {
            initialTo = target
        } else if initialMode == .payCreditCard {
            initialTo = liabilities.first?.id ?? ""
        } else {
            initialTo = db.accounts.first(where: { $0.id != initialFrom })?.id ?? ""
        }
        _toAccountID = State(initialValue: initialTo)
    }
    
    private var assetAccounts: [Account] {
        let assets = db.accounts.filter { !$0.isLiability }
        return assets.isEmpty ? db.accounts : assets
    }
    
    /// Only debit accounts can fund a credit card payment
    private var debitAccounts: [Account] {
        db.accounts.filter { $0.type == .debit }
    }
    
    private var defaultPaymentSourceID: String {
        debitAccounts.first?.id ?? externalSourceID
    }
    
    private var creditAccounts: [Account] {
        let liabilities = db.accounts.filter { $0.isLiability }
        return liabilities.isEmpty ? db.accounts : liabilities
    }
    
    private var targetCreditAccount: Account? {
        db.accounts.first(where: { $0.id == toAccountID })
    }
    
    private var isActionDisabled: Bool {
        guard let amt = Double(amountString), amt > 0 else { return true }
        switch mode {
        case .betweenAccounts:
            return fromAccountID.isEmpty || toAccountID.isEmpty || fromAccountID == toAccountID
        case .payCreditCard:
            return fromAccountID.isEmpty || toAccountID.isEmpty || fromAccountID == toAccountID
        case .otherTransfer:
            return fromAccountID.isEmpty || otherRecipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppleTheme.bgCanvas.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // 3-Way Mode Segmented Control
                        Picker("Transfer Mode", selection: $mode) {
                            ForEach(TransferMode.allCases) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        
                        // Hero Icon & Title
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(mode == .payCreditCard ? AppleTheme.accentGreen : AppleTheme.accentBlue)
                                    .frame(width: 52, height: 52)
                                Image(systemName: mode.icon)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            
                            Text(mode.rawValue)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text(subtitleForMode(mode))
                                .font(.system(size: 12))
                                .foregroundColor(AppleTheme.labelSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 30)
                        }
                        
                        // Hero Amount Card
                        VStack(spacing: 6) {
                            Text(mode == .payCreditCard ? "PAYMENT AMOUNT" : "TRANSFER AMOUNT")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppleTheme.labelSecondary)
                                .kerning(0.8)
                            
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("$")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(mode == .payCreditCard ? AppleTheme.accentGreen : AppleTheme.accentBlue)
                                TextField("0.00", text: $amountString)
                                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                                    .foregroundColor(.white)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            
                            // If Pay Credit Card: Quick Full Balance Pill
                            if mode == .payCreditCard, let card = targetCreditAccount {
                                let balance = card.balance
                                if balance > 0 {
                                    Button(action: {
                                        #if os(iOS)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        #endif
                                        amountString = String(format: "%.2f", balance)
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "bolt.fill")
                                                .font(.system(size: 11))
                                            Text("Pay Full Balance (\(formatCurrencyWithCommas(balance)))")
                                                .font(.system(size: 12, weight: .semibold))
                                        }
                                        .foregroundColor(AppleTheme.accentGreen)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(AppleTheme.accentGreen.opacity(0.15))
                                        .clipShape(Capsule())
                                    }
                                    .padding(.top, 4)
                                }
                            }
                        }
                        .padding(18)
                        .background(AppleTheme.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                                .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                        )
                        .padding(.horizontal, 20)
                        
                        // Selectors Card
                        VStack(spacing: 0) {
                            // From Account Row
                            HStack {
                                Text(mode == .payCreditCard ? "Pay From" : "From")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                Spacer()
                                Picker("From Account", selection: $fromAccountID) {
                                    if mode == .payCreditCard {
                                        ForEach(debitAccounts) { acc in
                                            Text("\(acc.name) (\(formatCurrencyWithCommas(acc.balance)))").tag(acc.id)
                                        }
                                        Text("Other (cash / external)").tag(externalSourceID)
                                    } else {
                                        ForEach(db.accounts) { acc in
                                            Text("\(acc.name) (\(formatCurrencyWithCommas(acc.balance)))").tag(acc.id)
                                        }
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .tint(AppleTheme.labelSecondary)
                            }
                            .padding()
                            
                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
                            
                            if mode == .payCreditCard && fromAccountID == externalSourceID {
                                HStack(spacing: 12) {
                                    Text("Paid By")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.white)
                                    TextField("Cash, friend, other bank… (optional)", text: $externalPayerName)
                                        .foregroundColor(.white)
                                        .font(.system(size: 14))
                                        .multilineTextAlignment(.trailing)
                                }
                                .padding()
                                
                                Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
                            }
                            
                            if mode == .betweenAccounts {
                                // To Account Row
                                HStack {
                                    Text("To")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Picker("To Account", selection: $toAccountID) {
                                        ForEach(db.accounts) { acc in
                                            Text("\(acc.name) (\(formatCurrencyWithCommas(acc.balance)))").tag(acc.id)
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    .tint(AppleTheme.labelSecondary)
                                }
                                .padding()
                                
                            } else if mode == .payCreditCard {
                                // Destination Credit Card Row
                                HStack {
                                    Text("Credit Card")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Picker("Credit Card", selection: $toAccountID) {
                                        ForEach(creditAccounts) { acc in
                                            Text("\(acc.name) (Owed: \(formatCurrencyWithCommas(acc.balance)))").tag(acc.id)
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    .tint(AppleTheme.accentGreen)
                                }
                                .padding()
                                
                            } else if mode == .otherTransfer {
                                // External Recipient Row
                                HStack(spacing: 12) {
                                    Text("Recipient")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    TextField("E-Transfer, Landlord, Payee...", text: $otherRecipient)
                                        .foregroundColor(.white)
                                        .font(.system(size: 15))
                                        .multilineTextAlignment(.trailing)
                                }
                                .padding()
                                
                                Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
                                
                                // Category Row
                                HStack {
                                    Text("Category")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Picker("Category", selection: $otherCategoryID) {
                                        ForEach(db.categories) { cat in
                                            Text(cat.name).tag(cat.id as Int?)
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    .tint(AppleTheme.labelSecondary)
                                }
                                .padding()
                                
                                Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
                                
                                // Optional Memo/Notes
                                HStack(spacing: 12) {
                                    Text("Notes")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    TextField("Optional memo or note", text: $otherNotes)
                                        .foregroundColor(.white)
                                        .font(.system(size: 14))
                                        .multilineTextAlignment(.trailing)
                                }
                                .padding()
                            }
                        }
                        .background(AppleTheme.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                                .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                        )
                        .padding(.horizontal, 20)
                        
                        // Recurring Transfer Card
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(isRecurring ? AppleTheme.accentBlue : AppleTheme.bgTertiary)
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "repeat")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(isRecurring ? .white : AppleTheme.labelSecondary)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode == .payCreditCard ? "Recurring Card Payment" : "Recurring Transfer")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white)
                                    Text(isRecurring ? "\(recurringFrequency.rawValue) schedule active" : "Mark as automatic or periodic transfer")
                                        .font(.system(size: 12))
                                        .foregroundColor(AppleTheme.labelSecondary)
                                }
                                
                                Spacer()
                                
                                Toggle("", isOn: $isRecurring)
                                    .labelsHidden()
                                    .tint(AppleTheme.accentBlue)
                            }
                            
                            if isRecurring {
                                Divider().background(Color.white.opacity(0.06))
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("FREQUENCY")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(AppleTheme.labelSecondary)
                                        .kerning(0.8)
                                    
                                    HStack(spacing: 6) {
                                        ForEach(RecurringFrequency.allCases) { freq in
                                            let isSel = recurringFrequency == freq
                                            Button(action: { recurringFrequency = freq }) {
                                                Text(freq.rawValue)
                                                    .font(.system(size: 11, weight: isSel ? .bold : .medium))
                                                    .foregroundColor(isSel ? .white : AppleTheme.labelSecondary)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 6)
                                                    .background(isSel ? AppleTheme.accentBlue : AppleTheme.bgTertiary)
                                                    .clipShape(Capsule())
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .background(AppleTheme.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                                .stroke(isRecurring ? AppleTheme.accentBlue.opacity(0.5) : AppleTheme.cardStrokeHairline, lineWidth: isRecurring ? 1 : 0.5)
                        )
                        .padding(.horizontal, 20)
                        
                        // Submit Button
                        Button(action: executeAction) {
                            Text(buttonTitleForMode(mode))
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(mode == .payCreditCard ? AppleTheme.accentGreen : AppleTheme.accentBlue)
                                .clipShape(RoundedRectangle(cornerRadius: AppleTheme.buttonCornerRadius, style: .continuous))
                                .shadow(color: (mode == .payCreditCard ? AppleTheme.accentGreen : AppleTheme.accentBlue).opacity(0.35), radius: 10, x: 0, y: 5)
                        }
                        .disabled(isActionDisabled)
                        .opacity(isActionDisabled ? 0.4 : 1.0)
                        .padding(.horizontal, 20)
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle(mode.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .foregroundColor(AppleTheme.accentBlue)
                }
            }
            .onAppear {
                mode = initialMode
                if mode == .payCreditCard {
                    if let target = initialTargetAccountID, !target.isEmpty {
                        toAccountID = target
                    } else if toAccountID.isEmpty || !creditAccounts.contains(where: { $0.id == toAccountID }) {
                        toAccountID = creditAccounts.first?.id ?? ""
                    }
                    if fromAccountID != externalSourceID && !debitAccounts.contains(where: { $0.id == fromAccountID }) {
                        fromAccountID = defaultPaymentSourceID
                    }
                } else {
                    setupInitialSelections()
                }
            }
            .onChange(of: mode) { _, newMode in
                adjustSelectionsForMode(newMode)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func subtitleForMode(_ mode: TransferMode) -> String {
        switch mode {
        case .betweenAccounts:
            return "Move funds seamlessly between your personal accounts"
        case .payCreditCard:
            return "Pay down credit card debt from a debit account, or from another source"
        case .otherTransfer:
            return "Send money to an external person, landlord, or e-transfer payee"
        }
    }
    
    private func buttonTitleForMode(_ mode: TransferMode) -> String {
        switch mode {
        case .betweenAccounts: return "Confirm Transfer"
        case .payCreditCard: return "Confirm Card Payment"
        case .otherTransfer: return "Send Transfer"
        }
    }
    
    private func setupInitialSelections() {
        if let target = initialTargetAccountID, !target.isEmpty {
            toAccountID = target
            if mode == .payCreditCard {
                fromAccountID = defaultPaymentSourceID
            } else if let firstAsset = assetAccounts.first(where: { $0.id != target }) {
                fromAccountID = firstAsset.id
            } else if let first = db.accounts.first(where: { $0.id != target }) {
                fromAccountID = first.id
            }
        } else {
            if mode == .payCreditCard {
                fromAccountID = defaultPaymentSourceID
            } else if let firstAsset = assetAccounts.first {
                fromAccountID = firstAsset.id
            } else if let first = db.accounts.first {
                fromAccountID = first.id
            }
            
            if mode == .payCreditCard {
                if let card = creditAccounts.first {
                    toAccountID = card.id
                }
            } else {
                if let second = db.accounts.first(where: { $0.id != fromAccountID }) {
                    toAccountID = second.id
                }
            }
        }
        
        if otherCategoryID == nil {
            otherCategoryID = db.getCategoryID(name: "Miscellaneous") ?? db.categories.first?.id
        }
    }
    
    private func adjustSelectionsForMode(_ newMode: TransferMode) {
        if newMode != .payCreditCard && fromAccountID == externalSourceID {
            fromAccountID = db.accounts.first(where: { $0.id != toAccountID })?.id ?? db.accounts.first?.id ?? ""
        }
        if newMode == .payCreditCard {
            if fromAccountID != externalSourceID && !debitAccounts.contains(where: { $0.id == fromAccountID }) {
                fromAccountID = defaultPaymentSourceID
            }
            if !creditAccounts.contains(where: { $0.id == toAccountID }) {
                if let card = creditAccounts.first {
                    toAccountID = card.id
                }
            }
        } else if newMode == .betweenAccounts {
            if fromAccountID == toAccountID {
                if let alt = db.accounts.first(where: { $0.id != fromAccountID }) {
                    toAccountID = alt.id
                }
            }
        }
    }
    
    private func executeAction() {
        guard let amount = Double(amountString), amount > 0 else { return }
        
        switch mode {
        case .betweenAccounts:
            guard fromAccountID != toAccountID else { return }
            db.transferFunds(
                fromId: fromAccountID,
                toId: toAccountID,
                amount: amount,
                isRecurring: isRecurring,
                recurringFrequency: isRecurring ? recurringFrequency.rawValue : nil
            )
            
        case .payCreditCard:
            guard !toAccountID.isEmpty else { return }
            if fromAccountID == externalSourceID {
                let payer = externalPayerName.trimmingCharacters(in: .whitespacesAndNewlines)
                db.recordExternalCardPayment(
                    toId: toAccountID,
                    amount: amount,
                    payer: payer.isEmpty ? nil : payer,
                    isRecurring: isRecurring,
                    recurringFrequency: isRecurring ? recurringFrequency.rawValue : nil
                )
            } else {
                guard fromAccountID != toAccountID else { return }
                db.transferFunds(
                    fromId: fromAccountID,
                    toId: toAccountID,
                    amount: amount,
                    notes: "Credit Card Payment",
                    isRecurring: isRecurring,
                    recurringFrequency: isRecurring ? recurringFrequency.rawValue : nil
                )
            }
            
        case .otherTransfer:
            guard !fromAccountID.isEmpty else { return }
            let recipient = otherRecipient.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !recipient.isEmpty else { return }
            let notesClean = otherNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            db.recordOtherTransfer(
                fromId: fromAccountID,
                amount: amount,
                recipient: recipient,
                categoryID: otherCategoryID,
                notes: notesClean.isEmpty ? nil : notesClean,
                isRecurring: isRecurring,
                recurringFrequency: isRecurring ? recurringFrequency.rawValue : nil
            )
        }
        
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        isPresented = false
    }
}

// MARK: - Shared Credit Card Rewards Form Section (Base Rate, Bonus Rate, Bonus Categories & Extra Tiers)
struct EditableBonusTierState: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var rateString: String = ""
    var selectedCategories: Set<String> = []
}

struct CardRewardsFormSectionView: View {
    let expenseCategories: [Category]
    @Binding var baseRateString: String
    @Binding var bonusRateString: String
    @Binding var selectedBonusCategories: Set<String>
    @Binding var extraBonusTiers: [EditableBonusTierState]
    
    private let basePresets = ["0.5", "1", "1.25", "1.5", "2"]
    private let bonusPresets = ["2", "3", "4", "5", "6"]
    
    private let gridColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppleTheme.accentYellow)
                Text("CARD REWARDS & BONUS CATEGORIES")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(AppleTheme.labelSecondary)
                    .kerning(0.8)
                Spacer()
            }
            .padding(.horizontal, 4)
            
            // 1. Base Rate (%) Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Base Rate (%)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Standard % earned on all everyday purchases")
                            .font(.system(size: 11))
                            .foregroundColor(AppleTheme.labelSecondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        TextField("1.0", text: $baseRateString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(width: 68)
                        Text("%")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(AppleTheme.accentBlue)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppleTheme.bgTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                
                // Quick Base Presets
                HStack(spacing: 6) {
                    Text("Quick:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppleTheme.labelTertiary)
                    ForEach(basePresets, id: \.self) { preset in
                        let isSelected = Double(baseRateString) != nil && Double(baseRateString) == Double(preset)
                        Button(action: {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            baseRateString = preset
                        }) {
                            Text("\(preset)%")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(isSelected ? .white : AppleTheme.labelSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(isSelected ? AppleTheme.accentBlue : AppleTheme.bgTertiary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .background(AppleTheme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                    .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
            )
            
            // 2. Primary Bonus Rate (%) & Bonus Categories Card
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bonus Rate (%)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Higher % earned on selected bonus categories")
                            .font(.system(size: 11))
                            .foregroundColor(AppleTheme.labelSecondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        TextField("4.0", text: $bonusRateString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(AppleTheme.accentGreen)
                            .frame(width: 68)
                        Text("%")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(AppleTheme.accentGreen)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppleTheme.bgTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                
                // Quick Bonus Presets
                HStack(spacing: 6) {
                    Text("Quick:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppleTheme.labelTertiary)
                    ForEach(bonusPresets, id: \.self) { preset in
                        let isSelected = Double(bonusRateString) != nil && Double(bonusRateString) == Double(preset)
                        Button(action: {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            bonusRateString = preset
                        }) {
                            Text("\(preset)%")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(isSelected ? .white : AppleTheme.labelSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(isSelected ? AppleTheme.accentGreen : AppleTheme.bgTertiary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Divider().background(Color.white.opacity(0.08))
                
                // Bonus Categories Multi-Select Grid
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("BONUS CATEGORIES")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppleTheme.labelSecondary)
                            .kerning(0.6)
                        Spacer()
                        Text("\(selectedBonusCategories.count) Selected")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(selectedBonusCategories.isEmpty ? AppleTheme.labelTertiary : AppleTheme.accentGreen)
                    }
                    
                    LazyVGrid(columns: gridColumns, spacing: 8) {
                        ForEach(expenseCategories) { cat in
                            let isSelected = selectedBonusCategories.contains(cat.name)
                            let style = CategoryStyle.style(for: cat.name)
                            
                            Button(action: {
                                #if os(iOS)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                                if isSelected {
                                    selectedBonusCategories.remove(cat.name)
                                } else {
                                    selectedBonusCategories.insert(cat.name)
                                }
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : style.icon)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(isSelected ? .white : style.color)
                                    
                                    Text(cat.name)
                                        .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                        .foregroundColor(isSelected ? .white : AppleTheme.labelPrimary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .padding(.horizontal, 6)
                                .background(isSelected ? style.color : AppleTheme.bgTertiary)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(isSelected ? Color.white.opacity(0.3) : Color.clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
            .background(AppleTheme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                    .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
            )
            
            // 3. Optional Additional Bonus Tiers (if a card has multiple bonus % rates)
            ForEach($extraBonusTiers) { $tier in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Additional Bonus Rate (%)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            TextField("2.0", text: $tier.rateString)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(AppleTheme.accentGreen)
                                .frame(width: 56)
                            Text("%")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(AppleTheme.accentGreen)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppleTheme.bgTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        
                        Button(action: {
                            extraBonusTiers.removeAll { $0.id == tier.id }
                        }) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 13))
                                .foregroundColor(AppleTheme.accentRed)
                                .padding(7)
                                .background(AppleTheme.bgTertiary)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    LazyVGrid(columns: gridColumns, spacing: 8) {
                        ForEach(expenseCategories) { cat in
                            let isSelected = tier.selectedCategories.contains(cat.name)
                            let style = CategoryStyle.style(for: cat.name)
                            
                            Button(action: {
                                if isSelected {
                                    tier.selectedCategories.remove(cat.name)
                                } else {
                                    tier.selectedCategories.insert(cat.name)
                                }
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : style.icon)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(isSelected ? .white : style.color)
                                    Text(cat.name)
                                        .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                        .foregroundColor(isSelected ? .white : AppleTheme.labelPrimary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 6)
                                .background(isSelected ? style.color : AppleTheme.bgTertiary)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
                .background(AppleTheme.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                        .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                )
            }
            
            // Button to add another bonus rate tier
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                extraBonusTiers.append(EditableBonusTierState())
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("Add Another Bonus Rate Tier (Optional)")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(AppleTheme.accentBlue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppleTheme.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppleTheme.accentBlue.opacity(0.35), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Edit / Rename Account Sheet
struct EditAccountSheetView: View {
    @ObservedObject var db: DatabaseManager
    let account: Account
    @Binding var isPresented: Bool
    
    @State private var name: String = ""
    @State private var institution: String = ""
    @State private var accountNumber: String = ""
    @State private var balanceString: String = ""
    @State private var accountType: AccountType = .debit
    @State private var selectedParentID: String = ""
    @State private var includeInNetWorth: Bool = true
    
    // Credit Card Rewards State
    @State private var baseRateString: String = ""
    @State private var bonusRateString: String = ""
    @State private var selectedBonusCategories: Set<String> = []
    @State private var extraBonusTiers: [EditableBonusTierState] = []
    
    private var expenseCategories: [Category] {
        db.categories.filter { !CategoryStyle.style(for: $0.name).isIncome }
    }
    
    private var validParents: [Account] {
        db.validParentCandidates(excluding: account.id)
    }
    
    private var isParentWithChildren: Bool {
        account.type == .debit && db.hasSubAccounts(account.id)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppleTheme.bgCanvas.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 0) {
                            HStack {
                                Text(accountType == .credit ? "Card Name" : "Account Name")
                                    .font(.system(size: 15))
                                    .foregroundColor(.white)
                                Spacer()
                                TextField(accountType == .credit ? "e.g. Amex Cobalt, CIBC Dividend" : "Account Name", text: $name)
                                    .multilineTextAlignment(.trailing)
                                    .foregroundColor(.white)
                            }
                            .padding()
                            
                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
                            
                            HStack {
                                Text("Institution")
                                    .font(.system(size: 15))
                                    .foregroundColor(.white)
                                Spacer()
                                TextField("e.g. CIBC, TD, Amex", text: $institution)
                                    .multilineTextAlignment(.trailing)
                                    .foregroundColor(AppleTheme.labelSecondary)
                            }
                            .padding()
                            
                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
                            
                            HStack {
                                Text("Card / Account Ending (Optional)")
                                    .font(.system(size: 15))
                                    .foregroundColor(.white)
                                Spacer()
                                TextField("e.g. 1234", text: $accountNumber)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .foregroundColor(AppleTheme.labelSecondary)
                            }
                            .padding()
                            
                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
                            
                            if isParentWithChildren {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Parent Total (Sum of Kids)")
                                            .font(.system(size: 15))
                                            .foregroundColor(.white)
                                        Spacer()
                                        Text(formatCurrencyWithCommas(db.effectiveBalance(for: account.id)))
                                            .font(.system(size: 15, weight: .bold, design: .rounded))
                                            .foregroundColor(AppleTheme.accentBlue)
                                    }
                                    Text("This parent debit account's balance automatically equals the sum of its included sub-accounts.")
                                        .font(.system(size: 11))
                                        .foregroundColor(AppleTheme.labelSecondary)
                                }
                                .padding()
                            } else {
                                HStack {
                                    Text("Current Balance")
                                        .font(.system(size: 15))
                                        .foregroundColor(.white)
                                    Spacer()
                                    TextField("0.00", text: $balanceString)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .foregroundColor(AppleTheme.labelSecondary)
                                }
                                .padding()
                            }
                            
                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
                            
                            HStack {
                                Text("Type")
                                    .font(.system(size: 15))
                                    .foregroundColor(.white)
                                Spacer()
                                Picker("Type", selection: $accountType) {
                                    ForEach(AccountType.allCases) { t in
                                        Text(t.rawValue).tag(t)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .tint(AppleTheme.labelSecondary)
                            }
                            .padding()
                            
                            // Parent Account Picker: ONLY FOR DEBIT ACCOUNTS
                            if accountType == .debit {
                                Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
                                
                                HStack {
                                    Text("Parent Account")
                                        .font(.system(size: 15))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Picker("Parent Account", selection: $selectedParentID) {
                                        Text("None (Top-Level Account)").tag("")
                                        ForEach(validParents) { candidate in
                                            Text(db.accountBreadcrumb(for: candidate.id)).tag(candidate.id)
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    .tint(AppleTheme.accentBlue)
                                }
                                .padding()
                                
                                Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
                                
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Include in Parent & Net Worth")
                                            .font(.system(size: 15))
                                            .foregroundColor(.white)
                                        Text("Turn off to exclude this balance from parent totals and Net Worth")
                                            .font(.system(size: 11))
                                            .foregroundColor(AppleTheme.labelSecondary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: $includeInNetWorth)
                                        .labelsHidden()
                                        .tint(AppleTheme.accentGreen)
                                }
                                .padding()
                            }
                        }
                        .background(AppleTheme.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                                .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        
                        // Credit Card Rewards Section when Type is Credit
                        if accountType == .credit {
                            CardRewardsFormSectionView(
                                expenseCategories: expenseCategories,
                                baseRateString: $baseRateString,
                                bonusRateString: $bonusRateString,
                                selectedBonusCategories: $selectedBonusCategories,
                                extraBonusTiers: $extraBonusTiers
                            )
                        }
                        
                        Button(action: saveChanges) {
                            Text(accountType == .credit ? "Save Credit Card Changes" : "Save Account Changes")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(AppleTheme.accentBlue)
                                .clipShape(RoundedRectangle(cornerRadius: AppleTheme.buttonCornerRadius, style: .continuous))
                                .shadow(color: AppleTheme.accentBlue.opacity(0.35), radius: 10, x: 0, y: 5)
                        }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1.0)
                        .padding(.horizontal, 20)
                        
                        Spacer(minLength: 30)
                    }
                }
            }
            .navigationTitle(accountType == .credit ? "Edit Credit Card" : "Rename / Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .foregroundColor(AppleTheme.accentBlue)
                }
            }
            .onAppear {
                name = account.name
                institution = account.institution
                accountNumber = account.accountNumber ?? ""
                balanceString = String(format: "%.2f", account.balance)
                accountType = account.type
                selectedParentID = account.parentID ?? ""
                includeInNetWorth = account.includeInNetWorth
                baseRateString = account.baseRate > 0 ? Account.formatRate(account.baseRate).replacingOccurrences(of: "%", with: "") : ""
                bonusRateString = account.bonusRate > 0 ? Account.formatRate(account.bonusRate).replacingOccurrences(of: "%", with: "") : ""
                selectedBonusCategories = Set(account.bonusCategories)
                extraBonusTiers = account.bonusTiers.map { tier in
                    EditableBonusTierState(
                        id: tier.id,
                        rateString: Account.formatRate(tier.rate).replacingOccurrences(of: "%", with: ""),
                        selectedCategories: Set(tier.categories)
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func saveChanges() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        
        let newBalance = isParentWithChildren ? account.balance : (Double(balanceString) ?? account.balance)
        let parentToSave = (accountType == .debit && !selectedParentID.isEmpty) ? selectedParentID : nil
        
        let parsedBaseRate = accountType == .credit ? (Double(baseRateString.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) ?? 0.0) : 0.0
        let parsedBonusRate = accountType == .credit ? (Double(bonusRateString.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) ?? 0.0) : 0.0
        let orderedBonusCats = accountType == .credit ? expenseCategories.map { $0.name }.filter { selectedBonusCategories.contains($0) } : []
        let parsedExtraTiers: [CardBonusTier] = accountType == .credit ? extraBonusTiers.compactMap { tierState in
            guard let r = Double(tierState.rateString.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)),
                  r > 0,
                  !tierState.selectedCategories.isEmpty else { return nil }
            let cats = expenseCategories.map { $0.name }.filter { tierState.selectedCategories.contains($0) }
            return CardBonusTier(id: tierState.id, rate: r, categories: cats)
        } : []
        
        db.updateAccount(
            id: account.id,
            name: trimmedName,
            type: accountType,
            balance: newBalance,
            institution: institution.trimmingCharacters(in: .whitespaces),
            parentID: parentToSave,
            includeInNetWorth: includeInNetWorth,
            accountNumber: accountNumber.trimmingCharacters(in: .whitespaces).isEmpty ? nil : accountNumber.trimmingCharacters(in: .whitespaces),
            baseRate: parsedBaseRate,
            bonusRate: parsedBonusRate,
            bonusCategories: orderedBonusCats,
            bonusTiers: parsedExtraTiers
        )
        
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        isPresented = false
    }
}

// MARK: - Add Account / Sub-Account / Credit Card Sheet
struct AddAccountSheetView: View {
    @ObservedObject var db: DatabaseManager
    @Binding var isPresented: Bool
    var initialParentID: String? = nil
    var initialAccountType: AccountType = .debit
    
    @State private var name = ""
    @State private var institution = ""
    @State private var accountNumber = ""
    @State private var balanceString = ""
    @State private var accountType: AccountType = .debit
    @State private var selectedParentID: String = ""
    @State private var includeInNetWorth: Bool = true
    
    // Credit Card Rewards State
    @State private var baseRateString: String = "1"
    @State private var bonusRateString: String = ""
    @State private var selectedBonusCategories: Set<String> = []
    @State private var extraBonusTiers: [EditableBonusTierState] = []
    
    private var expenseCategories: [Category] {
        db.categories.filter { !CategoryStyle.style(for: $0.name).isIncome }
    }
    
    private var isSubAccountMode: Bool {
        !selectedParentID.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppleTheme.bgCanvas.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Sub-account banner when creating under a parent
                        if !selectedParentID.isEmpty,
                           let parentAcc = db.accounts.first(where: { $0.id == selectedParentID }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(AppleTheme.accentBlue)
                                Text("Creating sub-account under **\(db.accountBreadcrumb(for: parentAcc.id))**")
                                    .font(.system(size: 13))
                                    .foregroundColor(AppleTheme.labelSecondary)
                                Spacer()
                            }
                            .padding(14)
                            .background(AppleTheme.accentBlue.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
                        }
                        
                        VStack(spacing: 0) {
                            HStack {
                                Text(accountType == .credit ? "Card Name" : "Account Name")
                                    .font(.system(size: 15))
                                    .foregroundColor(.white)
                                Spacer()
                                TextField(accountType == .credit ? "e.g. Amex Cobalt, Scotia Momentum" : "e.g. CIBC, Chequing, Grocery Fund", text: $name)
                                    .multilineTextAlignment(.trailing)
                                    .foregroundColor(.white)
                            }
                            .padding()
                            
                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
                            
                            HStack {
                                Text("Institution (Optional)")
                                    .font(.system(size: 15))
                                    .foregroundColor(.white)
                                Spacer()
                                TextField("e.g. CIBC, TD, Amex", text: $institution)
                                    .multilineTextAlignment(.trailing)
                                    .foregroundColor(AppleTheme.labelSecondary)
                            }
                            .padding()
                            
                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
                            
                            HStack {
                                Text("Card / Account Ending (Optional)")
                                    .font(.system(size: 15))
                                    .foregroundColor(.white)
                                Spacer()
                                TextField("e.g. 1234", text: $accountNumber)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .foregroundColor(AppleTheme.labelSecondary)
                            }
                            .padding()
                            
                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(accountType == .credit ? "Current Balance Owed (Optional)" : "Starting Balance (Optional)")
                                        .font(.system(size: 15))
                                        .foregroundColor(.white)
                                    Spacer()
                                    TextField("0.00", text: $balanceString)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .foregroundColor(AppleTheme.labelSecondary)
                                }
                                if accountType == .debit && selectedParentID.isEmpty {
                                    Text("Leave empty for parent accounts — their total will automatically equal the sum of their sub-accounts.")
                                        .font(.system(size: 11))
                                        .foregroundColor(AppleTheme.labelSecondary)
                                }
                            }
                            .padding()
                            
                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
                            
                            HStack {
                                Text("Type")
                                    .font(.system(size: 15))
                                    .foregroundColor(.white)
                                Spacer()
                                Picker("Type", selection: $accountType) {
                                    ForEach(AccountType.allCases) { t in
                                        Text(t.rawValue).tag(t)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .tint(AppleTheme.labelSecondary)
                                .disabled(isSubAccountMode)
                            }
                            .padding()
                            
                            // Parent Account Picker: ONLY FOR DEBIT ACCOUNTS
                            if accountType == .debit {
                                Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
                                
                                HStack {
                                    Text("Parent Account")
                                        .font(.system(size: 15))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Picker("Parent Account", selection: $selectedParentID) {
                                        Text("None (Top-Level Account)").tag("")
                                        ForEach(db.validParentCandidates()) { acc in
                                            Text(db.accountBreadcrumb(for: acc.id)).tag(acc.id)
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    .tint(AppleTheme.accentBlue)
                                }
                                .padding()
                                
                                Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
                                
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Include in Parent & Net Worth")
                                            .font(.system(size: 15))
                                            .foregroundColor(.white)
                                        Text("Turn off to exclude this balance from parent totals and Net Worth")
                                            .font(.system(size: 11))
                                            .foregroundColor(AppleTheme.labelSecondary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: $includeInNetWorth)
                                        .labelsHidden()
                                        .tint(AppleTheme.accentGreen)
                                }
                                .padding()
                            }
                        }
                        .background(AppleTheme.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                                .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, selectedParentID.isEmpty ? 10 : 0)
                        
                        // Credit Card Rewards Section when Type is Credit
                        if accountType == .credit {
                            CardRewardsFormSectionView(
                                expenseCategories: expenseCategories,
                                baseRateString: $baseRateString,
                                bonusRateString: $bonusRateString,
                                selectedBonusCategories: $selectedBonusCategories,
                                extraBonusTiers: $extraBonusTiers
                            )
                        }
                        
                        Button(action: saveAccount) {
                            Text(accountType == .credit ? "Add Credit Card" : (selectedParentID.isEmpty ? "Create Account" : "Create Sub-Account"))
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(AppleTheme.accentBlue)
                                .clipShape(RoundedRectangle(cornerRadius: AppleTheme.buttonCornerRadius, style: .continuous))
                                .shadow(color: AppleTheme.accentBlue.opacity(0.35), radius: 10, x: 0, y: 5)
                        }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1.0)
                        .padding(.horizontal, 20)
                        
                        Spacer(minLength: 30)
                    }
                }
            }
            .navigationTitle(accountType == .credit ? "New Credit Card" : (selectedParentID.isEmpty ? "New Account" : "New Sub-Account"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .foregroundColor(AppleTheme.accentBlue)
                }
            }
            .onAppear {
                accountType = initialAccountType
                selectedParentID = initialParentID ?? ""
                if let pid = initialParentID,
                   let parentAcc = db.accounts.first(where: { $0.id == pid }) {
                    institution = parentAcc.institution
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func saveAccount() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        let bal = Double(balanceString) ?? 0.0
        let parentToSave = (accountType == .debit && !selectedParentID.isEmpty) ? selectedParentID : nil
        
        let parsedBaseRate = accountType == .credit ? (Double(baseRateString.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) ?? 0.0) : 0.0
        let parsedBonusRate = accountType == .credit ? (Double(bonusRateString.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) ?? 0.0) : 0.0
        let orderedBonusCats = accountType == .credit ? expenseCategories.map { $0.name }.filter { selectedBonusCategories.contains($0) } : []
        let parsedExtraTiers: [CardBonusTier] = accountType == .credit ? extraBonusTiers.compactMap { tierState in
            guard let r = Double(tierState.rateString.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)),
                  r > 0,
                  !tierState.selectedCategories.isEmpty else { return nil }
            let cats = expenseCategories.map { $0.name }.filter { tierState.selectedCategories.contains($0) }
            return CardBonusTier(id: tierState.id, rate: r, categories: cats)
        } : []
        
        db.addAccount(
            name: trimmedName,
            type: accountType,
            balance: bal,
            institution: institution.trimmingCharacters(in: .whitespaces),
            icon: "",
            colorHex: "#0A84FF",
            parentID: parentToSave,
            includeInNetWorth: includeInNetWorth,
            accountNumber: accountNumber.trimmingCharacters(in: .whitespaces).isEmpty ? nil : accountNumber.trimmingCharacters(in: .whitespaces),
            baseRate: parsedBaseRate,
            bonusRate: parsedBonusRate,
            bonusCategories: orderedBonusCats,
            bonusTiers: parsedExtraTiers
        )
        
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        isPresented = false
    }
}

// MARK: - Insights Sheet View (Apple Health Style Bento Insights)
struct InsightsSheetView: View {
    @ObservedObject var db: DatabaseManager
    @Binding var isPresented: Bool
    
    private var monthlyExpense: Double {
        let calendar = Calendar.current
        let now = Date()
        let sum = db.transactions
            .filter { !$0.isIncome && $0.source != "transfer" && calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0.0) { $0 + $1.netExpenseImpact }
        return max(0.0, sum)
    }
    
    private var monthlyIncome: Double {
        let calendar = Calendar.current
        let now = Date()
        return db.transactions
            .filter { $0.isIncome && $0.source != "transfer" && calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + abs($1.amount) }
    }
    
    private var largestExpense: Transaction? {
        let calendar = Calendar.current
        let now = Date()
        return db.transactions
            .filter { !$0.isIncome && $0.source != "transfer" && !$0.isRefund && calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            .max { $0.amount < $1.amount }
    }
    
    private var savingsRate: Double {
        guard monthlyIncome > 0 else { return 0 }
        let saved = monthlyIncome - monthlyExpense
        return max(0, (saved / monthlyIncome) * 100)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppleTheme.bgCanvas.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        
                        // Header
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(AppleTheme.accentOrange)
                                    .frame(width: 44, height: 44)
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Monthly Insights")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Intelligent trends based on your spending history")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppleTheme.labelSecondary)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        
                        // Bento Insight 1: Savings Rate
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("SAVINGS RATE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(AppleTheme.labelSecondary)
                                    .kerning(0.8)
                                Spacer()
                                Image(systemName: "arrow.up.heart.fill")
                                    .foregroundColor(savingsRate >= 20 ? AppleTheme.accentGreen : AppleTheme.accentOrange)
                            }
                            
                            Text("\(Int(savingsRate))%")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(savingsRate >= 20 ? AppleTheme.accentGreen : AppleTheme.accentOrange)
                            
                            Text(savingsRate >= 20 ? "Excellent! You are saving over 20% of your earnings." : "Try reducing discretionary spending to boost your monthly savings.")
                                .font(.system(size: 13))
                                .foregroundColor(AppleTheme.labelSecondary)
                        }
                        .padding(18)
                        .background(AppleTheme.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                                .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                        )
                        .padding(.horizontal, 20)
                        
                        // Bento Insight 2: Largest Expense
                        if let largest = largestExpense {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("LARGEST EXPENSE")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(AppleTheme.labelSecondary)
                                        .kerning(0.8)
                                    Spacer()
                                    Image(systemName: "flame.fill")
                                        .foregroundColor(AppleTheme.accentRed)
                                }
                                
                                Text(formatCurrencyWithCommas(largest.amount))
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                
                                Text("\(largest.merchant) on \(largest.formattedDate)")
                                    .font(.system(size: 13))
                                    .foregroundColor(AppleTheme.labelSecondary)
                            }
                            .padding(18)
                            .background(AppleTheme.bgCard)
                            .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                                    .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                            )
                            .padding(.horizontal, 20)
                        }
                        
                        // Bento Insight 3: Recurring Commitments
                        if !db.recurringPayments.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("RECURRING COMMITMENTS")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(AppleTheme.labelSecondary)
                                        .kerning(0.8)
                                    Spacer()
                                    Image(systemName: "repeat.circle.fill")
                                        .foregroundColor(AppleTheme.accentBlue)
                                }
                                
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(formatCurrencyWithCommas(db.totalMonthlyRecurringSpend))
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                    Text("/ month")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(AppleTheme.labelSecondary)
                                }
                                
                                VStack(spacing: 8) {
                                    ForEach(db.recurringPayments.prefix(6)) { item in
                                        HStack {
                                            Text(item.name)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                            Spacer()
                                            Text(item.frequency.rawValue)
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(AppleTheme.accentBlue)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(AppleTheme.accentBlue.opacity(0.18))
                                                .clipShape(Capsule())
                                            Text(formatCurrencyWithCommas(item.amount))
                                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                                .foregroundColor(.white)
                                        }
                                    }
                                }
                            }
                            .padding(18)
                            .background(AppleTheme.bgCard)
                            .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                                    .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                            )
                            .padding(.horizontal, 20)
                        }
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                        .foregroundColor(AppleTheme.accentBlue)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
