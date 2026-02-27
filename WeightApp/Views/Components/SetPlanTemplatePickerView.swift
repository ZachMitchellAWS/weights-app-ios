import SwiftUI
import SwiftData

struct SetPlanTemplatePickerView: View {
    @Binding var selectedTemplateId: UUID?
    let onCustomSelected: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<SetPlanTemplate> { !$0.deleted })
    private var allTemplates: [SetPlanTemplate]

    @State private var showNewTemplateAlert = false
    @State private var newTemplateName = ""

    private var builtInTemplates: [SetPlanTemplate] {
        allTemplates.filter { $0.isBuiltIn }.sorted { $0.createdAt < $1.createdAt }
    }

    private var customTemplates: [SetPlanTemplate] {
        allTemplates.filter { !$0.isBuiltIn }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(white: 0.14), Color(white: 0.10)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Effort level legend — pinned above scroll
                    HStack(spacing: 8) {
                        ForEach(["easy", "moderate", "hard", "redline", "pr"], id: \.self) { level in
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
                        // Create new template button (top)
                        Button {
                            newTemplateName = ""
                            showNewTemplateAlert = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 18))
                                Text("New Template")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(Color.appAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.appAccent.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)

                        // Freeform option
                        templateRow(
                            name: "Freeform",
                            description: "Edit the set plan inline per exercise",
                            sequence: nil,
                            isSelected: selectedTemplateId == nil,
                            isBuiltIn: false
                        ) {
                            onCustomSelected()
                            dismiss()
                        }

                        // Built-in section
                        if !builtInTemplates.isEmpty {
                            sectionHeader("Presets")

                            ForEach(builtInTemplates) { template in
                                templateRow(
                                    name: template.name,
                                    description: template.templateDescription,
                                    sequence: template.effortSequence,
                                    isSelected: selectedTemplateId == template.id,
                                    isBuiltIn: true
                                ) {
                                    selectedTemplateId = template.id
                                    dismiss()
                                }
                            }
                        }

                        // User-created templates section
                        if !customTemplates.isEmpty {
                            sectionHeader("Your Templates")

                            ForEach(customTemplates) { template in
                                templateRow(
                                    name: template.name,
                                    description: template.templateDescription,
                                    sequence: template.effortSequence,
                                    isSelected: selectedTemplateId == template.id,
                                    isBuiltIn: false
                                ) {
                                    selectedTemplateId = template.id
                                    dismiss()
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deleteTemplate(template)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                }
            }
            .navigationTitle("Set Plan Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.appAccent)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .alert("New Template", isPresented: $showNewTemplateAlert) {
                TextField("Name", text: $newTemplateName)
                Button("Cancel", role: .cancel) { }
                Button("Create") {
                    let trimmed = newTemplateName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    let template = SetPlanTemplate(
                        name: trimmed,
                        effortSequence: Exercises.defaultSetPlan,
                        isBuiltIn: false
                    )
                    modelContext.insert(template)
                    try? modelContext.save()
                    selectedTemplateId = template.id
                    Task { await SyncService.shared.syncSetPlanTemplate(template) }
                    dismiss()
                }
            } message: {
                Text("Name your custom template")
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
    private func templateRow(name: String, description: String?, sequence: [String]?, isSelected: Bool, isBuiltIn: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.appAccent : .white.opacity(0.3))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        if isBuiltIn {
                            Text("PRESET")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.4))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(4)
                        }
                    }

                    if let desc = description {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    if let sequence = sequence {
                        HStack(spacing: 3) {
                            ForEach(Array(sequence.enumerated()), id: \.offset) { _, effort in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(SequenceSquareView.color(for: effort).opacity(0.4))
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(SequenceSquareView.color(for: effort), lineWidth: 1)
                                    )
                            }
                        }
                    }
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
                    .stroke(isSelected ? Color.appAccent : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func deleteTemplate(_ template: SetPlanTemplate) {
        template.deleted = true
        try? modelContext.save()
        if selectedTemplateId == template.id {
            selectedTemplateId = SetPlanTemplate.standardId
        }
        Task { await SyncService.shared.deleteSetPlanTemplate(template.id) }
    }
}
