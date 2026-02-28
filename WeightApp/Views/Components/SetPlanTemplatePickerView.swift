import SwiftUI
import SwiftData

struct SetPlanCatalogView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<SetPlanTemplate> { !$0.deleted })
    private var allTemplates: [SetPlanTemplate]

    @Query private var userPropertiesItems: [UserProperties]

    @State private var showNewTemplateAlert = false
    @State private var newTemplateName = ""
    @State private var showDeleteConfirmation = false
    @State private var templateToDelete: SetPlanTemplate?

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)
    private static let effortLevels = ["easy", "moderate", "hard", "redline", "pr"]

    private var userProperties: UserProperties {
        if let props = userPropertiesItems.first { return props }
        let props = UserProperties()
        modelContext.insert(props)
        return props
    }

    private var builtInTemplates: [SetPlanTemplate] {
        allTemplates.filter { $0.isBuiltIn }.sorted { $0.createdAt < $1.createdAt }
    }

    private var customTemplates: [SetPlanTemplate] {
        allTemplates.filter { !$0.isBuiltIn }.sorted { $0.createdAt < $1.createdAt }
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
                        newTemplateName = ""
                        showNewTemplateAlert = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
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
                        // Built-in section
                        if !builtInTemplates.isEmpty {
                            sectionHeader("Presets")

                            ForEach(builtInTemplates) { template in
                                templateCard(template: template, isEditable: false)
                            }
                        }

                        // User-created templates section
                        if !customTemplates.isEmpty {
                            sectionHeader("Your Templates")

                            ForEach(customTemplates) { template in
                                templateCard(template: template, isEditable: true)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .padding(.top, 8)
                }
            }
        }
        .alert("New Template", isPresented: $showNewTemplateAlert) {
            TextField("Name", text: $newTemplateName)
            Button("Cancel", role: .cancel) { }
            Button("Create") {
                let trimmed = newTemplateName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                let defaultSequence = SetPlanTemplate.builtInTemplates.first(where: { $0.id == SetPlanTemplate.standardId })?.sequence ?? ["easy", "moderate", "moderate", "hard", "pr"]
                let template = SetPlanTemplate(
                    name: trimmed,
                    effortSequence: defaultSequence,
                    isBuiltIn: false
                )
                modelContext.insert(template)
                userProperties.activeSetPlanTemplateId = template.id
                try? modelContext.save()
                Task {
                    await SyncService.shared.syncSetPlanTemplate(template)
                    await SyncService.shared.updateActiveSetPlanTemplate(template.id)
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
    private func templateCard(template: SetPlanTemplate, isEditable: Bool) -> some View {
        let isActive = userProperties.activeSetPlanTemplateId == template.id

        VStack(alignment: .leading, spacing: 10) {
            // Title row with selection
            HStack(spacing: 12) {
                Button {
                    hapticFeedback.impactOccurred()
                    userProperties.activeSetPlanTemplateId = template.id
                    try? modelContext.save()
                    Task { await SyncService.shared.updateActiveSetPlanTemplate(template.id) }
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

                        if template.isBuiltIn {
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
    }

    private func saveAndSyncTemplate(_ template: SetPlanTemplate) {
        try? modelContext.save()
        Task { await SyncService.shared.syncSetPlanTemplate(template) }
    }

    private func deleteTemplate(_ template: SetPlanTemplate) {
        template.deleted = true
        if userProperties.activeSetPlanTemplateId == template.id {
            userProperties.activeSetPlanTemplateId = SetPlanTemplate.standardId
        }
        try? modelContext.save()
        Task {
            await SyncService.shared.deleteSetPlanTemplate(template.id)
            if userProperties.activeSetPlanTemplateId == SetPlanTemplate.standardId {
                await SyncService.shared.updateActiveSetPlanTemplate(SetPlanTemplate.standardId)
            }
        }
    }
}
