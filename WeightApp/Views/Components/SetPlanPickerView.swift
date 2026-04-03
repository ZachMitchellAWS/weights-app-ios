import SwiftUI
import SwiftData

struct SetPlanCatalogView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<SetPlan> { !$0.deleted })
    private var allTemplates: [SetPlan]

    @Query private var userPropertiesItems: [UserProperties]
    @Query private var entitlementRecords: [EntitlementGrant]

    @State private var showNewTemplateAlert = false
    @State private var newTemplateName = ""
    @State private var showDeleteConfirmation = false
    @State private var templateToDelete: SetPlan?
    @State private var showUpsell = false

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

    private var builtInTemplates: [SetPlan] {
        allTemplates.filter { !$0.isCustom }.sorted { $0.createdAt < $1.createdAt }
    }

    private var customTemplates: [SetPlan] {
        allTemplates.filter { $0.isCustom }.sorted { $0.createdAt < $1.createdAt }
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
                            newTemplateName = ""
                            showNewTemplateAlert = true
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

                ScrollView {
                    VStack(spacing: 16) {
                        // Built-in section — free presets
                        if !builtInTemplates.isEmpty {
                            sectionHeader("Presets")

                            ForEach(builtInTemplates.filter { SetPlan.freePresetIds.contains($0.id) }) { template in
                                templateCard(template: template, isEditable: false)
                            }

                            // Premium presets
                            let premiumPresets = builtInTemplates.filter { !SetPlan.freePresetIds.contains($0.id) }
                            if !premiumPresets.isEmpty {
                                sectionHeader("Premium Set Plans")

                                if isPremium {
                                    ForEach(premiumPresets) { template in
                                        templateCard(template: template, isEditable: false)
                                    }
                                } else {
                                    // Show just a few cards as preview behind the lock
                                    VStack(spacing: 8) {
                                        ForEach(premiumPresets.prefix(3)) { template in
                                            templateCard(template: template, isEditable: false)
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

                        // User-created templates section
                        if !customTemplates.isEmpty {
                            sectionHeader("Your Templates")

                            ForEach(customTemplates) { template in
                                templateCard(template: template, isEditable: true)
                            }
                        }

                        // None option
                        noneCard()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .padding(.top, 8)
                }
            }
        }
        .fullScreenCover(isPresented: $showUpsell) {
            UpsellView(initialPage: setPlansUpsellPage) { _ in showUpsell = false }
        }
        .alert("New Template", isPresented: $showNewTemplateAlert) {
            TextField("Name", text: $newTemplateName)
            Button("Cancel", role: .cancel) { }
            Button("Create") {
                let trimmed = newTemplateName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                let defaultSequence = SetPlan.builtInTemplates.first(where: { $0.id == SetPlan.standardId })?.sequence ?? ["easy", "easy", "moderate", "moderate", "hard", "pr"]
                let template = SetPlan(
                    name: trimmed,
                    effortSequence: defaultSequence,
                    isCustom: true
                )
                modelContext.insert(template)
                userProperties.activeSetPlanId = template.id
                try? modelContext.save()
                Task {
                    await SyncService.shared.syncSetPlan(template)
                    await SyncService.shared.updateActiveSetPlan(template.id)
                }
            }
        } message: {
            Text("Name your custom template")
        }
        .alert("Delete Template?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                templateToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let template = templateToDelete {
                    deleteTemplate(template)
                }
                templateToDelete = nil
            }
        } message: {
            if let template = templateToDelete {
                Text("This will permanently delete \"\(template.name)\".")
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
    private func templateCard(template: SetPlan, isEditable: Bool) -> some View {
        let isActive = userProperties.activeSetPlanId == template.id

        VStack(alignment: .leading, spacing: 10) {
            // Title row with selection
            HStack(spacing: 12) {
                Button {
                    hapticFeedback.impactOccurred()
                    userProperties.activeSetPlanId = template.id
                    try? modelContext.save()
                    Task { await SyncService.shared.updateActiveSetPlan(template.id) }
                } label: {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isActive ? Color.appAccent : .white.opacity(0.3))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(template.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        if !template.isCustom {
                            Text("PRESET")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.4))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(4)
                        }
                    }

                    if let desc = template.templateDescription {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                Spacer()

                if isEditable {
                    Button {
                        hapticFeedback.impactOccurred()
                        templateToDelete = template
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
                    ForEach(Array(template.effortSequence.enumerated()), id: \.offset) { index, effort in
                        if isEditable {
                            SequenceSquareView(effort: effort)
                                .onTapGesture {
                                    let levels = Self.effortLevels
                                    let next = levels[((levels.firstIndex(of: effort) ?? 0) + 1) % levels.count]
                                    template.effortSequence[index] = next
                                    saveAndSyncTemplate(template)
                                    hapticFeedback.impactOccurred()
                                }
                                .onLongPressGesture {
                                    guard template.effortSequence.count > 1 else { return }
                                    template.effortSequence.remove(at: index)
                                    saveAndSyncTemplate(template)
                                    hapticFeedback.impactOccurred()
                                }
                        } else {
                            SequenceSquareView(effort: effort)
                        }
                    }

                    if isEditable && template.effortSequence.count < 20 {
                        Button {
                            template.effortSequence.append("easy")
                            saveAndSyncTemplate(template)
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
            userProperties.activeSetPlanId = template.id
            try? modelContext.save()
            Task { await SyncService.shared.updateActiveSetPlan(template.id) }
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

    private func saveAndSyncTemplate(_ template: SetPlan) {
        try? modelContext.save()
        Task { await SyncService.shared.syncSetPlan(template) }
    }

    private func deleteTemplate(_ template: SetPlan) {
        template.deleted = true
        if userProperties.activeSetPlanId == template.id {
            userProperties.activeSetPlanId = SetPlan.standardId
        }
        try? modelContext.save()
        Task {
            await SyncService.shared.deleteSetPlan(template.id)
            if userProperties.activeSetPlanId == SetPlan.standardId {
                await SyncService.shared.updateActiveSetPlan(SetPlan.standardId)
            }
        }
    }
}
