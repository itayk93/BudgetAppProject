# Swift & SwiftUI Code Editing Guidelines

### *Strict rules for AI-generated code in the BudgetApp project*

---

## 📌 Purpose

This document defines **strict and safe rules** for AI-generated code in the BudgetApp codebase.
Its goal is to prevent recurring issues such as:

* `Generic parameter 'C' could not be inferred`
* `Binding<C>` vs plain array confusion
* `dynamicMember` / `EnvironmentObject` wrapper issues
* Immutable struct mutation errors
* Optional vs non-optional mismatches
* Incorrect async closure handling
* Over-refactoring or modifying architecture unintentionally

Follow these rules **exactly** whenever generating or modifying Swift/SwiftUI code.

---

# 1. Minimal Changes Only

### ✅ Allowed

* Small localized fixes
* Adding the minimal missing piece to make the code compile
* Updating a single function or view

### ❌ Not allowed

* Refactoring entire files
* Introducing completely new services / view-models / models
* Changing function signatures unless explicitly instructed
* Changing property types (`Double` → `Double?`, `Bool` → `Binding<Bool>`, etc.)
* Changing architecture (MVVM, service layout, environment objects)

---

# 2. Immutable Structs (`let`) Must Not Be Mutated

If a struct has `let` properties (e.g., `CategoryOrder.monthlyTarget`):

### ❌ Forbidden

```swift
categoryOrderMap[name]?.monthlyTarget = newTarget
```

### ✅ Required

Recreate the struct and replace it:

```swift
if let old = categoryOrderMap[name] {
    let updated = CategoryOrder(
        categoryName: old.categoryName,
        displayOrder: old.displayOrder,
        weeklyDisplay: old.weeklyDisplay,
        monthlyTarget: newTarget,
        sharedCategory: old.sharedCategory
    )
    categoryOrderMap[name] = updated
}
```

---

# 3. ForEach Rules (Critical)

### ALWAYS use this form for a plain array:

```swift
ForEach(items, id: \.id) { item in
    ...
}
```

### NEVER:

❌ Use `ForEach(items)` without `id:`
❌ Pass `$items` unless the array itself is editable
❌ Allow Swift to infer the `ForEach` generic (it will choose the wrong initializer)

This prevents:

```
Generic parameter 'C' could not be inferred  
Cannot convert value of type '[Item]' to expected argument type 'Binding<C>'
```

---

# 4. EnvironmentObject Rules

### In the root view:

```swift
 @EnvironmentObject var vm: CashFlowDashboardViewModel
```

### Inside helper functions, nested views, etc.

❌ Do NOT redeclare ` @EnvironmentObject`
❌ Do NOT use `$vm`
❌ Do NOT access `vm` from static functions or helpers unless injection is explicit

### Instead:

✔ Pass derived values explicitly:

```swift
itemView(for: item, isCurrentMonth: vm.isCurrentMonth)
```

This prevents:

```
Referencing subscript 'dynamicMember' requires wrapper 'EnvironmentObject<...>.Wrapper'
Cannot convert Binding<Subject> to Bool
```

---

# 5. Optional vs Non-Optional Values

Do NOT modify function signatures.

Example:

If the ViewModel expects:

```swift
func updateTarget(for name: String, newTarget: Double)
```

and you have `Double?`, then:

### ❌ Do NOT:

* Change the function signature
* Change the property type
* Make it optional inside the ViewModel

### ✅ Do:

```swift
await vm.updateTarget(for: name, newTarget: newTarget ?? 0)
```

---

# 6. Async Closure Rules

If a view expects:

```swift
var onSuggest: (() async -> Double?)?
```

You must pass:

```swift
onSuggest: {
    await vm.suggestTarget(for: category.name)
}
```

### ❌ Not allowed:

* `Task { ... }.value`
* Returning `nil` because async doesn’t fit
* Changing the closure type

---

# 7. Avoid Over-Refactoring

AI must not:

* Rewrite entire view hierarchies
* Convert to new architecture
* Create new abstractions
* Extract dozens of helpers without instruction
* Replace MVVM with a new pattern
* Rename existing files, views, or models

Unless explicitly asked.

---

# 8. ViewBuilder Safety

When using `switch item` inside `ForEach`, always wrap with a ViewBuilder:

```swift
 @ViewBuilder
func itemView(for item: CashFlowDashboardViewModel.Item) -> some View {
    switch item {
    case .income: incomeSection
    case .savings: savingsSection
    case .nonCashflow: nonCashflowSection
    case .sharedGroup(let group):
        GroupSectionCard(
            group: group,
            accent: groupAccentColor(for: group.title),
            currency: vm.selectedCashFlow?.currency ?? "ILS"
        )
    case .category(let cat):
        CategorySummaryCard(
            category: cat,
            currency: vm.selectedCashFlow?.currency ?? "ILS",
            isWeekly: vm.isCurrentMonth ? vm.isWeeklyCategory(cat.name) : false,
            onEdit: vm.isCurrentMonth ? {
                editingTargetValue = cat.target
                selectedCategoryForEdit = cat
                showingEditTargetSheet = true
            } : nil,
            onEditBudget: vm.isCurrentMonth ? {
                editingBudgetValue = cat.target
                selectedCategoryForBudgetEdit = cat
                showingEditBudgetSheet = true
            } : nil
        )
    }
}
```

This avoids view-builder inference errors.

---

# 9. Rules for Adding New Methods

Allowed:

* Adding small missing methods the view expects
* Methods directly interacting with existing services
* Methods matching existing architectural patterns

Forbidden:

* Adding entire new services
* Adding new global helpers
* Changing async → sync or sync → async
* Modifying model structures unless explicitly required

---

# 10. Error-First Strategy

If any change introduces:

* Generic inference issues
* EnvironmentObject wrapper issues
* Optional mismatch
* Type mismatch
* DynamicMemberLookup errors

→ The AI **must revert the risky change** and try a simpler, smaller correction.

---

# 11. Formatting & Consistency

* Use the same naming conventions already in the project
* Do not rename variables unless asked
* Follow existing indentation and line length
* Do not reorder properties for no reason

---

## ✅ TL;DR Summary for System Prompt

> **Make minimal, safe edits. Do not change function signatures or types unless explicitly requested. Always use
> `ForEach(items, id: \.id)`. Do not mutate immutable structs—create updated copies. Never use `$vm` or add new
> ` @EnvironmentObject`. Pass values rather than accessing the view model inside helper functions. Do not refactor
> architecture. Preserve all existing patterns. Fix optionals with `??` instead of signature changes. Use async
> closures correctly. If your change introduces binding/generic/dynamicMember errors—revert and simplify.**