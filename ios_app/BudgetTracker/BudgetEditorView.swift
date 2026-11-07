import SwiftUI

struct BudgetEditorView: View {
    @Binding var isPresented: Bool
    @ObservedObject var db = DatabaseManager.shared
    @AppStorage("selectedCurrencySymbol") private var currencySymbol: String = "$"
    
    @State private var newCategoryName = ""
    @State private var editedLimits: [Int: String] = [:]
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppleTheme.bgCanvas.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        
                        // New Category Input Card
                        VStack(alignment: .leading, spacing: 12) {
                            Text("NEW CATEGORY")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(AppleTheme.labelSecondary)
                                .padding(.horizontal, 4)
                            
                            HStack(spacing: 12) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(AppleTheme.accentBlue)
                                
                                TextField("e.g. Subscriptions, Hobbies", text: $newCategoryName)
                                    .foregroundColor(.white)
                                    .font(.system(.body, design: .default))
                                
                                Button(action: addCategory) {
                                    Text("Add")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty ? AppleTheme.bgTertiary : AppleTheme.accentBlue)
                                        .clipShape(Capsule())
                                }
                                .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                            .padding(14)
                            .background(AppleTheme.bgCard)
                            .clipShape(RoundedRectangle(cornerRadius: AppleTheme.compactCornerRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppleTheme.compactCornerRadius, style: .continuous)
                                    .stroke(AppleTheme.cardStroke, lineWidth: 0.5)
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        
                        // Monthly Budget Thresholds
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("MONTHLY LIMITS")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(AppleTheme.labelSecondary)
                                Spacer()
                                Text("\(db.budgets.count) Categories")
                                    .font(.caption)
                                    .foregroundColor(AppleTheme.labelTertiary)
                            }
                            .padding(.horizontal, 24)
                            
                            VStack(spacing: 0) {
                                ForEach(Array(db.budgets.enumerated()), id: \.element.id) { index, budget in
                                    let style = CategoryStyle.style(for: budget.categoryName)
                                    
                                    HStack(spacing: 14) {
                                        ZStack {
                                            Circle()
                                                .fill(style.color)
                                                .frame(width: 34, height: 34)
                                            Image(systemName: style.icon)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(.white)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(budget.categoryName)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(.white)
                                            
                                            Text(style.isIncome ? "Income Category" : "Expense Category")
                                                .font(.system(size: 11))
                                                .foregroundColor(AppleTheme.labelSecondary)
                                        }
                                        
                                        Spacer()
                                        
                                        HStack(spacing: 6) {
                                            Text(currencySymbol)
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundColor(AppleTheme.labelSecondary)
                                            
                                            TextField("0", text: Binding(
                                                get: {
                                                    if let val = editedLimits[budget.categoryID] {
                                                        return val
                                                    }
                                                    return budget.monthlyLimit > 0 ? String(format: "%.0f", budget.monthlyLimit) : ""
                                                },
                                                set: { newValue in
                                                    let filtered = newValue.filter { "0123456789.".contains($0) }
                                                    editedLimits[budget.categoryID] = filtered
                                                }
                                            ))
                                            .keyboardType(.decimalPad)
                                            .multilineTextAlignment(.trailing)
                                            .font(.system(size: 16, weight: .bold, design: .rounded))
                                            .foregroundColor(.white)
                                            .frame(width: 80)
                                            .padding(.vertical, 8)
                                            .padding(.horizontal, 10)
                                            .background(AppleTheme.bgTertiary)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    
                                    if index < db.budgets.count - 1 {
                                        Divider()
                                            .background(Color.white.opacity(0.06))
                                            .padding(.leading, 64)
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
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("Manage Budgets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .foregroundColor(AppleTheme.accentBlue)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveBudgets()
                        isPresented = false
                    }
                    .font(.headline)
                    .foregroundColor(AppleTheme.accentGreen)
                }
            }
            .onAppear {
                for budget in db.budgets {
                    editedLimits[budget.categoryID] = budget.monthlyLimit > 0 ? String(format: "%.0f", budget.monthlyLimit) : ""
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func addCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        _ = db.addCategory(name: name)
        newCategoryName = ""
        
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            for budget in db.budgets {
                if editedLimits[budget.categoryID] == nil {
                    editedLimits[budget.categoryID] = ""
                }
            }
        }
    }
    
    private func saveBudgets() {
        var parsedLimits: [Int: Double] = [:]
        for (categoryID, limitStr) in editedLimits {
            parsedLimits[categoryID] = Double(limitStr) ?? 0.0
        }
        db.updateBudgets(parsedLimits)
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}
