//
//  AISettingsView+AdvancedSettings.swift
//  fluid
//
//  Extracted from AISettingsView.swift to keep view body under lint limit.
//

import AppKit
import SwiftUI

extension AISettingsView {
    // MARK: - Advanced Settings Card

    var advancedSettingsCard: some View {
        ThemedCard(style: .prominent, hoverEffect: false) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Image(systemName: "gearshape.2.fill")
                        .font(.title3)
                        .foregroundStyle(self.theme.palette.accent)
                    Text("Advanced")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                }

                // Dictation Prompts (multi-prompt system)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dictation Prompts")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(self.theme.palette.primaryText)
                            Text("Create multiple named system prompts for AI dictation cleanup. Select which one is active.")
                                .font(.system(size: 13))
                                .foregroundStyle(self.theme.palette.secondaryText)
                        }
                        Spacer()
                        Button("+ Add Prompt") {
                            self.openNewPromptEditor()
                        }
                        .buttonStyle(CompactButtonStyle())
                        .frame(width: 120)
                    }

                    // Default prompt card
                    self.promptProfileCard(
                        title: "Default",
                        subtitle: self.promptPreview(
                            self.settings.defaultDictationPromptOverride.map {
                                SettingsStore.stripBaseDictationPrompt(from: $0)
                            } ?? SettingsStore.defaultDictationPromptBodyText()
                        ),
                        isSelected: self.settings.selectedDictationPromptProfile == nil,
                        onUse: { self.settings.selectedDictationPromptID = nil },
                        onOpen: { self.openDefaultPromptViewer() }
                    )

                    // User prompt cards
                    let profiles = self.settings.dictationPromptProfiles
                    if profiles.isEmpty {
                        Text("No custom prompts yet. Click “+ Add Prompt” to create one.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    } else {
                        ForEach(profiles) { profile in
                            self.promptProfileCard(
                                title: profile.name.isEmpty ? "Untitled Prompt" : profile.name,
                                subtitle: profile.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Empty prompt (uses Default)" : self.promptPreview(SettingsStore.stripBaseDictationPrompt(from: profile.prompt)),
                                isSelected: self.settings.selectedDictationPromptID == profile.id,
                                onUse: { self.settings.selectedDictationPromptID = profile.id },
                                onOpen: { self.openEditor(for: profile) },
                                onDelete: { self.requestDeletePrompt(profile) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(14)
        }
        .modifier(CardAppearAnimation(delay: 0.3, appear: self.$appear))
        .sheet(item: self.$promptEditorMode) { mode in
            self.promptEditorSheet(mode: mode)
        }
    }

    func promptPreview(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Empty prompt" }
        let singleLine = trimmed.replacingOccurrences(of: "\n", with: " ")
        return singleLine.count > 120 ? String(singleLine.prefix(120)) + "…" : singleLine
    }

    /// Combine a user-visible body with the hidden base prompt to ensure role/intent is always present.
    func combinedDraftPrompt(_ text: String) -> String {
        let body = SettingsStore.stripBaseDictationPrompt(from: text)
        return SettingsStore.combineBasePrompt(with: body)
    }

    func requestDeletePrompt(_ profile: SettingsStore.DictationPromptProfile) {
        self.pendingDeletePromptID = profile.id
        self.pendingDeletePromptName = profile.name.isEmpty ? "Untitled Prompt" : profile.name
        self.showingDeletePromptConfirm = true
    }

    func clearPendingDeletePrompt() {
        self.showingDeletePromptConfirm = false
        self.pendingDeletePromptID = nil
        self.pendingDeletePromptName = ""
    }

    func deletePendingPrompt() {
        guard let id = self.pendingDeletePromptID else {
            self.clearPendingDeletePrompt()
            return
        }

        // Remove profile
        var profiles = self.settings.dictationPromptProfiles
        profiles.removeAll { $0.id == id }
        self.settings.dictationPromptProfiles = profiles

        // If the deleted profile was active, reset to Default
        if self.settings.selectedDictationPromptID == id {
            self.settings.selectedDictationPromptID = nil
        }

        self.clearPendingDeletePrompt()
    }

    func promptProfileCard(
        title: String,
        subtitle: String,
        isSelected: Bool,
        onUse: @escaping () -> Void,
        onOpen: @escaping () -> Void,
        onDelete: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(self.theme.palette.primaryText)
                        if isSelected {
                            Text("Active")
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.fluidGreen.opacity(0.18)))
                                .foregroundStyle(Color.fluidGreen)
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button("Use") { onUse() }
                    .buttonStyle(CompactButtonStyle())
                    .frame(width: 54)
                    .disabled(isSelected)

                if let onDelete {
                    Button(action: { onDelete() }) {
                        HStack(spacing: 4) { Image(systemName: "trash"); Text("Delete") }
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(CompactButtonStyle())
                    .frame(width: 74)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? self.theme.palette.accent.opacity(0.55) : .white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    func promptEditorSheet(mode: PromptEditorMode) -> some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text({
                        switch mode {
                        case .defaultPrompt: return "Default Dictation Prompt"
                        case .newPrompt: return "New Dictation Prompt"
                        case .edit: return "Edit Dictation Prompt"
                        }
                    }())
                        .font(.headline)
                    Text(mode.isDefault
                        ? "This is the built-in prompt. Create a custom prompt to override it."
                        : "Name and prompt text are used as the system prompt for dictation cleanup."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let isDefaultNameLocked = mode.isDefault
                TextField("Prompt name", text: self.$draftPromptName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isDefaultNameLocked)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PromptTextView(
                    text: self.$draftPromptText,
                    isEditable: true,
                    font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
                )
                .id(self.promptEditorSessionID)
                .frame(minHeight: 180)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.25))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(.white.opacity(0.12), lineWidth: 1)
                        )
                )
                .onChange(of: self.draftPromptText) { _, newValue in
                    let combined = self.combinedDraftPrompt(newValue)
                    self.promptTest.updateDraftPromptText(combined)
                }
            }

            // MARK: - Test Mode

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundStyle(self.theme.palette.accent)
                    Text("Test")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                }

                let hotkeyDisplay = SettingsStore.shared.hotkeyShortcut.displayString
                let canTest = self.isAIPostProcessingConfiguredForDictation()

                Toggle(isOn: Binding(
                    get: { self.promptTest.isActive },
                    set: { enabled in
                        if enabled {
                            let combined = self.combinedDraftPrompt(self.draftPromptText)
                            self.promptTest.activate(draftPromptText: combined)
                        } else {
                            self.promptTest.deactivate()
                        }
                    }
                )) {
                    Text("Enable Test Mode (Hotkey: \(hotkeyDisplay))")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .disabled(!canTest)

                if !canTest {
                    Text("Testing is disabled because AI post-processing is not configured.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if self.promptTest.isActive {
                    Text("Press the hotkey to start/stop recording. The transcription will be post-processed using your draft prompt and shown below (nothing will be typed into other apps).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if self.promptTest.isActive {
                    if self.promptTest.isProcessing {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Processing…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !self.promptTest.lastError.isEmpty {
                        Text(self.promptTest.lastError)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Raw transcription")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextEditor(text: Binding(
                            get: { self.promptTest.lastTranscriptionText },
                            set: { _ in }
                        ))
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 70)
                        .scrollContentBackground(.hidden)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.ultraThinMaterial.opacity(0.25))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(.white.opacity(0.12), lineWidth: 1)
                                )
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Post-processed output")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextEditor(text: Binding(
                            get: { self.promptTest.lastOutputText },
                            set: { _ in }
                        ))
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 110)
                        .scrollContentBackground(.hidden)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.ultraThinMaterial.opacity(0.25))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(.white.opacity(0.12), lineWidth: 1)
                                )
                        )
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(self.theme.palette.accent.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.white.opacity(0.10), lineWidth: 1)
                    )
            )

            HStack(spacing: 10) {
                Button(mode.isDefault ? "Close" : "Cancel") {
                    self.closePromptEditor()
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    self.savePromptEditor(mode: mode)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!mode.isDefault && self.draftPromptName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 420)
        .onDisappear {
            self.promptTest.deactivate()
        }
    }

    func openDefaultPromptViewer() {
        self.draftPromptName = "Default"
        if let override = self.settings.defaultDictationPromptOverride {
            self.draftPromptText = SettingsStore.stripBaseDictationPrompt(from: override)
        } else {
            self.draftPromptText = SettingsStore.defaultDictationPromptBodyText()
        }
        self.promptEditorSessionID = UUID()
        self.promptEditorMode = .defaultPrompt
    }

    func openNewPromptEditor() {
        self.draftPromptName = "New Prompt"
        self.draftPromptText = ""
        self.promptEditorSessionID = UUID()
        self.promptEditorMode = .newPrompt
    }

    func openEditor(for profile: SettingsStore.DictationPromptProfile) {
        self.draftPromptName = profile.name
        self.draftPromptText = SettingsStore.stripBaseDictationPrompt(from: profile.prompt)
        self.promptEditorSessionID = UUID()
        self.promptEditorMode = .edit(promptID: profile.id)
    }

    func closePromptEditor() {
        self.promptEditorMode = nil
        self.draftPromptName = ""
        self.draftPromptText = ""
        self.promptTest.deactivate()
    }

    // MARK: - Prompt Test Gating

    func isAIPostProcessingConfiguredForDictation() -> Bool {
        DictationAIPostProcessingGate.isConfigured()
    }

    func savePromptEditor(mode: PromptEditorMode) {
        // Default prompt is non-deletable; save it via the optional override (empty is allowed).
        if mode.isDefault {
            let body = SettingsStore.stripBaseDictationPrompt(from: self.draftPromptText)
            self.settings.defaultDictationPromptOverride = body
            self.closePromptEditor()
            return
        }

        let name = self.draftPromptName.trimmingCharacters(in: .whitespacesAndNewlines)
        let promptBody = SettingsStore.stripBaseDictationPrompt(from: self.draftPromptText)

        var profiles = SettingsStore.shared.dictationPromptProfiles
        let now = Date()

        if let id = mode.editingPromptID,
           let idx = profiles.firstIndex(where: { $0.id == id })
        {
            var updated = profiles[idx]
            updated.name = name
            updated.prompt = promptBody
            updated.updatedAt = now
            profiles[idx] = updated
        } else {
            let newProfile = SettingsStore.DictationPromptProfile(name: name, prompt: promptBody, createdAt: now, updatedAt: now)
            profiles.append(newProfile)
        }

        SettingsStore.shared.dictationPromptProfiles = profiles
        self.closePromptEditor()
    }
}
