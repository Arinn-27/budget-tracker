import SwiftUI
import UniformTypeIdentifiers

public struct StatementImportSheet: View {
    @ObservedObject var db = DatabaseManager.shared
    @Binding var isPresented: Bool
    
    @State private var showingFileImporter = false
    @State private var reconciliationPlan: StatementReconciliationPlan? = nil
    @State private var selectedAccountID: String = ""
    @State private var errorMessage: String? = nil
    @State private var importResultSummary: (inserted: Int, merged: Int, skipped: Int)? = nil
    @State private var selectedFilter: FilterMode = .all
    @State private var isProcessingFile = false
    @State private var displayLimit: Int = 60
    @State private var forceReimport: Bool = false
    
    public enum FilterMode: String, CaseIterable, Identifiable {
        case all = "All"
        case newOnly = "New"
        case manualMatches = "Manual Match"
        case duplicates = "Skipped"
        public var id: String { rawValue }
    }
    
    public init(db: DatabaseManager = .shared, isPresented: Binding<Bool>) {
        self.db = db
        self._isPresented = isPresented
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppleTheme.bgCanvas.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        headerBanner
                        
                        if let err = errorMessage {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(AppleTheme.accentRed)
                                Text(err)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(14)
                            .appleCard(cornerRadius: 14)
                            .padding(.horizontal, 20)
                        }
                        
                        if isProcessingFile {
                            VStack(spacing: 14) {
                                ProgressView()
                                    .tint(AppleTheme.accentBlue)
                                    .scaleEffect(1.2)
                                Text("Processing & Reconciling Statement…")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(28)
                            .appleCard()
                            .padding(.horizontal, 20)
                        } else if let result = importResultSummary {
                            completedSummaryCard(result)
                        } else if let plan = reconciliationPlan {
                            statementSummaryCard(plan)
                            
                            if plan.isStatementAlreadyImported && !forceReimport {
                                fastExitAlreadyImportedCard(plan)
                            } else {
                                accountPickerCard
                                commitButton(plan)
                                filterBar(plan)
                                transactionPreviewList(plan)
                            }
                        } else {
                            emptyPickerPromptCard
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Import Statement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        isPresented = false
                    }
                    .foregroundColor(AppleTheme.labelSecondary)
                }
                if reconciliationPlan != nil && importResultSummary == nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Choose File") {
                            showingFileImporter = true
                        }
                        .foregroundColor(AppleTheme.accentBlue)
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.json, .commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Subviews
    
