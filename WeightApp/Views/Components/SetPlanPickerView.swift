import SwiftUI
import SwiftData

struct SetPlanCatalogView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<SetPlan> { !$0.deleted })
    private var allPlans: [SetPlan]

    @Query private var userPropertiesItems: [UserProperties]
    @Query private var entitlementRecords: [EntitlementGrant]

    @State private var showNewPlanAlert = false
    @State private var newPlanName = ""
    @State private var showDeleteConfirmation = false
    @State private var planToDelete: SetPlan?
    @State private var showUpsell = false
    @State private var shouldScrollToBottom = false

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)
    private static let effortLevels = ["easy", "moderate", "hard", "redline", "pr"]

    private var isPremium: Bool {
        if FreeOverride.isEnabled { return false }
        return PremiumOverride.isEnabled || EntitlementGrant.isPremium(entitlementRecords)
    }

    private var setPlansUpsellPage: Int {
        let index = SubscriptionConfig.premiumFeatures.firstIndex { $0.title == "Set Plan Catalog" } ?? 3
        return index + 1
    }

    private var userProperties: UserProperties {
        if let props = userPropertiesItems.first { return props }
        let props = UserProperties()
        modelContext.insert(props)
        return props
    }

    private var builtInPlans: [SetPlan] {
        allPlans.filter { !$0.isCustom }.sorted { $0.createdAt < $1.createdAt }
    }

    private var customPlans: [SetPlan] {
        allPlans.filter { $0.isCustom }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.14), Color(white: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Set Plan Catalog")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    Spacer()

                    Button {
                        if isPremium {
                            newPlanName = ""
                            showNewPlanAlert = true
                        } else {
                            showUpsell = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isPremium ? "plus" : "lock.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text("New")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(Color.appAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.appAccent.opacity(0.15))
                        .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

                // Effort level legend
                HStack(spacing: 8) {
                    ForEach(Self.effortLevels, id: \.self) { level in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(SequenceSquareView.color(for: level))
                                .frame(width: 8, height: 8)
                            Text(level == "pr" ? "e1RM ↑" : level.capitalized)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Color(white: 0.12))

                ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 16) {
                        // Built-in section — free presets
                        if !builtInPlans.isEmpty {
                            sectionHeader("Presets")

                            ForEach(builtInPlans.filter { SetPlan.freePresetIds.contains($0.id) }) { plan in
                                planCard(plan: plan, isEditable: false)
                            }

                            // Premium presets
                            let premiumPresets = builtInPlans.filter { !SetPlan.freePresetIds.contains($0.id) }
                            if !premiumPresets.isEmpty {
                                sectionHeader("Premium Set Plans")

                                if isPremium {
                                    ForEach(premiumPresets) { plan in
                                        planCard(plan: plan, isEditable: false)
                                    }
                                } else {
                                    // Show just a few cards as preview behind the lock
                                    VStack(spacing: 8) {
                                        ForEach(premiumPresets.prefix(3)) { plan in
                                            planCard(plan: plan, isEditable: false)
                                        }
                                    }
                                    .premiumLocked(
                                        title: "Unlock Premium Set Plans",
                                        subtitle: "Access premium set plans and create your own",
                                        blurRadius: 6,
                                        showUpsell: $showUpsell
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }

                        // User-created plans section
                        if !customPlans.isEmpty {
                            sectionHeader("Your Plans")

                            ForEach(customPlans) { plan in
                                planCard(plan: plan, isEditable: true)
                            }
                        }

                        // None option
                        noneCard()
                            .id("catalogBottom")
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .padding(.top, 8)
                }
                .onChange(of: shouldScrollToBottom) { _, scroll in
                    if scroll {
                        shouldScrollToBottom = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation {
                                scrollProxy.scrollTo("catalogBottom", anchor: .bottom)
                            }
                        }
                    }
                }
                } // ScrollViewReader
            }
        }
        .fullScreenCover(isPresented: $showUpsell) {
            UpsellView(initialPage: setPlansUpsellPage) { _ in showUpsell = false }
        }
        .alert("New Plan", isPresented: $showNewPlanAlert) {
            TextField("Name", text: $newPlanName)
            Button("Cancel", role: .cancel) { }
            Button("Create") {
                let trimmed = newPlanName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                let plan = SetPlan(
                    name: trimmed,
                    effortSequence: [],
                    isCustom: true
                )
                modelContext.insert(plan)
                try? modelContext.save()
                shouldScrollToBottom = true
                Task {
                    await SyncService.shared.syncSetPlan(plan)
                }
            }
        } message: {
            Text("Name your custom plan")
        }
        .alert("Delete Plan?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                planToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let plan = planToDelete {
                    deletePlan(plan)
                }
                planToDelete = nil
            }
        } message: {
            if let plan = planToDelete {
                Text("This will permanently delete \"\(plan.name)\".")
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func planCard(plan: SetPlan, isEditable: Bool) -> some View {
        let isActive = userProperties.activeSetPlanId == plan.id

        VStack(alignment: .leading, spacing: 10) {
            // Title row with selection
            HStack(spacing: 12) {
                Button {
                    hapticFeedback.impactOccurred()
                    userProperties.activeSetPlanId = plan.id
                    try? modelContext.save()
                    Task { await SyncService.shared.updateActiveSetPlan(plan.id) }
                } label: {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isActive ? Color.appAccent : .white.opacity(0.3))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(plan.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        if !plan.isCustom {
                            Text("PRESET")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.4))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(4)
                        }
                    }

                    if let desc = plan.planDescription {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                Spacer()

                if isEditable {
                    Button {
                        hapticFeedback.impactOccurred()
                        planToDelete = plan
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.3))
                            .padding(8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Effort squares
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(plan.effortSequence.enumerated()), id: \.offset) { index, effort in
                        if isEditable {
                            SequenceSquareView(effort: effort)
                                .onTapGesture {
                                    let levels = Self.effortLevels
                                    let next = levels[((levels.firstIndex(of: effort) ?? 0) + 1) % levels.count]
                                    plan.effortSequence[index] = next
                                    saveAndSyncPlan(plan)
                                    hapticFeedback.impactOccurred()
                                }
                                .onLongPressGesture {
                                    guard plan.effortSequence.count > 1 else { return }
                                    plan.effortSequence.remove(at: index)
                                    saveAndSyncPlan(plan)
                                    hapticFeedback.impactOccurred()
                                }
                        } else {
                            SequenceSquareView(effort: effort)
                        }
                    }

                    if isEditable && plan.effortSequence.count < 20 {
                        Button {
                            plan.effortSequence.append("easy")
                            saveAndSyncPlan(plan)
                            hapticFeedback.impactOccurred()
                        } label: {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(white: 0.15))
                                .frame(width: 42, height: 42)
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.5))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 2)
            }
            .frame(height: 46)

            if isEditable {
                Text("Tap to cycle effort level. Long-press to remove.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color(white: 0.18), Color(white: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.appAccent : Color.white.opacity(0.1), lineWidth: isActive ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            hapticFeedback.impactOccurred()
            userProperties.activeSetPlanId = plan.id
            try? modelContext.save()
            Task { await SyncService.shared.updateActiveSetPlan(plan.id) }
        }
    }

    @ViewBuilder
    private func noneCard() -> some View {
        let isActive = userProperties.activeSetPlanId == nil

        HStack(spacing: 12) {
            Button {
                hapticFeedback.impactOccurred()
                userProperties.activeSetPlanId = nil
                try? modelContext.save()
                Task { await SyncService.shared.updateActiveSetPlan(nil) }
            } label: {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isActive ? Color.appAccent : .white.opacity(0.3))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text("None")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text("No set plan — freestyle your sets")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color(white: 0.18), Color(white: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.appAccent : Color.white.opacity(0.1), lineWidth: isActive ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            hapticFeedback.impactOccurred()
            userProperties.activeSetPlanId = nil
            try? modelContext.save()
            Task { await SyncService.shared.updateActiveSetPlan(nil) }
        }
    }

    private func saveAndSyncPlan(_ plan: SetPlan) {
        try? modelContext.save()
        Task { await SyncService.shared.syncSetPlan(plan) }
    }

    private func deletePlan(_ plan: SetPlan) {
        plan.deleted = true
        if userProperties.activeSetPlanId == plan.id {
            userProperties.activeSetPlanId = SetPlan.standardId
        }
        try? modelContext.save()
        Task {
            await SyncService.shared.deleteSetPlan(plan.id)
            if userProperties.activeSetPlanId == SetPlan.standardId {
                await SyncService.shared.updateActiveSetPlan(SetPlan.standardId)
            }
        }
    }
}
