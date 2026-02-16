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

                // Prompts (unified prompt system)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Prompts")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(self.theme.palette.primaryText)
                            Text("Create mode-specific prompts for Dictate and Edit. Select which prompt is active per mode.")
                                .font(.system(size: 13))
                                .foregroundStyle(self.theme.palette.secondaryText)
                        }
                        Spacer()
                        Button("+ Add Prompt") {
                            self.viewModel.openNewPromptEditor(prefillMode: .edit)
                        }
                        .buttonStyle(CompactButtonStyle(isReady: true))
                        .frame(minWidth: AISettingsLayout.actionMinWidth, minHeight: AISettingsLayout.controlHeight)
                    }

                    // Built-in default cards
                    self.promptProfileCard(
                        title: "Default Dictate",
                        subtitle: self.viewModel.promptPreview(self.viewModel.defaultPromptBodyPreview(for: .dictate)),
                        mode: .dictate,
                        isSelected: self.viewModel.selectedPromptID(for: .dictate) == nil,
                        onUse: {
                            self.viewModel.setSelectedPromptID(nil, for: .dictate)
                        },
                        onOpen: { self.viewModel.openDefaultPromptViewer(for: .dictate) }
                    )

                    self.promptProfileCard(
                        title: "Default Edit",
                        subtitle: self.viewModel.promptPreview(self.viewModel.defaultPromptBodyPreview(for: .edit)),
                        mode: .edit,
                        isSelected: self.viewModel.selectedPromptID(for: .edit) == nil,
                        onUse: {
                            self.viewModel.setSelectedPromptID(nil, for: .edit)
                        },
                        onOpen: { self.viewModel.openDefaultPromptViewer(for: .edit) }
                    )

                    // User prompt cards
                    let profiles = self.viewModel.dictationPromptProfiles
                        .filter { SettingsStore.PromptMode.visiblePromptModes.contains($0.mode.normalized) }
                    if profiles.isEmpty {
                        Text("No custom prompts yet. Click “+ Add Prompt” to create one.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    } else {
                        ForEach(profiles) { profile in
                            self.promptProfileCard(
                                title: profile.name.isEmpty ? "Untitled Prompt" : profile.name,
                                subtitle: SettingsStore.stripBasePrompt(for: profile.mode, from: profile.prompt).isEmpty
                                    ? "Empty prompt (uses Default)"
                                    : self.viewModel.promptPreview(SettingsStore.stripBasePrompt(for: profile.mode, from: profile.prompt)),
                                mode: profile.mode,
                                showContextBadge: profile.includeContext,
                                isSelected: self.viewModel.selectedPromptID(for: profile.mode) == profile.id,
                                onUse: {
                                    self.viewModel.setSelectedPromptID(profile.id, for: profile.mode)
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
        mode: SettingsStore.PromptMode,
        showContextBadge: Bool = false,
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
                        Text(mode.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(self.theme.palette.cardBorder.opacity(0.3))
                            )
                            .foregroundStyle(self.theme.palette.secondaryText)
                        if showContextBadge {
                            Text("Uses {context}")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(self.theme.palette.accent.opacity(0.16))
                                )
                                .foregroundStyle(self.theme.palette.accent)
                        }
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
                        case let .defaultPrompt(promptMode): return "Default \(promptMode.displayName) Prompt"
                        case let .newPrompt(prefillMode): return "New \(prefillMode.displayName) Prompt"
                        case .edit: return "Edit Prompt"
                        }
                    }())
                        .font(.headline)
                    Text(mode.isDefault
                        ? "This is the built-in prompt. Create a custom prompt to override it."
                        : "Prompt text is appended to the hidden base prompt for the selected mode."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Mode", selection: self.$viewModel.draftPromptMode) {
                    ForEach(SettingsStore.PromptMode.visiblePromptModes) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(mode.isDefault)
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
                    guard self.viewModel.draftPromptMode == .dictate else { return }
                    let combined = self.viewModel.combinedDraftPrompt(newValue, mode: self.viewModel.draftPromptMode)
                    self.promptTest.updateDraftPromptText(combined)
                }
            }

            if self.viewModel.draftPromptMode != .dictate {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Include selected text context", isOn: self.$viewModel.draftIncludeContext)
                        .toggleStyle(.switch)
                        .disabled(mode.isDefault)

                    Text("Template added when enabled:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(SettingsStore.contextTemplateText())
                        .font(.system(.caption2, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
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

            // MARK: - Test Mode

            if self.viewModel.draftPromptMode == .dictate {
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
                            let combined = self.viewModel.combinedDraftPrompt(self.viewModel.draftPromptText, mode: self.viewModel.draftPromptMode)
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
            } else if self.promptTest.isActive {
                Text("Prompt test mode is available only for Dictate prompts.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .onAppear { self.promptTest.deactivate() }
            }

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

    func openDefaultPromptViewer(for mode: SettingsStore.PromptMode) {
        self.viewModel.openDefaultPromptViewer(for: mode)
    }

    func openNewPromptEditor(prefillMode: SettingsStore.PromptMode = .edit) {
        self.viewModel.openNewPromptEditor(prefillMode: prefillMode)
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