    private var headerBanner: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppleTheme.accentBlue.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: "doc.badge.gearshape.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(AppleTheme.accentBlue)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text("Hash Reconciliation Pipeline")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Text("SHA-256 duplicate skip + ±3d manual entry merge")
                    .font(.system(size: 12))
                    .foregroundColor(AppleTheme.labelSecondary)
            }
            Spacer()
        }
        .padding(16)
        .appleCard()
        .padding(.horizontal, 20)
    }
    
    private var emptyPickerPromptCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.up.doc.on.clipboard")
                .font(.system(size: 38))
                .foregroundColor(AppleTheme.accentBlue)
                .padding(.top, 8)
            
            Text("Select Statement Bundle")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
            
            Text("Import a statement_bundle.json or .csv generated by scripts/process_statement.py on your Mac.")
                .font(.system(size: 13))
                .foregroundColor(AppleTheme.labelSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            
            Button(action: { showingFileImporter = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                    Text("Choose .json or .csv File")
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppleTheme.accentBlue)
                .clipShape(RoundedRectangle(cornerRadius: AppleTheme.buttonCornerRadius, style: .continuous))
            }
            .padding(.top, 4)
        }
        .padding(22)
        .appleCard()
        .padding(.horizontal, 20)
    }
    
    private func statementSummaryCard(_ plan: StatementReconciliationPlan) -> some View {
        let b = plan.bundle
        let headerAccountLabel: String = {
            if let acc = b.account, !acc.isEmpty {
                return acc.uppercased()
            }
            if let inst = b.institution, let hint = b.accountHint, !hint.isEmpty {
                return "\(inst.uppercased()) •••• \(hint)"
            }
            return (b.institution ?? "STATEMENT").uppercased()
        }()
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: "creditcard.fill")
                            .font(.system(size: 10))
                            .foregroundColor(AppleTheme.accentBlue)
                        Text(headerAccountLabel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppleTheme.labelSecondary)
                            .kerning(0.8)
                    }
                    
                    if let ps = b.periodStart, let pe = b.periodEnd {
                        Text("\(ps) → \(pe)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Text("\(b.transactions.count) Transactions")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                Spacer()
                
                HStack(spacing: 5) {
                    Image(systemName: b.checksumVerified ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                    Text(b.checksumVerified ? "Checksum Verified" : "Unverified")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(b.checksumVerified ? AppleTheme.accentGreen : AppleTheme.accentOrange)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background((b.checksumVerified ? AppleTheme.accentGreen : AppleTheme.accentOrange).opacity(0.15))
                .clipShape(Capsule())
            }
            
            Divider().background(Color.white.opacity(0.08))
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DEBITS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppleTheme.labelSecondary)
                    Text(formatCurrencyWithCommas(b.totalDebits))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(AppleTheme.accentRed)
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("CREDITS / PAYMENTS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppleTheme.labelSecondary)
                    Text(formatCurrencyWithCommas(b.totalCredits))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(AppleTheme.accentGreen)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("ROWS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppleTheme.labelSecondary)
                    Text("\(b.transactions.count)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            
            if !b.statementHash.isEmpty {
                Text("SHA-256: \(String(b.statementHash.prefix(24)))…")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(AppleTheme.labelTertiary)
            }
        }
        .padding(16)
        .appleCard()
        .padding(.horizontal, 20)
    }
    
    private func fastExitAlreadyImportedCard(_ plan: StatementReconciliationPlan) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(AppleTheme.accentGreen)
            
            Text("Statement Already Reconciled")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
            
            Text("Fast-exit check passed: All \(plan.bundle.transactions.count) transaction hashes match your statement history.")
                .font(.system(size: 13))
                .foregroundColor(AppleTheme.labelSecondary)
                .multilineTextAlignment(.center)
            
            Button(action: { isPresented = false }) {
                Text("Done")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppleTheme.accentGreen)
                    .clipShape(RoundedRectangle(cornerRadius: AppleTheme.buttonCornerRadius, style: .continuous))
            }
            .padding(.top, 4)
            
            Button(action: {
                for i in plan.items.indices {
                    reconciliationPlan?.items[i].isSelected = true
                }
                forceReimport = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Re-Import / Review Anyway")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppleTheme.accentBlue)
                .padding(.vertical, 4)
            }
        }
        .padding(20)
        .appleCard()
        .padding(.horizontal, 20)
    }
    
    private var accountPickerCard: some View {
        HStack {
            Label("Paid From Account", systemImage: "creditcard.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Picker("Paid From Account", selection: $selectedAccountID) {
                Text("Auto-Match per Transaction").tag("")
                ForEach(db.accounts) { acc in
                    let numSuffix = (acc.accountNumber ?? "").isEmpty ? "" : " •••• \(acc.accountNumber ?? "")"
                    Text("\(acc.name)\(numSuffix) (\(formatCurrencyWithCommas(acc.balance)))").tag(acc.id)
                }
            }
            .pickerStyle(.menu)
            .tint(AppleTheme.accentBlue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .appleCard(cornerRadius: 14)
        .padding(.horizontal, 20)
    }
    
    private func filterBar(_ plan: StatementReconciliationPlan) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterPill(.all, title: "All (\(plan.items.count))")
                filterPill(.newOnly, title: "New (\(plan.newCount))")
                filterPill(.manualMatches, title: "Manual Match (\(plan.mergedCount))")
                filterPill(.duplicates, title: "Duplicates (\(plan.duplicateCount))")
            }
            .padding(.horizontal, 20)
        }
    }
    
    private func filterPill(_ mode: FilterMode, title: String) -> some View {
        let active = selectedFilter == mode
        return Button(action: {
            selectedFilter = mode
            displayLimit = 60
        }) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(active ? .white : AppleTheme.labelSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(active ? AppleTheme.accentBlue : AppleTheme.bgCard)
                .clipShape(Capsule())
        }
    }
    
    private func transactionPreviewList(_ plan: StatementReconciliationPlan) -> some View {
        let indices = plan.items.indices.filter { idx in
            let item = plan.items[idx]
            switch selectedFilter {
            case .all: return true
            case .newOnly: return item.matchType == .newInsert
            case .manualMatches: return item.matchType == .fuzzyManualMerge
            case .duplicates: return item.matchType == .exactHashDuplicate
            }
        }
        let visibleIndices = Array(indices.prefix(displayLimit))
        let remainingCount = max(0, indices.count - visibleIndices.count)
        let selectedAccountObj = db.accounts.first(where: { $0.id == selectedAccountID })
        
        return LazyVStack(spacing: 0) {
            ForEach(visibleIndices, id: \.self) { idx in
                let preview = plan.items[idx]
                let rowAccountLabel: String? = {
                    if let selAcc = selectedAccountObj {
                        let num = selAcc.accountNumber ?? ""
                        return num.isEmpty ? selAcc.name : "\(selAcc.name) •••• \(num)"
                    }
                    if let itemAcc = preview.item.account, !itemAcc.isEmpty {
                        return itemAcc
                    }
                    if let bundleAcc = plan.bundle.account, !bundleAcc.isEmpty {
                        return bundleAcc
                    }
                    return nil
                }()
                HStack(spacing: 12) {
                    Button(action: {
                        if preview.matchType != .exactHashDuplicate {
                            reconciliationPlan?.items[idx].isSelected.toggle()
                        }
                    }) {
                        Image(systemName: preview.isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundColor(
                                preview.matchType == .exactHashDuplicate
                                    ? AppleTheme.labelTertiary
                                    : (preview.isSelected ? AppleTheme.accentBlue : AppleTheme.labelSecondary)
                            )
                    }
                    .disabled(preview.matchType == .exactHashDuplicate)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(preview.item.merchant)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            statusBadge(preview.matchType, isTransfer: preview.item.isTransfer)
                        }
                        
                        HStack(spacing: 6) {
                            Text(preview.item.date)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(AppleTheme.labelSecondary)
                            
                            if let accLbl = rowAccountLabel {
                                Text("• \(accLbl)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(AppleTheme.labelSecondary)
                                    .lineLimit(1)
                            }
                            
                            if preview.matchType == .fuzzyManualMerge, let mMerch = preview.matchedMerchant {
                                Text("• Merges w/ '\(mMerch)'")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(AppleTheme.accentOrange)
                                    .lineLimit(1)
                            } else {
                                Menu {
                                    ForEach(db.categories) { cat in
                                        Button(cat.name) {
                                            reconciliationPlan?.items[idx].item.category = cat.name
                                        }
                                    }
                                } label: {
                                    Text("• \(preview.item.category)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(AppleTheme.accentBlue)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Text(formatCurrencyWithCommas(preview.item.amount, showSign: true))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(preview.item.amount < 0 ? AppleTheme.accentGreen : .white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                
                if idx != visibleIndices.last || remainingCount > 0 {
                    Divider().background(Color.white.opacity(0.06)).padding(.leading, 44)
                }
            }
            
            if remainingCount > 0 {
                Button(action: {
                    displayLimit += 100
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 14))
                        Text("Show More (\(remainingCount) remaining)")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(AppleTheme.accentBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                }
            }
        }
        .background(AppleTheme.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppleTheme.cardCornerRadius, style: .continuous)
                .stroke(AppleTheme.cardStrokeHairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 20)
    }
    
    private func statusBadge(_ type: ReconciliationMatchType, isTransfer: Bool) -> some View {
        let label = isTransfer && type == .newInsert ? "Transfer" : type.rawValue
        let color: Color = {
            switch type {
            case .newInsert: return isTransfer ? AppleTheme.accentIndigo : AppleTheme.accentGreen
            case .fuzzyManualMerge: return AppleTheme.accentOrange
            case .exactHashDuplicate: return AppleTheme.labelSecondary
            }
        }()
        return Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.16))
            .clipShape(Capsule())
    }
    
    private func commitButton(_ plan: StatementReconciliationPlan) -> some View {
        let selectedCount = plan.items.filter { $0.isSelected && $0.matchType != .exactHashDuplicate }.count
        return Button(action: {
            guard let currentPlan = reconciliationPlan else { return }
            let targetAcc = selectedAccountID.isEmpty ? nil : selectedAccountID
            let res = db.commitReconciliationPlan(currentPlan, accountID: targetAcc)
            importResultSummary = res
        }) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.doc.fill")
                Text("Reconcile & Import (\(selectedCount) items)")
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(selectedCount > 0 ? AppleTheme.accentBlue : AppleTheme.bgTertiary)
            .clipShape(RoundedRectangle(cornerRadius: AppleTheme.buttonCornerRadius, style: .continuous))
        }
        .disabled(selectedCount == 0)
        .padding(.horizontal, 20)
    }
    
    private func completedSummaryCard(_ result: (inserted: Int, merged: Int, skipped: Int)) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundColor(AppleTheme.accentGreen)
            
            Text("Statement Reconciled")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            HStack(spacing: 20) {
                statPill(label: "Inserted", count: result.inserted, color: AppleTheme.accentGreen)
                statPill(label: "Merged Manual", count: result.merged, color: AppleTheme.accentOrange)
                statPill(label: "Skipped Hash", count: result.skipped, color: AppleTheme.labelSecondary)
            }
            
            Button(action: { isPresented = false }) {
                Text("Done")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppleTheme.accentBlue)
                    .clipShape(RoundedRectangle(cornerRadius: AppleTheme.buttonCornerRadius, style: .continuous))
            }
            .padding(.top, 6)
        }
        .padding(22)
        .appleCard()
        .padding(.horizontal, 20)
    }
    
    private func statPill(label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppleTheme.labelSecondary)
        }
    }
    
    // MARK: - File Handling
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        errorMessage = nil
        importResultSummary = nil
        selectedFilter = .all
        displayLimit = 60
        forceReimport = false
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            isProcessingFile = true
            Task.detached(priority: .userInitiated) {
                do {
                    let bundle = try db.parseStatementFile(from: url)
                    await MainActor.run {
                        self.autoSelectMatchingAccount(for: bundle)
                    }
                    let targetAcc = await MainActor.run {
                        self.selectedAccountID.isEmpty ? nil : self.selectedAccountID
                    }
                    let plan = db.prepareReconciliationPlan(bundle: bundle, targetAccountID: targetAcc)
                    await MainActor.run {
                        self.reconciliationPlan = plan
                        self.isProcessingFile = false
                    }
                } catch {
                    await MainActor.run {
                        self.errorMessage = "Failed to parse statement file: \(error.localizedDescription)"
                        self.isProcessingFile = false
                    }
                }
            }
        case .failure(let error):
            self.errorMessage = error.localizedDescription
        }
    }
    
    private func autoSelectMatchingAccount(for bundle: ImportedStatementBundle) {
        let distinctAccounts = Set(bundle.transactions.compactMap { $0.account }.filter { !$0.isEmpty })
        if distinctAccounts.count > 1 {
            // Multi-account bundle: let each transaction auto-match its own payment account
            selectedAccountID = ""
            return
        }
        if let matched = db.resolveMatchingAccount(
            accountLabel: bundle.account,
            institution: bundle.institution,
            accountHint: bundle.accountHint
        ) {
            selectedAccountID = matched.id
            return
        }
        selectedAccountID = ""
    }
}

