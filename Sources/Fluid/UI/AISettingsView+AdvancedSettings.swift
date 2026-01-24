//
//  AISettingsView+AdvancedSettings.swift
//  fluid
//
//  Extracted from AISettingsView.swift to keep view body under lint limit.
//

import AppKit
import SwiftUI

extension AIEnhancementSettingsView {
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
                            self.viewModel.openNewPromptEditor()
                        }
                        .buttonStyle(CompactButtonStyle(isReady: true))
                        .frame(minWidth: AISettingsLayout.actionMinWidth, minHeight: AISettingsLayout.controlHeight)
                    }

                    // Default prompt card
                    self.promptProfileCard(
                        title: "Default",
                        subtitle: self.viewModel.promptPreview(
                            self.settings.defaultDictationPromptOverride.map {
                                SettingsStore.stripBaseDictationPrompt(from: $0)
                            } ?? SettingsStore.defaultDictationPromptBodyText()
                        ),
                        isSelected: self.viewModel.selectedDictationPromptID == nil,
                        onUse: {
                            self.settings.selectedDictationPromptID = nil
                            self.viewModel.selectedDictationPromptID = nil
                        },
                        onOpen: { self.viewModel.openDefaultPromptViewer() }
                    )

                    // User prompt cards
                    let profiles = self.viewModel.dictationPromptProfiles
                    if profiles.isEmpty {
                        Text("No custom prompts yet. Click “+ Add Prompt” to create one.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    } else {
                        ForEach(profiles) { profile in
                            self.promptProfileCard(
                                title: profile.name.isEmpty ? "Untitled Prompt" : profile.name,
                                subtitle: profile.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? "Empty prompt (uses Default)"
                                    : self.viewModel.promptPreview(SettingsStore.stripBaseDictationPrompt(from: profile.prompt)),
                                isSelected: self.viewModel.selectedDictationPromptID == profile.id,
                                onUse: {
                                    self.settings.selectedDictationPromptID = profile.id
                                    self.viewModel.selectedDictationPromptID = profile.id
                                },
                                onOpen: { self.viewModel.openEditor(for: profile) },
                                onDelete: { self.viewModel.requestDeletePrompt(profile) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(14)
        }
        .sheet(item: self.$viewModel.promptEditorMode) { mode in
            self.promptEditorSheet(mode: mode)
        }
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
                    .frame(minWidth: AISettingsLayout.promptActionMinWidth, minHeight: AISettingsLayout.controlHeight)
                    .disabled(isSelected)

                if let onDelete {
                    Button(action: { onDelete() }) {
                        HStack(spacing: 4) { Image(systemName: "trash"); Text("Delete") }
                            .font(.caption)
                    }
                    .buttonStyle(CompactButtonStyle(foreground: .red, borderColor: .red.opacity(0.6)))
                    .frame(minWidth: AISettingsLayout.promptActionMinWidth, minHeight: AISettingsLayout.controlHeight)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(self.theme.palette.cardBackground.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? self.theme.palette.accent.opacity(0.55) : self.theme.palette.cardBorder.opacity(0.35), lineWidth: 1)
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
                TextField("Prompt name", text: self.$viewModel.draftPromptName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isDefaultNameLocked)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PromptTextView(
                    text: self.$viewModel.draftPromptText,
                    isEditable: true,
                    font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
                )
                .id(self.viewModel.promptEditorSessionID)
                .frame(minHeight: 180)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(self.theme.palette.contentBackground.opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(self.theme.palette.cardBorder.opacity(0.35), lineWidth: 1)
                        )
                )
                .onChange(of: self.viewModel.draftPromptText) { _, newValue in
                    let combined = self.viewModel.combinedDraftPrompt(newValue)
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

                let hotkeyDisplay = self.settings.hotkeyShortcut.displayString
                let canTest = self.viewModel.isAIPostProcessingConfiguredForDictation()

                Toggle(isOn: Binding(
                    get: { self.promptTest.isActive },
                    set: { enabled in
                        if enabled {
                            let combined = self.viewModel.combinedDraftPrompt(self.viewModel.draftPromptText)
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
                                .fill(self.theme.palette.contentBackground.opacity(0.7))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(self.theme.palette.cardBorder.opacity(0.35), lineWidth: 1)
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
                                .fill(self.theme.palette.contentBackground.opacity(0.7))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(self.theme.palette.cardBorder.opacity(0.35), lineWidth: 1)
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
                            .stroke(self.theme.palette.cardBorder.opacity(0.5), lineWidth: 1)
                    )
            )

            HStack(spacing: 10) {
                Button(mode.isDefault ? "Close" : "Cancel") {
                    self.viewModel.closePromptEditor()
                }
                .buttonStyle(CompactButtonStyle())
                .frame(minWidth: AISettingsLayout.actionMinWidth, minHeight: AISettingsLayout.controlHeight)

                Button("Save") {
                    self.viewModel.savePromptEditor(mode: mode)
                }
                .buttonStyle(GlassButtonStyle(height: AISettingsLayout.controlHeight))
                .frame(minWidth: AISettingsLayout.actionMinWidth, minHeight: AISettingsLayout.controlHeight)
                .disabled(!mode.isDefault && self.viewModel.draftPromptName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 420)
        .onDisappear {
            self.promptTest.deactivate()
        }
        .onChange(of: self.viewModel.enableAIProcessing) { _, _ in
            self.autoDisablePromptTestIfNeeded()
        }
        .onChange(of: self.viewModel.selectedProviderID) { _, _ in
            self.autoDisablePromptTestIfNeeded()
        }
        .onChange(of: self.viewModel.providerAPIKeys) { _, _ in
            self.autoDisablePromptTestIfNeeded()
        }
        .onChange(of: self.viewModel.savedProviders) { _, _ in
            self.autoDisablePromptTestIfNeeded()
        }
    }

    private func autoDisablePromptTestIfNeeded() {
        guard self.promptTest.isActive else { return }
        if !self.viewModel.isAIPostProcessingConfiguredForDictation() {
            self.promptTest.deactivate()
        }
    }

    func openDefaultPromptViewer() {
        self.viewModel.openDefaultPromptViewer()
    }

    func openNewPromptEditor() {
        self.viewModel.openNewPromptEditor()
    }

    func openEditor(for profile: SettingsStore.DictationPromptProfile) {
        self.viewModel.openEditor(for: profile)
    }

    func closePromptEditor() {
        self.viewModel.closePromptEditor()
    }

    // MARK: - Prompt Test Gating

    func isAIPostProcessingConfiguredForDictation() -> Bool {
        self.viewModel.isAIPostProcessingConfiguredForDictation()
    }

    func savePromptEditor(mode: PromptEditorMode) {
        self.viewModel.savePromptEditor(mode: mode)
    }
}
