import SwiftUI

struct ManualEntryView: View {
    @Binding var isPresented: Bool
    var editingTransaction: Transaction? = nil
    @ObservedObject var db = DatabaseManager.shared
    @AppStorage("selectedCurrencySymbol") private var currencySymbol: String = "$"
    
    @State private var merchant = ""
    @State private var subCategory = ""
    @State private var notes = ""
    @State private var amountString = ""
    @State private var selectedCategoryID: Int? = nil
    @State private var selectedAccountID: String? = nil
    @State private var date = Date()
    @State private var transactionType: TransactionType = .expense
    @State private var isRecurring: Bool = false
    @State private var recurringFrequency: RecurringFrequency = .monthly
    @State private var showingManageSubCategories = false
    @State private var showingRefundSheet = false
    @State private var renamingSubCategoryTarget: String? = nil
    @State private var renamingSubCategoryText = ""
    
    enum TransactionType: String, CaseIterable, Identifiable {
        case expense = "Expense"
        case income = "Income"
        case refund = "Refund"
        var id: String { rawValue }
    }
    
    let presets = [5.0, 10.0, 25.0, 50.0, 100.0]
    
    private var selectedCategoryName: String? {
        db.categories.first(where: { $0.id == selectedCategoryID })?.name
    }
    
    private var suggestedSubCategories: [String] {
        db.allKnownSubCategories(for: selectedCategoryName)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppleTheme.bgCanvas.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        // Transaction Type Picker (Apple HIG Segmented Control)
                        Picker("Transaction Type", selection: $transactionType) {
                            ForEach(TransactionType.allCases) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        
                        // Hero Amount Card (Apple Cash Style)
                        VStack(spacing: 8) {
                            Text(transactionType == .expense ? "OUTFLOW AMOUNT" : (transactionType == .refund ? "REFUND INFLOW AMOUNT" : "INFLOW AMOUNT"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppleTheme.labelSecondary)
                                .kerning(0.8)
                            
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(transactionType == .expense ? "-\(currencySymbol)" : "+\(currencySymbol)")
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundColor(transactionType == .expense ? AppleTheme.accentRed : AppleTheme.accentGreen)
                                
                                TextField("0.00", text: $amountString)
                                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                                    .foregroundColor(.white)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            
                            // Quick Preset Pills
                            HStack(spacing: 8) {
                                ForEach(presets, id: \.self) { p in
                                    Button(action: {
                                        #if os(iOS)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        #endif
                                        let current = Double(amountString) ?? 0.0
                                        amountString = String(format: "%.0f", current + p)
                                    }) {
                                        Text("+\(currencySymbol)\(Int(p))")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(AppleTheme.labelPrimary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(AppleTheme.bgTertiary)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(20)
                        .background(AppleTheme.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                                .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                        )
                        .padding(.horizontal, 20)
                        
                        // Details Bento Group
                        detailsBentoCard
                        
                        // Recurring Payment / Membership Card
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
                                    Text(transactionType == .income ? "Recurring Income" : "Recurring Expense / Membership")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white)
                                    Text(isRecurring ? "\(recurringFrequency.rawValue) schedule active" : (transactionType == .income ? "Track as recurring salary, deposit, or dividend" : "Track as recurring subscription, bill, or membership"))
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
                                            let isSelected = recurringFrequency == freq
                                            Button(action: {
                                                #if os(iOS)
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                #endif
                                                recurringFrequency = freq
                                            }) {
                                                Text(freq.rawValue)
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundColor(isSelected ? .white : AppleTheme.labelSecondary)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 6)
                                                    .background(isSelected ? AppleTheme.accentBlue : AppleTheme.bgTertiary)
                                                    .clipShape(Capsule())
                                            }
                                        }
                                    }
                                }
                                .padding(.top, 2)
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
                        
                        // Notes Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NOTES & WHY YOU MADE THIS TRANSACTION")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(AppleTheme.labelSecondary)
                                .padding(.horizontal, 24)
                            
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "note.text")
                                    .font(.system(size: 16))
                                    .foregroundColor(AppleTheme.accentOrange)
                                    .frame(width: 24)
                                    .padding(.top, 2)
                                
                                TextField("Add notes, context, who it was with, or receipt memo...", text: $notes, axis: .vertical)
                                    .lineLimit(2...5)
                                    .foregroundColor(.white)
                                    .font(.system(size: 14))
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
                        
                        // Category Selector Grid
                        VStack(alignment: .leading, spacing: 10) {
                            Text("CATEGORY")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(AppleTheme.labelSecondary)
                                .padding(.horizontal, 24)
                            
                            let cols = [
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)
                            ]
                            
                            LazyVGrid(columns: cols, spacing: 10) {
                                ForEach(db.categories) { cat in
                                    let isSelected = selectedCategoryID == cat.id
                                    let style = CategoryStyle.style(for: cat.name)
                                    
                                    Button(action: {
                                        #if os(iOS)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        #endif
                                        selectedCategoryID = cat.id
                                    }) {
                                        VStack(spacing: 6) {
                                            ZStack {
                                                Circle()
                                                    .fill(isSelected ? style.color : style.color.opacity(0.25))
                                                    .frame(width: 38, height: 38)
                                                Image(systemName: style.icon)
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundColor(isSelected ? .white : style.color)
                                            }
                                            
                                            Text(cat.name)
                                                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                                .foregroundColor(isSelected ? .white : AppleTheme.labelSecondary)
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(AppleTheme.bgCard)
                                        .clipShape(RoundedRectangle(cornerRadius: AppleTheme.compactCornerRadius, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: AppleTheme.compactCornerRadius, style: .continuous)
                                                .stroke(isSelected ? style.color : AppleTheme.cardStrokeHairline, lineWidth: isSelected ? 1.5 : 0.5)
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        // Submit Button
                        Button(action: saveTransaction) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.headline)
                                Text(editingTransaction != nil ? "Update Transaction" : "Save Transaction")
                                    .font(.headline)
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [AppleTheme.accentBlue, AppleTheme.accentIndigo],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: AppleTheme.buttonCornerRadius, style: .continuous))
                            .shadow(color: AppleTheme.accentBlue.opacity(0.35), radius: 10, x: 0, y: 5)
                        }
                        .disabled(merchant.trimmingCharacters(in: .whitespaces).isEmpty || amountString.isEmpty)
                        .opacity(merchant.trimmingCharacters(in: .whitespaces).isEmpty || amountString.isEmpty ? 0.5 : 1.0)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        
                        // Refund Action / Status (if editing existing expense)
                        if let tx = editingTransaction, !tx.isRefund, tx.amount > 0 {
                            let remaining = db.remainingRefundableAmount(for: tx.uuid)
                            if remaining > 0.001 {
                                Button {
                                    showingRefundSheet = true
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.uturn.backward.circle.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                        Text("Issue Refund (\(formatCurrencyWithCommas(remaining)) remaining)")
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                    .foregroundColor(AppleTheme.accentGreen)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(AppleTheme.accentGreen.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: AppleTheme.buttonCornerRadius, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: AppleTheme.buttonCornerRadius, style: .continuous)
                                            .stroke(AppleTheme.accentGreen.opacity(0.35), lineWidth: 1)
                                    )
                                }
                                .padding(.horizontal, 20)
                            } else if db.isFullyRefunded(uuid: tx.uuid) {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(AppleTheme.accentGreen)
                                    Text("This transaction is fully refunded (\(formatCurrencyWithCommas(db.refundedAmount(for: tx.uuid))))")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(AppleTheme.labelSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .background(AppleTheme.bgCard)
                                .clipShape(RoundedRectangle(cornerRadius: AppleTheme.buttonCornerRadius, style: .continuous))
                                .padding(.horizontal, 20)
                            }
                        }
                        
                        // Delete Button (if editing existing transaction)
                        if let tx = editingTransaction {
                            Button(role: .destructive) {
                                #if os(iOS)
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                #endif
                                db.deleteTransaction(uuid: tx.uuid)
                                isPresented = false
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "trash.fill")
                                    Text("Delete Transaction")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(AppleTheme.accentRed)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppleTheme.accentRed.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: AppleTheme.buttonCornerRadius, style: .continuous))
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle(editingTransaction != nil ? "Edit Transaction" : "New Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .foregroundColor(AppleTheme.accentBlue)
                }
                if let tx = editingTransaction {
                    ToolbarItem(placement: .destructiveAction) {
                        Button(role: .destructive) {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            #endif
                            db.deleteTransaction(uuid: tx.uuid)
                            isPresented = false
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(AppleTheme.accentRed)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingManageSubCategories) {
                ManageSubCategoriesSheetView(
                    db: db,
                    initialCategoryName: selectedCategoryName ?? "Grocery",
                    selectedSubCategory: $merchant
                )
            }
            .sheet(isPresented: $showingRefundSheet) {
                if let tx = editingTransaction {
                    RefundTransactionSheetView(db: db, originalTransaction: tx)
                }
            }
            .alert(
                "Rename Tag",
                isPresented: Binding(
                    get: { renamingSubCategoryTarget != nil },
                    set: { if !$0 { renamingSubCategoryTarget = nil } }
                )
            ) {
                TextField("Tag Name", text: $renamingSubCategoryText)
                Button("Save") {
                    if let old = renamingSubCategoryTarget {
                        let trimmed = renamingSubCategoryText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            if merchant.caseInsensitiveCompare(old) == .orderedSame {
                                merchant = trimmed
                            }
                            db.renameMerchant(oldName: old, newName: trimmed, for: selectedCategoryName)
                        }
                    }
                    renamingSubCategoryTarget = nil
                }
                Button("Cancel", role: .cancel) {
                    renamingSubCategoryTarget = nil
                }
            }
            .onAppear {
                if let tx = editingTransaction {
                    merchant = tx.merchant
                    subCategory = tx.subCategory ?? ""
                    notes = tx.notes ?? ""
                    amountString = String(format: "%.2f", tx.displayAmount)
                    selectedCategoryID = tx.categoryID
                    selectedAccountID = tx.accountID
                    date = tx.date
                    if tx.isRefund {
                        transactionType = .refund
                    } else {
                        transactionType = tx.isIncome ? .income : .expense
                    }
                    isRecurring = tx.isRecurring
                    if let rf = tx.recurringFrequency, let freq = RecurringFrequency(rawValue: rf) {
                        recurringFrequency = freq
                    }
                } else {
                    if selectedCategoryID == nil, let first = db.categories.first {
                        selectedCategoryID = first.id
                    }
                    if selectedAccountID == nil, let firstAcc = db.accounts.first {
                        selectedAccountID = firstAcc.id
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Subviews for Form
    
    @ViewBuilder
    private var detailsBentoCard: some View {
        VStack(spacing: 0) {
            merchantRow
            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
            accountRow
            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
            dateRow
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
    private var merchantRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AppleTheme.accentIndigo)
                    .frame(width: 24)
                
                TextField("Tag name", text: $merchant)
                    .foregroundColor(.white)
                    .font(.system(size: 15))
                
                Button(action: { showingManageSubCategories = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Edit")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(AppleTheme.accentBlue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppleTheme.accentBlue.opacity(0.15))
                    .clipShape(Capsule())
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(suggestedSubCategories, id: \.self) { suggestion in
                        let active = merchant.caseInsensitiveCompare(suggestion) == .orderedSame
                        Button(action: {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            merchant = active ? "" : suggestion
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 9))
                                Text(suggestion)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(active ? .white : AppleTheme.labelSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(active ? AppleTheme.accentBlue : AppleTheme.bgTertiary)
                            .clipShape(Capsule())
                        }
                        .contextMenu {
                            Button {
                                renamingSubCategoryTarget = suggestion
                                renamingSubCategoryText = suggestion
                            } label: {
                                Label("Rename Tag", systemImage: "pencil")
                            }
                            
                            Button(role: .destructive) {
                                if active { merchant = "" }
                                db.deleteMerchant(name: suggestion, for: selectedCategoryName)
                            } label: {
                                Label("Delete Tag", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.leading, 36)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    @ViewBuilder
    private var accountRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 16))
                .foregroundColor(AppleTheme.accentBlue)
                .frame(width: 24)
            
            Text("Account")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
            
            Spacer()
            
            Picker("Account", selection: $selectedAccountID) {
                Text("Select Account").tag(nil as String?)
                ForEach(db.accounts) { acc in
                    Text("\(db.accountBreadcrumb(for: acc.id)) (\(formatCurrencyWithCommas(db.effectiveBalance(for: acc.id))))").tag(acc.id as String?)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .tint(AppleTheme.labelSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    @ViewBuilder
    private var dateRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 16))
                .foregroundColor(AppleTheme.accentOrange)
                .frame(width: 24)
            
            Text("Date")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
            
            Spacer()
            
            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(CompactDatePickerStyle())
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    private func saveTransaction() {
        guard let amountVal = Double(amountString) else { return }
        let merchantName = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !merchantName.isEmpty else { return }
        
        let finalAmount = transactionType == .expense ? amountVal : -amountVal
        let targetSource = transactionType == .refund ? "refund" : (editingTransaction?.source ?? "manual")
        let cleanSub = subCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let tx = editingTransaction {
            db.updateTransaction(
                uuid: tx.uuid,
                date: date,
                amount: finalAmount,
                categoryID: selectedCategoryID,
                merchant: merchantName,
                subCategory: cleanSub.isEmpty ? nil : cleanSub,
                notes: cleanNotes.isEmpty ? nil : cleanNotes,
                accountID: selectedAccountID,
                isRecurring: isRecurring,
                recurringFrequency: isRecurring ? recurringFrequency.rawValue : nil,
                source: targetSource
            )
        } else {
            db.addTransaction(
                date: date,
                amount: finalAmount,
                categoryID: selectedCategoryID,
                merchant: merchantName,
                subCategory: cleanSub.isEmpty ? nil : cleanSub,
                notes: cleanNotes.isEmpty ? nil : cleanNotes,
                source: transactionType == .refund ? "refund" : "manual",
                accountID: selectedAccountID,
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

// MARK: - Manage Sub-Categories Sheet (Add, Rename/Edit, Delete Sub-Categories)
struct ManageSubCategoriesSheetView: View {
    @ObservedObject var db: DatabaseManager
    var initialCategoryName: String
    @Binding var selectedSubCategory: String
    
    @Environment(\.dismiss) private var dismiss
    @State private var categoryName: String = ""
    @State private var newSubCategoryName: String = ""
    @State private var renamingTarget: String? = nil
    @State private var renamingText: String = ""
    
    private var currentSubCategories: [String] {
        db.allKnownSubCategories(for: categoryName.isEmpty ? initialCategoryName : categoryName)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppleTheme.bgCanvas.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        // Category Picker Header
                        HStack {
                            Text("Category")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                            Spacer()
                            Picker("Category", selection: $categoryName) {
                                ForEach(db.categories) { cat in
                                    Text(cat.name).tag(cat.name)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(AppleTheme.accentBlue)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(AppleTheme.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        
                        // Add New Tag Row
                        HStack(spacing: 10) {
                            Image(systemName: "tag.fill")
                                .foregroundColor(AppleTheme.accentIndigo)
                                .font(.system(size: 15))
                            
                            TextField("Add new tag...", text: $newSubCategoryName)
                                .foregroundColor(.white)
                                .font(.system(size: 15))
                                .onSubmit(addNewSubCategory)
                            
                            Button(action: addNewSubCategory) {
                                Text("Add")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(newSubCategoryName.trimmingCharacters(in: .whitespaces).isEmpty ? AppleTheme.bgTertiary : AppleTheme.accentBlue)
                                    .clipShape(Capsule())
                            }
                            .disabled(newSubCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(AppleTheme.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                        )
                        .padding(.horizontal, 20)
                        
                        // Existing Tags List
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SAVED TAGS (\(currentSubCategories.count))")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(AppleTheme.labelSecondary)
                                .kerning(0.8)
                                .padding(.horizontal, 24)
                            
                            if currentSubCategories.isEmpty {
                                Text("No saved tags for this category yet. Add one above.")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppleTheme.labelSecondary)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 8)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(Array(currentSubCategories.enumerated()), id: \.element) { index, item in
                                        HStack(spacing: 12) {
                                            Button(action: {
                                                selectedSubCategory = item
                                                dismiss()
                                            }) {
                                                HStack(spacing: 10) {
                                                    Image(systemName: selectedSubCategory.caseInsensitiveCompare(item) == .orderedSame ? "checkmark.circle.fill" : "tag.fill")
                                                        .foregroundColor(selectedSubCategory.caseInsensitiveCompare(item) == .orderedSame ? AppleTheme.accentBlue : AppleTheme.labelSecondary)
                                                        .font(.system(size: 15))
                                                    
                                                    Text(item)
                                                        .font(.system(size: 15, weight: .medium))
                                                        .foregroundColor(.white)
                                                    
                                                    Spacer()
                                                }
                                            }
                                            .buttonStyle(.plain)
                                            
                                            // Rename Button
                                            Button(action: {
                                                renamingTarget = item
                                                renamingText = item
                                            }) {
                                                Image(systemName: "pencil")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(AppleTheme.accentBlue)
                                                    .padding(8)
                                                    .background(AppleTheme.bgTertiary)
                                                    .clipShape(Circle())
                                            }
                                            .buttonStyle(.plain)
                                            
                                            // Delete Button
                                            Button(action: {
                                                if selectedSubCategory.caseInsensitiveCompare(item) == .orderedSame {
                                                    selectedSubCategory = ""
                                                }
                                                let targetCat = categoryName.isEmpty ? initialCategoryName : categoryName
                                                db.deleteMerchant(name: item, for: targetCat)
                                            }) {
                                                Image(systemName: "trash.fill")
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundColor(AppleTheme.accentRed)
                                                    .padding(8)
                                                    .background(AppleTheme.bgTertiary)
                                                    .clipShape(Circle())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        
                                        if index < currentSubCategories.count - 1 {
                                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 42)
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
                        
                        Spacer(minLength: 30)
                    }
                }
            }
            .navigationTitle("Edit Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppleTheme.accentBlue)
                }
            }
            .onAppear {
                categoryName = initialCategoryName
            }
            .alert(
                "Rename Tag",
                isPresented: Binding(
                    get: { renamingTarget != nil },
                    set: { if !$0 { renamingTarget = nil } }
                )
            ) {
                TextField("Tag Name", text: $renamingText)
                Button("Save") {
                    if let old = renamingTarget {
                        let trimmed = renamingText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let targetCat = categoryName.isEmpty ? initialCategoryName : categoryName
                        if !trimmed.isEmpty {
                            if selectedSubCategory.caseInsensitiveCompare(old) == .orderedSame {
                                selectedSubCategory = trimmed
                            }
                            db.renameMerchant(oldName: old, newName: trimmed, for: targetCat)
                        }
                    }
                    renamingTarget = nil
                }
                Button("Cancel", role: .cancel) {
                    renamingTarget = nil
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func addNewSubCategory() {
        let trimmed = newSubCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let targetCat = categoryName.isEmpty ? initialCategoryName : categoryName
        db.addSubCategory(name: trimmed, for: targetCat)
        selectedSubCategory = trimmed
        newSubCategoryName = ""
    }
}

// MARK: - Refund Transaction Sheet View
struct RefundTransactionSheetView: View {
    @ObservedObject var db: DatabaseManager
    let originalTransaction: Transaction
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedCurrencySymbol") private var currencySymbol: String = "$"
    
    @State private var isFullRefund: Bool = true
    @State private var customRefundAmount: String = ""
    @State private var selectedAccountID: String? = nil
    @State private var refundDate: Date = Date()
    @State private var notes: String = ""
    
    private var maxRefundable: Double {
        db.remainingRefundableAmount(for: originalTransaction.uuid)
    }
    
    private var effectiveRefundAmount: Double {
        if isFullRefund {
            return maxRefundable
        } else {
            let parsed = Double(customRefundAmount) ?? 0.0
            return max(0.0, min(parsed, maxRefundable))
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppleTheme.bgCanvas.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Original Transaction Summary Card
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ORIGINAL PURCHASE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppleTheme.labelSecondary)
                                .kerning(0.8)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(originalTransaction.merchant)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                    Text(originalTransaction.date, style: .date)
                                        .font(.system(size: 12))
                                        .foregroundColor(AppleTheme.labelSecondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(formatCurrencyWithCommas(originalTransaction.amount))
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                    Text("Refundable: \(formatCurrencyWithCommas(maxRefundable))")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(AppleTheme.accentGreen)
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
                        .padding(.horizontal, 20)
                        
                        // Refund Mode Selector (Full vs Partial)
                        Picker("Refund Type", selection: $isFullRefund) {
                            Text("Full (\(formatCurrencyWithCommas(maxRefundable)))").tag(true)
                            Text("Partial").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 20)
                        
                        // Amount input if partial
                        if !isFullRefund {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("REFUND AMOUNT")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(AppleTheme.labelSecondary)
                                    .kerning(0.8)
                                
                                HStack {
                                    Text(currencySymbol)
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(AppleTheme.accentGreen)
                                    TextField("0.00", text: $customRefundAmount)
                                        .keyboardType(.decimalPad)
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                
                                if let amt = Double(customRefundAmount), amt > maxRefundable {
                                    Text("Exceeds maximum refundable amount of \(formatCurrencyWithCommas(maxRefundable))")
                                        .font(.system(size: 11))
                                        .foregroundColor(AppleTheme.accentRed)
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
                        
                        // Details: Account & Date
                        VStack(spacing: 0) {
                            // Target Account
                            HStack(spacing: 12) {
                                Image(systemName: "creditcard.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(AppleTheme.accentBlue)
                                    .frame(width: 24)
                                
                                Text("Refund To")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                Picker("Refund To", selection: $selectedAccountID) {
                                    ForEach(db.accounts) { acc in
                                        Text("\(db.accountBreadcrumb(for: acc.id))").tag(acc.id as String?)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .tint(AppleTheme.labelSecondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            
                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
                            
                            // Date
                            HStack(spacing: 12) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 16))
                                    .foregroundColor(AppleTheme.accentOrange)
                                    .frame(width: 24)
                                
                                Text("Date")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                DatePicker("", selection: $refundDate, displayedComponents: .date)
                                    .datePickerStyle(CompactDatePickerStyle())
                                    .labelsHidden()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            
                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
                            
                            // Notes
                            HStack(spacing: 12) {
                                Image(systemName: "note.text")
                                    .font(.system(size: 16))
                                    .foregroundColor(AppleTheme.labelSecondary)
                                    .frame(width: 24)
                                
                                TextField("Reason / Notes (optional)", text: $notes)
                                    .foregroundColor(.white)
                                    .font(.system(size: 15))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .background(AppleTheme.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                                .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                        )
                        .padding(.horizontal, 20)
                        
                        // Confirm Refund Button
                        Button(action: executeRefund) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                Text("Record Refund of \(formatCurrencyWithCommas(effectiveRefundAmount))")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(effectiveRefundAmount > 0 ? AppleTheme.accentGreen : AppleTheme.bgTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(effectiveRefundAmount <= 0)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Record Refund")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppleTheme.accentBlue)
                }
            }
            .onAppear {
                selectedAccountID = originalTransaction.accountID ?? db.accounts.first?.id
                customRefundAmount = String(format: "%.2f", maxRefundable)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func executeRefund() {
        guard effectiveRefundAmount > 0 else { return }
        db.recordRefund(
            originalTransaction: originalTransaction,
            refundAmount: effectiveRefundAmount,
            accountID: selectedAccountID,
            date: refundDate,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        )
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        dismiss()
    }
}
