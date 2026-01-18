//
//  AISettingsView.swift
//  fluid
//
//  Extracted from ContentView.swift to reduce monolithic architecture.
//  Created: 2025-12-14
//

import AppKit
import Security
import SwiftUI

// MARK: - Connection Status Enum

enum AIConnectionStatus {
    case unknown, testing, success, failed
}

// MARK: - Liquid Layer Shape (Gentle bobbing wave)

/// A gentle wave surface that bobs up and down
private struct LiquidLayer: Shape {
    var phase: Double // Phase offset for this layer
    var time: Double // Animation time

    var animatableData: Double {
        get { self.time }
        set { self.time = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = Double(rect.width)
        let height = Double(rect.height)

        // Wave surface very close to the top (only 3% offset for wave amplitude)
        let baseY = height * 0.03

        path.move(to: CGPoint(x: 0, y: CGFloat(baseY)))

        // Create a gentle, organic wave surface
        for x in stride(from: 0.0, through: width, by: 1.0) {
            let normalizedX = x / width

            // Slow, gentle wave like water sloshing in a jar
            let waveAmplitude = 2.0
            let waveFrequency = 1.5 // Lower frequency = broader, more ocean-like waves
            let y = baseY + sin((normalizedX * waveFrequency + self.time * 0.25 + self.phase) * .pi) * waveAmplitude

            path.addLine(to: CGPoint(x: CGFloat(x), y: CGFloat(y)))
        }

        // Fill down to bottom
        path.addLine(to: CGPoint(x: CGFloat(width), y: CGFloat(height)))
        path.addLine(to: CGPoint(x: 0, y: CGFloat(height)))
        path.closeSubpath()

        return path
    }
}

/// A vertical liquid-filled bar with animated fill level
private struct LiquidBar: View {
    let fillPercent: Double
    let color: Color
    let secondaryColor: Color
    let icon: String
    let label: String

    // Animated fill level (smoothly transitions between values)
    @State private var animatedFill: Double = 0

    var body: some View {
        VStack(spacing: 8) {
            // Label
            HStack(spacing: 4) {
                Image(systemName: self.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(self.color)
                Text(self.label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            // Liquid Container (Capsule Glass)
            ZStack(alignment: .bottom) {
                // Background (Empty glass interior)
                Capsule()
                    .fill(Color.black.opacity(0.35))
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.25), .white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )

                // Single clean liquid layer with animated height
                GeometryReader { geo in
                    let displayHeight = geo.size.height * CGFloat(self.animatedFill)

                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        let time = timeline.date.timeIntervalSinceReferenceDate

                        // Single organic liquid surface
                        LiquidLayer(phase: 0.0, time: time)
                            .fill(
                                LinearGradient(
                                    colors: [self.color, self.secondaryColor],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(height: displayHeight)
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .clipShape(Capsule())
                .padding(3)

                // Glass highlight (3D glossy effect)
                Capsule()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.25), location: 0),
                                .init(color: .white.opacity(0.08), location: 0.25),
                                .init(color: .clear, location: 0.5),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(2)
                    .allowsHitTesting(false)
            }
            .frame(width: 48, height: 90)

            // Percentage (shows target, not animated)
            Text("\(Int(self.fillPercent * 100))%")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(self.fillPercent > 0 ? self.color : .secondary)
                .contentTransition(.numericText())
        }
        .onAppear {
            // Initialize to target on first appear
            self.animatedFill = self.fillPercent
        }
        .onChange(of: self.fillPercent) { _, newValue in
            // Animate liquid level change with a gentle "sloshing" feel
            withAnimation(.interpolatingSpring(stiffness: 140, damping: 18)) {
                self.animatedFill = newValue
            }
        }
    }
}

private enum PromptEditorMode: Identifiable, Equatable {
    case defaultPrompt
    case newPrompt
    case edit(promptID: String)

    var id: String {
        switch self {
        case .defaultPrompt: return "default"
        case .newPrompt: return "new"
        case let .edit(promptID): return "edit:\(promptID)"
        }
    }

    var isDefault: Bool {
        if case .defaultPrompt = self { return true }
        return false
    }

    var editingPromptID: String? {
        if case let .edit(promptID) = self { return promptID }
        return nil
    }
}

struct AISettingsView: View {
    @EnvironmentObject private var appServices: AppServices
    @EnvironmentObject private var menuBarManager: MenuBarManager
    @Environment(\.theme) private var theme
    @ObservedObject private var promptTest = DictationPromptTestCoordinator.shared

    private var asr: ASRService { self.appServices.asr }

    // MARK: - State Variables (moved from ContentView)

    @ObservedObject private var settings = SettingsStore.shared

    @State private var appear = false
    @State private var openAIBaseURL: String = ModelRepository.shared.defaultBaseURL(for: "openai")
    @State private var enableAIProcessing: Bool = false

    // Model Management
    @State private var availableModelsByProvider: [String: [String]] = [:]
    @State private var selectedModelByProvider: [String: String] = [:]
    @State private var availableModels: [String] = ["gpt-4.1"]
    @State private var selectedModel: String = "gpt-4.1"
    @State private var showingAddModel: Bool = false
    @State private var newModelName: String = ""
    @State private var isFetchingModels: Bool = false
    @State private var fetchModelsError: String? = nil

    // Reasoning Configuration
    @State private var showingReasoningConfig: Bool = false
    @State private var editingReasoningParamName: String = "reasoning_effort"
    @State private var editingReasoningParamValue: String = "low"
    @State private var editingReasoningEnabled: Bool = false

    // Provider Management
    @State private var providerAPIKeys: [String: String] = [:]
    @State private var currentProvider: String = "openai"
    @State private var savedProviders: [SettingsStore.SavedProvider] = []
    @State private var selectedProviderID: String = SettingsStore.shared.selectedProviderID

    // Connection Testing
    @State private var isTestingConnection: Bool = false
    @State private var connectionStatus: AIConnectionStatus = .unknown
    @State private var connectionErrorMessage: String = ""

    // UI State
    @State private var showHelp: Bool = false
    @State private var showingSaveProvider: Bool = false
    @State private var showAPIKeyEditor: Bool = false

    @State private var showingEditProvider: Bool = false

    // Provider Form State
    @State private var newProviderName: String = ""
    @State private var newProviderBaseURL: String = ""
    @State private var newProviderApiKey: String = ""
    @State private var newProviderModels: String = ""
    @State private var editProviderName: String = ""
    @State private var editProviderBaseURL: String = ""

    // Keychain State
    @State private var showKeychainPermissionAlert: Bool = false
    @State private var keychainPermissionMessage: String = ""

    // Filler Words State - local state to ensure UI reactivity
    @State private var removeFillerWordsEnabled: Bool = SettingsStore.shared.removeFillerWordsEnabled

    // Dictation Prompt Profiles UI
    @State private var promptEditorMode: PromptEditorMode? = nil
    @State private var draftPromptName: String = ""
    @State private var draftPromptText: String = ""
    @State private var promptEditorSessionID: UUID = .init()

    // Prompt Deletion UI
    @State private var showingDeletePromptConfirm: Bool = false
    @State private var pendingDeletePromptID: String? = nil
    @State private var pendingDeletePromptName: String = ""

    // Speech Model Provider Tab Selection
    @State private var selectedSpeechProvider: SettingsStore.SpeechModel.Provider = .nvidia
    @State private var previewSpeechModel: SettingsStore.SpeechModel = SettingsStore.shared.selectedSpeechModel
    @State private var showAdvancedSpeechInfo: Bool = false
    @State private var suppressSpeechProviderSync: Bool = false
    @State private var skipNextSpeechModelSync: Bool = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                self.speechRecognitionCard
                self.aiConfigurationCard
            }
            .padding(14)
        }
        .onAppear {
            self.appear = true
            self.loadSettings()

            // CRITICAL FIX: Refresh model status immediately on appear
            // This ensures the speech recognition card shows current download status
            // Use async variant for accurate detection (especially for AppleSpeechAnalyzerProvider)
            Task {
                await self.asr.checkIfModelsExistAsync()
            }
        }
        .onChange(of: self.enableAIProcessing) { _, newValue in
            SettingsStore.shared.enableAIProcessing = newValue
            // Keep menu bar UI in sync when toggled from this screen
            self.menuBarManager.aiProcessingEnabled = newValue
        }
        .onChange(of: self.selectedModel) { _, newValue in
            if newValue != "__ADD_MODEL__" {
                self.selectedModelByProvider[self.currentProvider] = newValue
                SettingsStore.shared.selectedModelByProvider = self.selectedModelByProvider
            }
        }
        .onChange(of: self.selectedProviderID) { _, newValue in
            SettingsStore.shared.selectedProviderID = newValue
        }
        .onChange(of: self.settings.selectedSpeechModel) { _, newValue in
            // Keep preview in sync if the active model changes elsewhere
            if self.skipNextSpeechModelSync {
                self.skipNextSpeechModelSync = false
                return
            }
            guard !self.suppressSpeechProviderSync else { return }
            self.previewSpeechModel = newValue
            self.setSelectedSpeechProvider(newValue.provider)
        }
        .onChange(of: self.showKeychainPermissionAlert) { _, isPresented in
            guard isPresented else { return }
            self.presentKeychainAccessAlert(message: self.keychainPermissionMessage)
            self.showKeychainPermissionAlert = false
        }
        .alert("Delete Prompt?", isPresented: self.$showingDeletePromptConfirm) {
            Button("Delete", role: .destructive) {
                self.deletePendingPrompt()
            }
            Button("Cancel", role: .cancel) {
                self.clearPendingDeletePrompt()
            }
        } message: {
            if self.pendingDeletePromptName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("This cannot be undone.")
            } else {
                Text("Delete “\(self.pendingDeletePromptName)”? This cannot be undone.")
            }
        }
    }

    // MARK: - Load Settings

    private func loadSettings() {
        self.selectedProviderID = SettingsStore.shared.selectedProviderID

        self.enableAIProcessing = SettingsStore.shared.enableAIProcessing
        self.availableModelsByProvider = SettingsStore.shared.availableModelsByProvider
        self.selectedModelByProvider = SettingsStore.shared.selectedModelByProvider
        self.providerAPIKeys = SettingsStore.shared.providerAPIKeys
        self.savedProviders = SettingsStore.shared.savedProviders
        self.previewSpeechModel = SettingsStore.shared.selectedSpeechModel
        self.selectedSpeechProvider = SettingsStore.shared.selectedSpeechModel.provider

        // Normalize provider keys
        var normalized: [String: [String]] = [:]
        for (key, models) in self.availableModelsByProvider {
            let lower = key.lowercased()
            let newKey: String
            // Use ModelRepository to correctly identify ALL built-in providers
            if ModelRepository.shared.isBuiltIn(lower) {
                newKey = lower
            } else {
                newKey = key.hasPrefix("custom:") ? key : "custom:\(key)"
            }
            let clean = Array(Set(models.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })).sorted()
            if !clean.isEmpty { normalized[newKey] = clean }
        }
        self.availableModelsByProvider = normalized
        SettingsStore.shared.availableModelsByProvider = normalized

        // Normalize selected model by provider
        var normalizedSel: [String: String] = [:]
        for (key, model) in self.selectedModelByProvider {
            let lower = key.lowercased()
            // Use ModelRepository to correctly identify ALL built-in providers
            let newKey: String = ModelRepository.shared.isBuiltIn(lower) ? lower :
                (key.hasPrefix("custom:") ? key : "custom:\(key)")
            if let list = normalized[newKey], list.contains(model) { normalizedSel[newKey] = model }
        }
        self.selectedModelByProvider = normalizedSel
        SettingsStore.shared.selectedModelByProvider = normalizedSel

        // Determine initial model list AND set baseURL BEFORE calling updateCurrentProvider
        if let saved = savedProviders.first(where: { $0.id == selectedProviderID }) {
            let key = self.providerKey(for: self.selectedProviderID)
            let stored = self.availableModelsByProvider[key]
            self.availableModels = saved.models.isEmpty ? (stored ?? []) : saved.models
            self.openAIBaseURL = saved.baseURL // Set this FIRST
        } else if ModelRepository.shared.isBuiltIn(self.selectedProviderID) {
            // Handle all built-in providers using ModelRepository
            self.openAIBaseURL = ModelRepository.shared.defaultBaseURL(for: self.selectedProviderID)
            let key = self.selectedProviderID
            self.availableModels = self.availableModelsByProvider[key] ?? ModelRepository.shared.defaultModels(for: key)
        } else {
            self.availableModels = ModelRepository.shared.defaultModels(for: self.providerKey(for: self.selectedProviderID))
        }

        // NOW update currentProvider after openAIBaseURL is set correctly
        self.updateCurrentProvider()

        // Restore selected model using the correct currentProvider
        // If no models available, clear selection
        if self.availableModels.isEmpty {
            self.selectedModel = ""
        } else if let sel = selectedModelByProvider[currentProvider], availableModels.contains(sel) {
            self.selectedModel = sel
        } else if let first = availableModels.first {
            self.selectedModel = first
        }

        DebugLogger.shared.debug("loadSettings complete: provider=\(self.selectedProviderID), currentProvider=\(self.currentProvider), model=\(self.selectedModel), baseURL=\(self.openAIBaseURL)", source: "AISettingsView")
    }

    // MARK: - Speech Recognition Card

    private var speechRecognitionCard: some View {
        ThemedCard(hoverEffect: false) {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundStyle(self.theme.palette.accent)
                    Text("Voice Engine")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Toggle("Show model names", isOn: self.$showAdvancedSpeechInfo)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                    Spacer()
                }

                // Provider Tabs (centered, no label)
                HStack {
                    Spacer()
                    Picker("", selection: self.$selectedSpeechProvider) {
                        ForEach(SettingsStore.SpeechModel.Provider.allCases, id: \.self) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 280)
                    Spacer()
                }
                .padding(.vertical, 4)
                .onChange(of: self.selectedSpeechProvider) { _, newProvider in
                    // Preview the first model in the new provider (do not activate)
                    if self.previewSpeechModel.provider == newProvider { return }
                    if let firstModel = SettingsStore.SpeechModel.models(for: newProvider).first {
                        self.previewSpeechModel = firstModel
                    }
                }

                // Stats Panel - Dynamic bars that update based on selected model
                self.modelStatsPanel

                // Model Cards for selected provider
                VStack(spacing: 8) {
                    ForEach(SettingsStore.SpeechModel.models(for: self.selectedSpeechProvider)) { model in
                        self.speechModelCard(for: model)
                    }
                }

                Divider().padding(.vertical, 4)

                // Filler Words Section
                self.fillerWordsSection
            }
            .padding(14)
        }
    }

    /// Stats panel showing speed/accuracy bars that animate when model changes
    private var modelStatsPanel: some View {
        let model = self.previewSpeechModel

        return VStack(alignment: .leading, spacing: 8) {
            // Model name and description
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.humanReadableName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(self.theme.palette.primaryText)

                    if let badge = model.badgeText {
                        Text(badge)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(badge == "FluidVoice Pick" ? .cyan.opacity(0.2) : .orange.opacity(0.2)))
                            .foregroundStyle(badge == "FluidVoice Pick" ? .cyan : .orange)
                    }

                    Spacer()
                }

                Text(model.cardDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Label(model.downloadSize, systemImage: "internaldrive")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if model.requiresAppleSilicon {
                    Text("Apple Silicon")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(self.theme.palette.accent.opacity(0.2)))
                        .foregroundStyle(self.theme.palette.accent)
                }

                Text(model.languageSupport)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))
                    .foregroundStyle(.secondary)

                Spacer()
            }

            // Speed and Accuracy - Vertical Liquid Bars (FluidVoice easter egg!)
            HStack(spacing: 16) {
                Spacer()

                // Speed liquid bar
                LiquidBar(
                    fillPercent: model.speedPercent,
                    color: .yellow,
                    secondaryColor: .orange,
                    icon: "bolt.fill",
                    label: "Speed"
                )

                // Accuracy liquid bar
                LiquidBar(
                    fillPercent: model.accuracyPercent,
                    color: .green,
                    secondaryColor: .cyan,
                    icon: "target",
                    label: "Accuracy"
                )

                Spacer()
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: model.id)
        }
        .padding(.vertical, 6)
    }

    /// Simplified card for selecting a speech model
    private func speechModelCard(for model: SettingsStore.SpeechModel) -> some View {
        let isSelected = self.previewSpeechModel == model
        let isActive = self.isActiveSpeechModel(model)

        return HStack(spacing: 10) {
            // Selection indicator
            Circle()
                .fill(isSelected ? .green : .white.opacity(0.1))
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(isSelected ? .green : .white.opacity(0.3), lineWidth: 1)
                )

            // Brand logo/badge - fixed size container for consistency
            ZStack {
                if model.usesAppleLogo {
                    // Apple logo uses SF Symbol
                    Image(systemName: "apple.logo")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: model.brandColorHex) ?? .gray)
                } else {
                    // Text badges (NVIDIA, OpenAI)
                    Text(model.brandName)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: model.brandColorHex) ?? .gray)
                        )
                }
            }
            .frame(width: 48, height: 18, alignment: .center)

            // Title + technical name
            VStack(alignment: .leading, spacing: 2) {
                Text(model.humanReadableName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? self.theme.palette.primaryText : .secondary)
                if self.showAdvancedSpeechInfo {
                    Text(model.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Action area (right side)
            if (self.asr.isDownloadingModel || self.asr.isLoadingModel) && isActive && !self.asr.isAsrReady {
                VStack(alignment: .trailing, spacing: 4) {
                    if let progress = self.asr.downloadProgress, self.asr.isDownloadingModel {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .frame(width: 90)
                        Text("\(Int(progress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .controlSize(.mini)
                        Text(self.asr.isLoadingModel ? "Loading…" : "Downloading…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if model.isInstalled {
                HStack(spacing: 8) {
                    if isActive {
                        let isLoading = (self.asr.isLoadingModel || self.asr.isDownloadingModel) && !self.asr.isAsrReady
                        Text(isLoading ? "Loading…" : "Active")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(isLoading ? .orange.opacity(0.25) : .green.opacity(0.25)))
                            .foregroundStyle(isLoading ? .orange : .green)
                    } else {
                        Button("Activate") {
                            self.activateSpeechModel(model)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.green)
                        .fontWeight(.semibold)
                        .shadow(color: .green.opacity(0.35), radius: 4, x: 0, y: 1)
                        .disabled(self.asr.isRunning)
                    }

                    if !model.usesAppleLogo {
                        Button {
                            self.deleteSpeechModel(model)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 15))
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .disabled(self.asr.isRunning)
                    }
                }
            } else {
                Button("Download") {
                    self.previewSpeechModel = model
                    self.downloadSpeechModel(model)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.blue)
                .disabled(self.asr.isRunning)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? .white.opacity(0.05) : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? .white.opacity(0.25) : .white.opacity(0.05), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isActive ? .green.opacity(0.9) : .clear, lineWidth: 2)
                )
        )
        .onTapGesture {
            self.previewSpeechModel = model
        }
        .opacity(self.asr.isRunning ? 0.6 : 1.0)
        .allowsHitTesting(!self.asr.isRunning)
    }

    private func activateSpeechModel(_ model: SettingsStore.SpeechModel) {
        guard !self.asr.isRunning else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            SettingsStore.shared.selectedSpeechModel = model
            self.previewSpeechModel = model
            self.setSelectedSpeechProvider(model.provider)
        }
        self.asr.resetTranscriptionProvider()
        Task {
            do {
                try await self.asr.ensureAsrReady()
            } catch {
                DebugLogger.shared.error("Failed to prepare model after activation: \(error)", source: "AISettingsView")
            }
        }
    }

    private func downloadSpeechModel(_ model: SettingsStore.SpeechModel) {
        guard !self.asr.isRunning else { return }
        let previousActive = SettingsStore.shared.selectedSpeechModel

        Task {
            let shouldRestore = previousActive != model
            let initialProvider = self.selectedSpeechProvider
            await MainActor.run {
                if shouldRestore {
                    self.suppressSpeechProviderSync = true
                }
                SettingsStore.shared.selectedSpeechModel = model
                self.asr.resetTranscriptionProvider()
            }

            defer {
                Task { @MainActor in
                    guard shouldRestore else { return }
                    if SettingsStore.shared.selectedSpeechModel == model {
                        self.skipNextSpeechModelSync = true
                        SettingsStore.shared.selectedSpeechModel = previousActive
                        self.asr.resetTranscriptionProvider()
                    }
                    if self.selectedSpeechProvider == initialProvider {
                        self.previewSpeechModel = model
                    }
                    self.suppressSpeechProviderSync = false
                }
            }

            await self.downloadModels()
        }
    }

    private func deleteSpeechModel(_ model: SettingsStore.SpeechModel) {
        guard !self.asr.isRunning else { return }
        let previousActive = SettingsStore.shared.selectedSpeechModel

        Task {
            let shouldRestore = previousActive != model
            let initialProvider = self.selectedSpeechProvider
            await MainActor.run {
                if shouldRestore {
                    self.suppressSpeechProviderSync = true
                }
                SettingsStore.shared.selectedSpeechModel = model
                self.asr.resetTranscriptionProvider()
            }

            defer {
                Task { @MainActor in
                    guard shouldRestore else { return }
                    self.skipNextSpeechModelSync = true
                    SettingsStore.shared.selectedSpeechModel = previousActive
                    self.asr.resetTranscriptionProvider()
                    if self.selectedSpeechProvider == initialProvider {
                        self.previewSpeechModel = model
                    }
                    self.suppressSpeechProviderSync = false
                }
            }

            await self.deleteModels()
        }
    }

    private func isActiveSpeechModel(_ model: SettingsStore.SpeechModel) -> Bool {
        SettingsStore.shared.selectedSpeechModel == model
    }

    /// Returns the appropriate description text for the currently selected speech model
    private var modelDescriptionText: String {
        let model = SettingsStore.shared.selectedSpeechModel
        switch model {
        case .appleSpeech:
            return "Apple Speech (Legacy) uses on-device recognition. No download required, works on Intel and Apple Silicon."
        case .appleSpeechAnalyzer:
            return "Apple Speech uses advanced on-device recognition with fast, accurate transcription. Requires macOS 26+."
        case .parakeetTDT:
            return "Parakeet TDT v3 uses CoreML and Neural Engine for fastest transcription (25 languages) on Apple Silicon."
        case .parakeetTDTv2:
            return "Parakeet TDT v2 is an English-only model optimized for accuracy and consistency on Apple Silicon."
        default:
            return "Whisper models support 99 languages and work on any Mac."
        }
    }

    private var modelStatusView: some View {
        HStack(spacing: 12) {
            if (self.asr.isDownloadingModel || self.asr.isLoadingModel) && !self.asr.isAsrReady {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(self.asr.isLoadingModel ? "Loading model…" : "Downloading…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if self.asr.isAsrReady {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                Text("Ready").font(.caption).foregroundStyle(.secondary)

                Button(action: { Task { await self.deleteModels() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Delete")
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            } else if self.asr.modelsExistOnDisk {
                Image(systemName: "doc.fill").foregroundStyle(self.theme.palette.accent).font(.caption)
                Text("Cached").font(.caption).foregroundStyle(.secondary)

                Button(action: { Task { await self.deleteModels() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Delete")
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: { Task { await self.downloadModels() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Download")
                    }
                    .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(.ultraThinMaterial.opacity(0.3))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1), lineWidth: 1)))
    }

    private var fillerWordsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remove Filler Words").font(.body)
                    Text("Automatically remove filler sounds like 'um', 'uh', 'er' from transcriptions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: self.$removeFillerWordsEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: self.removeFillerWordsEnabled) { _, newValue in
                        SettingsStore.shared.removeFillerWordsEnabled = newValue
                    }
            }

            if self.removeFillerWordsEnabled {
                FillerWordsEditor()
            }
        }
    }

    // MARK: - Model Download/Delete

    private func downloadModels() async {
        do {
            try await self.asr.ensureAsrReady()
        } catch {
            DebugLogger.shared.error("Failed to download models: \(error)", source: "AISettingsView")
        }
    }

    private func deleteModels() async {
        do {
            try await self.asr.clearModelCache()
        } catch {
            DebugLogger.shared.error("Failed to delete models: \(error)", source: "AISettingsView")
        }
    }

    // MARK: - Helper Functions

    private func setSelectedSpeechProvider(_ provider: SettingsStore.SpeechModel.Provider) {
        self.selectedSpeechProvider = provider
    }

    private func providerKey(for providerID: String) -> String {
        // Built-in providers use their ID directly
        if ModelRepository.shared.isBuiltIn(providerID) { return providerID }
        // Custom providers get "custom:" prefix (if not already present)
        if providerID.hasPrefix("custom:") { return providerID }
        return providerID.isEmpty ? self.currentProvider : "custom:\(providerID)"
    }

    private func providerDisplayName(for providerID: String) -> String {
        switch providerID {
        case "openai": return "OpenAI"
        case "groq": return "Groq"
        case "apple-intelligence": return "Apple Intelligence"
        default:
            return self.savedProviders.first(where: { $0.id == providerID })?.name ?? providerID.capitalized
        }
    }

    private func saveProviderAPIKeys() {
        SettingsStore.shared.providerAPIKeys = self.providerAPIKeys
    }

    private func updateCurrentProvider() {
        let url = self.openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.contains("openai.com") { self.currentProvider = "openai"; return }
        if url.contains("groq.com") { self.currentProvider = "groq"; return }
        self.currentProvider = self.providerKey(for: self.selectedProviderID)
    }

    private func saveSavedProviders() {
        SettingsStore.shared.savedProviders = self.savedProviders
    }

    private func isLocalEndpoint(_ urlString: String) -> Bool {
        return ModelRepository.shared.isLocalEndpoint(urlString)
    }

    private func hasReasoningConfigForCurrentModel() -> Bool {
        let pKey = self.providerKey(for: self.selectedProviderID)
        if SettingsStore.shared.hasCustomReasoningConfig(forModel: self.selectedModel, provider: pKey) {
            if let config = SettingsStore.shared.getReasoningConfig(forModel: selectedModel, provider: pKey) {
                return config.isEnabled
            }
        }
        return SettingsStore.shared.isReasoningModel(self.selectedModel)
    }

    private func addNewModel() {
        guard !self.newModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let modelName = self.newModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = self.providerKey(for: self.selectedProviderID)

        var list = self.availableModelsByProvider[key] ?? self.availableModels
        if !list.contains(modelName) {
            list.append(modelName)
            self.availableModelsByProvider[key] = list
            SettingsStore.shared.availableModelsByProvider = self.availableModelsByProvider

            if let providerIndex = savedProviders.firstIndex(where: { $0.id == selectedProviderID }) {
                let updatedProvider = SettingsStore.SavedProvider(
                    id: self.savedProviders[providerIndex].id,
                    name: self.savedProviders[providerIndex].name,
                    baseURL: self.savedProviders[providerIndex].baseURL,
                    models: list
                )
                self.savedProviders[providerIndex] = updatedProvider
                self.saveSavedProviders()
            }

            self.availableModels = list
            self.selectedModel = modelName
            self.selectedModelByProvider[key] = modelName
            SettingsStore.shared.selectedModelByProvider = self.selectedModelByProvider
        }

        self.showingAddModel = false
        self.newModelName = ""
    }

    // MARK: - Keychain Access Helpers

    private enum KeychainAccessCheckResult {
        case granted
        case denied(OSStatus)
    }

    private func handleAPIKeyButtonTapped() {
        switch self.probeKeychainAccess() {
        case .granted:
            self.newProviderApiKey = self.providerAPIKeys[self.currentProvider] ?? ""
            self.showAPIKeyEditor = true
        case let .denied(status):
            self.keychainPermissionMessage = self.keychainPermissionExplanation(for: status)
            self.showKeychainPermissionAlert = true
        }
    }

    private func probeKeychainAccess() -> KeychainAccessCheckResult {
        let service = "com.fluidvoice.provider-api-keys"
        let account = "fluidApiKeys"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        var readQuery = query
        readQuery[kSecReturnData as String] = kCFBooleanTrue
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne

        let readStatus = SecItemCopyMatching(readQuery as CFDictionary, nil)
        switch readStatus {
        case errSecSuccess:
            return .granted
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            addQuery[kSecValueData as String] = (try? JSONEncoder().encode([String: String]())) ?? Data()

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus == errSecSuccess {
                SecItemDelete(query as CFDictionary)
            }

            switch addStatus {
            case errSecSuccess, errSecDuplicateItem:
                return .granted
            case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled:
                return .denied(addStatus)
            default:
                return .denied(addStatus)
            }
        case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled:
            return .denied(readStatus)
        default:
            return .denied(readStatus)
        }
    }

    private func keychainPermissionExplanation(for status: OSStatus) -> String {
        var message = "FluidVoice stores provider API keys securely in your macOS Keychain but does not currently have permission to access it."
        if let detail = SecCopyErrorMessageString(status, nil) as String? {
            message += "\n\nmacOS reported: \(detail) (\(status))"
        }
        message += "\n\nClick \"Always Allow\" when the Keychain prompt appears, or open Keychain Access > login > Passwords, locate the FluidVoice entry, and grant access."
        return message
    }

    @MainActor
    private func presentKeychainAccessAlert(message: String) {
        let msg = message.isEmpty
            ? "FluidVoice stores provider API keys securely in your macOS Keychain. Please grant access by choosing \"Always Allow\" when prompted."
            : message

        let alert = NSAlert()
        alert.messageText = "Keychain Access Required"
        alert.informativeText = msg
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Keychain Access")
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.keychainaccess") {
                NSWorkspace.shared.openApplication(
                    at: appURL,
                    configuration: NSWorkspace.OpenConfiguration(),
                    completionHandler: nil
                )
            }
        }
    }

    // MARK: - API Connection Testing

    private func testAPIConnection() async {
        guard !self.isTestingConnection else { return }

        let apiKey = self.providerAPIKeys[self.currentProvider] ?? ""
        let baseURL = self.openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let isLocal = self.isLocalEndpoint(baseURL)

        if isLocal {
            guard !baseURL.isEmpty else {
                await MainActor.run {
                    self.connectionStatus = .failed
                    self.connectionErrorMessage = "Base URL is required"
                }
                return
            }
        } else {
            guard !apiKey.isEmpty, !baseURL.isEmpty else {
                await MainActor.run {
                    self.connectionStatus = .failed
                    self.connectionErrorMessage = "API key and base URL are required"
                }
                return
            }
        }

        await MainActor.run {
            self.isTestingConnection = true
            self.connectionStatus = .testing
            self.connectionErrorMessage = ""
        }

        do {
            let endpoint = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let fullURL: String
            if endpoint.contains("/chat/completions") || endpoint.contains("/api/chat") || endpoint
                .contains("/api/generate")
            {
                fullURL = endpoint
            } else {
                fullURL = endpoint + "/chat/completions"
            }

            // Debug logging to diagnose test failures
            DebugLogger.shared.debug("testAPIConnection: provider=\(self.selectedProviderID), model=\(self.selectedModel), baseURL=\(endpoint), fullURL=\(fullURL)", source: "AISettingsView")

            guard let url = URL(string: fullURL) else {
                await MainActor.run {
                    self.connectionStatus = .failed
                    self.connectionErrorMessage = "Invalid Base URL format"
                }
                return
            }

            let provKey = self.providerKey(for: self.selectedProviderID)
            let reasoningConfig = SettingsStore.shared.getReasoningConfig(forModel: self.selectedModel, provider: provKey)

            let usesMaxCompletionTokens = SettingsStore.shared.isReasoningModel(self.selectedModel)

            var requestDict: [String: Any] = [
                "model": selectedModel,
                "messages": [["role": "user", "content": "test"]],
            ]

            if usesMaxCompletionTokens {
                requestDict["max_completion_tokens"] = 50
            } else {
                requestDict["max_tokens"] = 50
            }

            if let config = reasoningConfig, config.isEnabled {
                if config.parameterName == "enable_thinking" {
                    requestDict[config.parameterName] = config.parameterValue == "true"
                } else {
                    requestDict[config.parameterName] = config.parameterValue
                }
            }

            guard let jsonData = try? JSONSerialization.data(withJSONObject: requestDict, options: []) else {
                await MainActor.run {
                    self.connectionStatus = .failed
                    self.connectionErrorMessage = "Failed to encode test request"
                }
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 30

            if !isLocal {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }

            request.httpBody = jsonData

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if (200...299).contains(httpResponse.statusCode) {
                    await MainActor.run {
                        self.connectionStatus = .success
                        self.connectionErrorMessage = ""
                    }
                } else {
                    var errorMessage = "HTTP \(httpResponse.statusCode)"

                    if let responseBody = String(data: data, encoding: .utf8),
                       let jsonData = responseBody.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
                    {
                        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
                            errorMessage = message
                        } else if let message = json["message"] as? String {
                            errorMessage = message
                        }
                    }

                    await MainActor.run {
                        self.connectionStatus = .failed
                        self.connectionErrorMessage = errorMessage
                    }
                }
            }
        } catch let urlError as URLError {
            var errorMessage: String
            switch urlError.code {
            case .timedOut: errorMessage = "Request timed out - server not responding"
            case .cannotConnectToHost: errorMessage = "Cannot connect to host - check URL"
            case .notConnectedToInternet: errorMessage = "No internet connection"
            default: errorMessage = urlError.localizedDescription
            }

            await MainActor.run {
                connectionStatus = .failed
                connectionErrorMessage = errorMessage
            }
        } catch {
            await MainActor.run {
                self.connectionStatus = .failed
                self.connectionErrorMessage = error.localizedDescription
            }
        }

        await MainActor.run {
            self.isTestingConnection = false
        }
    }

    // MARK: - AI Configuration Card

    private var aiConfigurationCard: some View {
        VStack(spacing: 14) {
            ThemedCard(style: .prominent, hoverEffect: false) {
                VStack(alignment: .leading, spacing: 10) {
                    // Header
                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundStyle(self.theme.palette.accent)
                            Text("AI Enhancement")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        Spacer()
                        Toggle("", isOn: self.$enableAIProcessing)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    // Streaming Toggle
                    if self.enableAIProcessing && self.selectedProviderID != "apple-intelligence" {
                        HStack(spacing: 20) {
                            Toggle("Enable Streaming", isOn: Binding(
                                get: { SettingsStore.shared.enableAIStreaming },
                                set: { SettingsStore.shared.enableAIStreaming = $0 }
                            ))
                            .toggleStyle(.checkbox)

                            Toggle("Show Thinking Tokens", isOn: Binding(
                                get: { SettingsStore.shared.showThinkingTokens },
                                set: { SettingsStore.shared.showThinkingTokens = $0 }
                            ))
                            .toggleStyle(.checkbox)
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .padding(.leading, 4)
                        .padding(.top, -2)
                    }

                    // API Key Warning
                    if self.enableAIProcessing && self.selectedProviderID != "apple-intelligence" &&
                        !self.isLocalEndpoint(self.openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) &&
                        (self.providerAPIKeys[self.currentProvider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    {
                        self.apiKeyWarningView
                    }

                    // Help Section
                    if self.showHelp { self.helpSectionView }

                    // Provider/Model Configuration (only shown when AI Enhancement is enabled)
                    if self.enableAIProcessing {
                        HStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "key.fill")
                                    .font(.title3)
                                    .foregroundStyle(self.theme.palette.accent)
                                Text("API Configuration")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }

                            // Compatibility Badge
                            if self.selectedProviderID == "apple-intelligence" {
                                HStack(spacing: 4) {
                                    Image(systemName: "apple.logo").font(.caption2)
                                    Text("On-device").font(.caption)
                                }
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.quaternary.opacity(0.5)))
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.seal.fill").font(.caption2)
                                    Text("OpenAI Compatible").font(.caption)
                                }
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.quaternary.opacity(0.5)))
                            }

                            Spacer()

                            Button(action: { self.showHelp.toggle() }) {
                                Image(systemName: self.showHelp ? "questionmark.circle.fill" : "questionmark.circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(self.theme.palette.accent.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                        }

                        self.providerConfigurationSection

                        self.advancedSettingsCard
                    }
                }
                .padding(14)
            }
            .modifier(CardAppearAnimation(delay: 0.1, appear: self.$appear))
        }
    }

    private var apiKeyWarningView: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 16))
            Text("API key required for AI enhancement to work")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.orange)
            Spacer()
        }
        .padding(12)
        .background(.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.orange.opacity(0.3), lineWidth: 1))
        .padding(.horizontal, 4)
    }

    private var helpSectionView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                Text("Quick Start Guide").font(.subheadline).fontWeight(.semibold)
            }
            VStack(alignment: .leading, spacing: 6) {
                self.helpStep("1", "Enable AI enhancement if needed")
                self.helpStep("2", "Add/choose any provider of your choice along with its API key")
                self.helpStep("3", "Add/choose any good model of your liking")
                self.helpStep("4", "If it's OpenAI compatible endpoint, then update the base URL")
                self.helpStep("5", "Once everything is set, click verify to check if the connection works")
            }
        }
        .padding(14)
        .background(self.theme.palette.accent.opacity(0.08))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(self.theme.palette.accent.opacity(0.2), lineWidth: 1))
        .padding(.horizontal, 4)
        .transition(.opacity)
    }

    private func helpStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.caption).fontWeight(.semibold).frame(width: 16, alignment: .trailing)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var providerConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            self.providerPickerRow

            if self.showingEditProvider { self.editProviderSection }

            if self.selectedProviderID == "apple-intelligence" { self.appleIntelligenceBadge }

            // API Key Management
            if self.selectedProviderID != "apple-intelligence" {
                HStack(spacing: 8) {
                    Button(action: { self.handleAPIKeyButtonTapped() }) {
                        Label("Add or Modify API Key", systemImage: "key.fill")
                            .labelStyle(.titleAndIcon).font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(self.theme.palette.accent.opacity(0.8))

                    // Get API Key / Download button for built-in providers
                    if let websiteInfo = ModelRepository.shared.providerWebsiteURL(for: self.selectedProviderID),
                       let url = URL(string: websiteInfo.url)
                    {
                        Button(action: { NSWorkspace.shared.open(url) }) {
                            Label(websiteInfo.label, systemImage: websiteInfo.label.contains("Download") ? "arrow.down.circle.fill" : (websiteInfo.label.contains("Guide") ? "book.fill" : "link"))
                                .labelStyle(.titleAndIcon).font(.caption)
                        }
                        .buttonStyle(GlassButtonStyle())
                    }
                }
            }

            // Model Row
            if self.selectedProviderID == "apple-intelligence" {
                self.appleIntelligenceModelRow
            } else {
                self.standardModelRow
                if self.showingAddModel { self.addModelSection }
                if self.showingReasoningConfig { self.reasoningConfigSection }
            }

            // Connection Test
            if self.selectedProviderID != "apple-intelligence" {
                self.connectionTestSection
                if self.showingSaveProvider { self.addProviderSection }
            }
        }
        .padding(.horizontal, 4)
    }

    private var providerPickerRow: some View {
        HStack(spacing: 12) {
            HStack {
                Text("Provider:").fontWeight(.medium)
            }
            .frame(width: 90, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(LinearGradient(colors: [self.theme.palette.accent.opacity(0.15), self.theme.palette.accent.opacity(0.05)], startPoint: .leading, endPoint: .trailing))
            .cornerRadius(6)

            // Searchable provider picker with bounded popover
            SearchableProviderPicker(
                builtInProviders: self.builtInProvidersList,
                savedProviders: self.savedProviders,
                selectedProviderID: Binding(
                    get: { self.selectedProviderID },
                    set: { newValue in
                        self.selectedProviderID = newValue
                        self.handleProviderChange(newValue)
                    }
                )
            )

            // Edit button for all providers (including built-in)
            if self.selectedProviderID != "apple-intelligence" {
                Button(action: { self.startEditingProvider() }) {
                    HStack(spacing: 4) { Image(systemName: "pencil"); Text("Edit") }.font(.caption)
                }
                .buttonStyle(CompactButtonStyle())
            }

            // Delete button only for custom providers
            if !ModelRepository.shared.isBuiltIn(self.selectedProviderID) {
                Button(action: { self.deleteCurrentProvider() }) {
                    HStack(spacing: 4) { Image(systemName: "trash"); Text("Delete") }.font(.caption).foregroundStyle(.red)
                }
                .buttonStyle(CompactButtonStyle())
            }

            Button("+ Add Provider") {
                self.showingSaveProvider = true
                self.newProviderName = ""; self.newProviderBaseURL = ""; self.newProviderApiKey = ""; self.newProviderModels = ""
            }
            .buttonStyle(CompactButtonStyle())
        }
    }

    private var builtInProvidersList: [(id: String, name: String)] {
        ModelRepository.shared.builtInProvidersList(
            includeAppleIntelligence: true,
            appleIntelligenceAvailable: AppleIntelligenceService.isAvailable
        )
    }

    private func handleProviderChange(_ newValue: String) {
        // Handle Apple Intelligence specially (no base URL)
        if newValue == "apple-intelligence" {
            self.openAIBaseURL = ""
            self.updateCurrentProvider()
            self.availableModels = ["System Model"]
            self.selectedModel = "System Model"
            return
        }

        // Check if it's a built-in provider
        if ModelRepository.shared.isBuiltIn(newValue) {
            self.openAIBaseURL = ModelRepository.shared.defaultBaseURL(for: newValue)
            self.updateCurrentProvider()
            let key = newValue
            self.availableModels = self.availableModelsByProvider[key] ?? ModelRepository.shared.defaultModels(for: key)
            // If no models available, clear selection; otherwise use saved or first
            if self.availableModels.isEmpty {
                self.selectedModel = ""
            } else {
                self.selectedModel = self.selectedModelByProvider[key] ?? self.availableModels.first ?? ""
            }
            return
        }

        // Handle saved/custom providers
        if let provider = savedProviders.first(where: { $0.id == newValue }) {
            self.openAIBaseURL = provider.baseURL
            self.updateCurrentProvider()
            let key = self.providerKey(for: newValue)
            self.availableModels = provider.models.isEmpty ? (self.availableModelsByProvider[key] ?? []) : provider.models
            self.selectedModel = self.selectedModelByProvider[key] ?? self.availableModels.first ?? self.selectedModel
        }
    }

    private func startEditingProvider() {
        // Handle built-in providers
        if ModelRepository.shared.isBuiltIn(self.selectedProviderID) {
            self.editProviderName = ModelRepository.shared.displayName(for: self.selectedProviderID)
            self.editProviderBaseURL = self.openAIBaseURL // Use current URL (may have been customized)
            self.showingEditProvider = true
            return
        }
        // Handle saved/custom providers
        if let provider = savedProviders.first(where: { $0.id == selectedProviderID }) {
            self.editProviderName = provider.name
            self.editProviderBaseURL = provider.baseURL
            self.showingEditProvider = true
        }
    }

    private func deleteCurrentProvider() {
        self.savedProviders.removeAll { $0.id == self.selectedProviderID }
        self.saveSavedProviders()
        let key = self.providerKey(for: self.selectedProviderID)
        self.availableModelsByProvider.removeValue(forKey: key)
        self.selectedModelByProvider.removeValue(forKey: key)
        self.providerAPIKeys.removeValue(forKey: key)
        self.saveProviderAPIKeys()
        SettingsStore.shared.availableModelsByProvider = self.availableModelsByProvider
        SettingsStore.shared.selectedModelByProvider = self.selectedModelByProvider
        // Reset to OpenAI
        self.selectedProviderID = "openai"
        self.openAIBaseURL = ModelRepository.shared.defaultBaseURL(for: "openai")
        self.updateCurrentProvider()
        // Use fetched models if available, fall back to defaults (same logic as handleProviderChange)
        self.availableModels = self.availableModelsByProvider["openai"] ?? ModelRepository.shared.defaultModels(for: "openai")
        self.selectedModel = self.selectedModelByProvider["openai"] ?? self.availableModels.first ?? ""
    }

    private var editProviderSection: some View {
        VStack(spacing: 12) {
            HStack { Text("Edit Provider").font(.headline).fontWeight(.semibold); Spacer() }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name").font(.caption).foregroundStyle(.secondary)
                    TextField("Provider name", text: self.$editProviderName).textFieldStyle(.roundedBorder).frame(width: 200)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Base URL").font(.caption).foregroundStyle(.secondary)
                    TextField("e.g., http://localhost:11434/v1", text: self.$editProviderBaseURL).textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                }
            }
            HStack(spacing: 8) {
                Button("Save") { self.saveEditedProvider() }.buttonStyle(GlassButtonStyle())
                    .disabled(self.editProviderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || self.editProviderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel") { self.showingEditProvider = false; self.editProviderName = ""; self.editProviderBaseURL = "" }.buttonStyle(GlassButtonStyle())
            }
        }
        .padding(12)
        .background(self.theme.palette.cardBackground.opacity(0.5))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(self.theme.palette.accent.opacity(0.3), lineWidth: 1))
        .padding(.vertical, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func saveEditedProvider() {
        let name = self.editProviderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = self.editProviderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !base.isEmpty else { return }

        // For built-in providers, we just update the base URL (name is not editable)
        if ModelRepository.shared.isBuiltIn(self.selectedProviderID) {
            self.openAIBaseURL = base
            self.updateCurrentProvider()
            self.showingEditProvider = false
            self.editProviderName = ""; self.editProviderBaseURL = ""
            return
        }

        // For saved/custom providers, update the full provider record
        if let providerIndex = savedProviders.firstIndex(where: { $0.id == selectedProviderID }) {
            let oldProvider = self.savedProviders[providerIndex]
            let updatedProvider = SettingsStore.SavedProvider(id: oldProvider.id, name: name, baseURL: base, models: oldProvider.models)
            self.savedProviders[providerIndex] = updatedProvider
            self.saveSavedProviders()
            self.openAIBaseURL = base
            self.updateCurrentProvider()
        }
        self.showingEditProvider = false
        self.editProviderName = ""; self.editProviderBaseURL = ""
    }

    private var appleIntelligenceBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "apple.logo").font(.system(size: 14))
            Text("On-Device").fontWeight(.medium)
            Text("•").foregroundStyle(.secondary)
            Image(systemName: "lock.shield.fill").font(.system(size: 12))
            Text("Private").fontWeight(.medium)
        }
        .font(.caption).foregroundStyle(.green)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.green.opacity(0.15))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                .green.opacity(0.3),
                lineWidth: 1
            )))
    }

    private var appleIntelligenceModelRow: some View {
        HStack(spacing: 12) {
            HStack { Text("Model:").fontWeight(.medium) }
                .frame(width: 90, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(LinearGradient(colors: [self.theme.palette.accent.opacity(0.15), self.theme.palette.accent.opacity(0.05)], startPoint: .leading, endPoint: .trailing))
                .cornerRadius(6)
            Text("System Language Model").foregroundStyle(.secondary).font(.system(.body))
            Spacer()
        }
    }

    private var standardModelRow: some View {
        HStack(spacing: 12) {
            HStack { Text("Model:").fontWeight(.medium) }
                .frame(width: 90, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(LinearGradient(colors: [self.theme.palette.accent.opacity(0.15), self.theme.palette.accent.opacity(0.05)], startPoint: .leading, endPoint: .trailing))
                .cornerRadius(6)

            // Searchable model picker with refresh button
            SearchableModelPicker(
                models: self.availableModels,
                selectedModel: self.$selectedModel,
                onRefresh: { await self.fetchModelsForCurrentProvider() },
                isRefreshing: self.isFetchingModels
            )

            if !ModelRepository.shared.isBuiltIn(self.selectedProviderID) {
                Button(action: { self.deleteSelectedModel() }) {
                    HStack(spacing: 4) { Image(systemName: "trash"); Text("Delete") }.font(.caption).foregroundStyle(.red)
                }
                .buttonStyle(CompactButtonStyle())
            }

            if !self.showingAddModel {
                Button("+ Add Model") { self.showingAddModel = true; self.newModelName = "" }.buttonStyle(CompactButtonStyle())
            }

            Button(action: { self.openReasoningConfig() }) {
                HStack(spacing: 4) {
                    Image(systemName: self.hasReasoningConfigForCurrentModel() ? "brain.fill" : "brain")
                    Text("Reasoning")
                }
                .font(.caption)
                .foregroundStyle(self.hasReasoningConfigForCurrentModel() ? self.theme.palette.accent : .secondary)
            }
            .buttonStyle(CompactButtonStyle())
        }
    }

    private func deleteSelectedModel() {
        let key = self.providerKey(for: self.selectedProviderID)
        var list = self.availableModelsByProvider[key] ?? self.availableModels
        list.removeAll { $0 == self.selectedModel }
        if list.isEmpty { list = ModelRepository.shared.defaultModels(for: key) }
        self.availableModelsByProvider[key] = list
        SettingsStore.shared.availableModelsByProvider = self.availableModelsByProvider

        if let providerIndex = savedProviders.firstIndex(where: { $0.id == selectedProviderID }) {
            let updatedProvider = SettingsStore.SavedProvider(id: self.savedProviders[providerIndex].id, name: self.savedProviders[providerIndex].name, baseURL: self.savedProviders[providerIndex].baseURL, models: list)
            self.savedProviders[providerIndex] = updatedProvider
            self.saveSavedProviders()
        }

        self.availableModels = list
        self.selectedModel = list.first ?? ""
        self.selectedModelByProvider[key] = self.selectedModel
        SettingsStore.shared.selectedModelByProvider = self.selectedModelByProvider
    }

    private func fetchModelsForCurrentProvider() async {
        self.isFetchingModels = true
        self.fetchModelsError = nil
        defer { self.isFetchingModels = false }

        let baseURL = self.openAIBaseURL
        let key = self.providerKey(for: self.selectedProviderID)
        let apiKey = self.providerAPIKeys[key] ?? self.providerAPIKeys[self.selectedProviderID]

        do {
            let models = try await ModelRepository.shared.fetchModels(
                for: self.selectedProviderID,
                baseURL: baseURL,
                apiKey: apiKey
            )

            // Update state on main thread
            await MainActor.run {
                if models.isEmpty {
                    // Keep existing models if fetch returned empty
                    self.fetchModelsError = "No models returned from API"
                } else {
                    self.availableModels = models
                    self.availableModelsByProvider[key] = models
                    SettingsStore.shared.availableModelsByProvider = self.availableModelsByProvider

                    if let providerIndex = self.savedProviders.firstIndex(where: { $0.id == self.selectedProviderID }) {
                        let updatedProvider = SettingsStore.SavedProvider(
                            id: self.savedProviders[providerIndex].id,
                            name: self.savedProviders[providerIndex].name,
                            baseURL: self.savedProviders[providerIndex].baseURL,
                            models: models
                        )
                        self.savedProviders[providerIndex] = updatedProvider
                        self.saveSavedProviders()
                    }

                    // Select first model if current selection not in list
                    if !models.contains(self.selectedModel) {
                        self.selectedModel = models.first ?? ""
                        self.selectedModelByProvider[key] = self.selectedModel
                        SettingsStore.shared.selectedModelByProvider = self.selectedModelByProvider
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.fetchModelsError = error.localizedDescription
            }
        }
    }

    private func openReasoningConfig() {
        let pKey = self.providerKey(for: self.selectedProviderID)
        if let config = SettingsStore.shared.getReasoningConfig(forModel: selectedModel, provider: pKey) {
            self.editingReasoningParamName = config.parameterName
            self.editingReasoningParamValue = config.parameterValue
            self.editingReasoningEnabled = config.isEnabled
        } else {
            let modelLower = self.selectedModel.lowercased()
            if modelLower.hasPrefix("gpt-5") || modelLower.hasPrefix("o1") || modelLower.hasPrefix("o3") || modelLower.contains("gpt-oss") {
                self.editingReasoningParamName = "reasoning_effort"; self.editingReasoningParamValue = "low"; self.editingReasoningEnabled = true
            } else if modelLower.contains("deepseek"), modelLower.contains("reasoner") {
                self.editingReasoningParamName = "enable_thinking"; self.editingReasoningParamValue = "true"; self.editingReasoningEnabled = true
            } else {
                self.editingReasoningParamName = "reasoning_effort"; self.editingReasoningParamValue = "low"; self.editingReasoningEnabled = false
            }
        }
        self.showingReasoningConfig = true
    }

    private var addModelSection: some View {
        HStack(spacing: 8) {
            TextField("Enter model name", text: self.$newModelName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if !self.newModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { self.addNewModel() } }
            Button("Add") { self.addNewModel() }.buttonStyle(CompactButtonStyle())
                .disabled(self.newModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel") { self.showingAddModel = false; self.newModelName = "" }.buttonStyle(CompactButtonStyle())
        }
        .padding(.leading, 122)
    }

    private var reasoningConfigSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "brain.head.profile").foregroundStyle(self.theme.palette.accent)
                Text("Reasoning Config for \(self.selectedModel)").font(.caption).fontWeight(.semibold)
                Spacer()
            }

            Toggle("Enable reasoning parameter", isOn: self.$editingReasoningEnabled).toggleStyle(.switch).font(.caption)

            if self.editingReasoningEnabled {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Parameter Name").font(.caption2).foregroundStyle(.secondary)
                        Picker("", selection: Binding(
                            get: {
                                // Map current value to picker options
                                if self.editingReasoningParamName == "reasoning_effort" {
                                    return "reasoning_effort"
                                } else if self.editingReasoningParamName == "enable_thinking" {
                                    return "enable_thinking"
                                } else {
                                    return "custom"
                                }
                            },
                            set: { newValue in
                                if newValue == "custom" {
                                    // Keep the current value for custom editing
                                    if self.editingReasoningParamName == "reasoning_effort" || self.editingReasoningParamName == "enable_thinking" {
                                        self.editingReasoningParamName = ""
                                    }
                                } else {
                                    self.editingReasoningParamName = newValue
                                }
                            }
                        )) {
                            Text("reasoning_effort").tag("reasoning_effort")
                            Text("enable_thinking").tag("enable_thinking")
                            Text("Custom...").tag("custom")
                        }
                        .pickerStyle(.menu).labelsHidden().frame(width: 150)
                    }

                    // Show TextField for custom parameter name
                    if self.editingReasoningParamName != "reasoning_effort" && self.editingReasoningParamName != "enable_thinking" {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Custom Name").font(.caption2).foregroundStyle(.secondary)
                            TextField("e.g., thinking_budget", text: self.$editingReasoningParamName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 150)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Value").font(.caption2).foregroundStyle(.secondary)
                        if self.editingReasoningParamName == "reasoning_effort" {
                            Picker("", selection: self.$editingReasoningParamValue) {
                                Text("none").tag("none"); Text("minimal").tag("minimal"); Text("low").tag("low"); Text("medium").tag("medium"); Text("high").tag("high")
                            }
                            .pickerStyle(.menu).labelsHidden().frame(width: 100)
                        } else if self.editingReasoningParamName == "enable_thinking" {
                            Picker("", selection: self.$editingReasoningParamValue) {
                                Text("true").tag("true"); Text("false").tag("false")
                            }
                            .pickerStyle(.menu).labelsHidden().frame(width: 100)
                        } else {
                            // Free-form value for custom parameters
                            TextField("value", text: self.$editingReasoningParamValue)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button("Save") { self.saveReasoningConfig() }.buttonStyle(GlassButtonStyle())
                Button("Cancel") { self.showingReasoningConfig = false }.buttonStyle(CompactButtonStyle())
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(self.theme.palette.accent.opacity(0.08)).overlay(RoundedRectangle(cornerRadius: 8).stroke(self.theme.palette.accent.opacity(0.2), lineWidth: 1)))
        .padding(.leading, 122)
        .transition(.opacity)
    }

    private func saveReasoningConfig() {
        let pKey = self.providerKey(for: self.selectedProviderID)
        if self.editingReasoningEnabled {
            let config = SettingsStore.ModelReasoningConfig(parameterName: self.editingReasoningParamName, parameterValue: self.editingReasoningParamValue, isEnabled: true)
            SettingsStore.shared.setReasoningConfig(config, forModel: self.selectedModel, provider: pKey)
        } else {
            let config = SettingsStore.ModelReasoningConfig(parameterName: "", parameterValue: "", isEnabled: false)
            SettingsStore.shared.setReasoningConfig(config, forModel: self.selectedModel, provider: pKey)
        }
        self.showingReasoningConfig = false
    }

    private var connectionTestSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(action: { Task { await self.testAPIConnection() } }) {
                    Text(self.isTestingConnection ? "Verifying..." : "Verify Connection").font(.caption).fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(self.theme.palette.accent.opacity(0.8))
                .disabled(self.isTestingConnection || (!self.isLocalEndpoint(self.openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) && (self.providerAPIKeys[self.currentProvider] ?? "").isEmpty))
            }

            // Connection Status Display
            if self.connectionStatus == .success {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                    Text("Connection verified").font(.caption).foregroundStyle(.green)
                }
            } else if self.connectionStatus == .failed {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red).font(.caption)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connection failed").font(.caption).foregroundStyle(.red)
                        if !self.connectionErrorMessage.isEmpty {
                            Text(self.connectionErrorMessage).font(.caption2).foregroundStyle(.red.opacity(0.8)).lineLimit(1)
                        }
                    }
                }
            } else if self.connectionStatus == .testing {
                HStack(spacing: 8) {
                    ProgressView().frame(width: 16, height: 16)
                    Text("Verifying...").font(.caption).foregroundStyle(self.theme.palette.accent)
                }
            }

            // API Key Editor Sheet
            Color.clear.frame(height: 0)
                .sheet(isPresented: self.$showAPIKeyEditor) {
                    self.apiKeyEditorSheet
                }
        }
    }

    private var apiKeyEditorSheet: some View {
        VStack(spacing: 14) {
            Text("Enter \(self.providerDisplayName(for: self.selectedProviderID)) API Key").font(.headline)
            SecureField("API Key (optional for local endpoints)", text: self.$newProviderApiKey)
                .textFieldStyle(.roundedBorder).frame(width: 300)
            HStack(spacing: 12) {
                Button("Cancel") { self.showAPIKeyEditor = false }.buttonStyle(.bordered)
                Button("OK") {
                    let trimmedKey = self.newProviderApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.providerAPIKeys[self.currentProvider] = trimmedKey
                    self.saveProviderAPIKeys()
                    if self.connectionStatus != .unknown { self.connectionStatus = .unknown; self.connectionErrorMessage = "" }
                    self.showAPIKeyEditor = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(!self.isLocalEndpoint(self.openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) && self.newProviderApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 350, minHeight: 150)
    }

    private var addProviderSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                TextField("Provider name", text: self.$newProviderName).textFieldStyle(.roundedBorder).frame(width: 200)
                TextField("Base URL", text: self.$newProviderBaseURL).textFieldStyle(.roundedBorder).frame(width: 250)
            }
            HStack(spacing: 8) {
                SecureField("API Key (optional for local)", text: self.$newProviderApiKey).textFieldStyle(.roundedBorder).frame(width: 200)
                TextField("Models (comma-separated)", text: self.$newProviderModels).textFieldStyle(.roundedBorder).frame(width: 250)
            }
            HStack(spacing: 8) {
                Button("Save Provider") { self.saveNewProvider() }
                    .buttonStyle(GlassButtonStyle())
                    .disabled(self.newProviderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || self.newProviderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel") {
                    self.showingSaveProvider = false; self.newProviderName = ""; self.newProviderBaseURL = ""; self
                        .newProviderApiKey = ""; self.newProviderModels = ""
                }
                .buttonStyle(GlassButtonStyle())
            }
        }
        .transition(.opacity)
    }

    private func saveNewProvider() {
        let name = self.newProviderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = self.newProviderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let api = self.newProviderApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !base.isEmpty else { return }

        let modelsList = self.newProviderModels.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let models = modelsList.isEmpty ? ModelRepository.shared.defaultModels(for: "openai") : modelsList

        let newProvider = SettingsStore.SavedProvider(name: name, baseURL: base, models: models)
        self.savedProviders.removeAll { $0.name.lowercased() == name.lowercased() }
        self.savedProviders.append(newProvider)
        self.saveSavedProviders()

        let key = self.providerKey(for: newProvider.id)
        self.providerAPIKeys[key] = api
        self.availableModelsByProvider[key] = models
        self.selectedModelByProvider[key] = models.first ?? self.selectedModel
        SettingsStore.shared.providerAPIKeys = self.providerAPIKeys
        SettingsStore.shared.availableModelsByProvider = self.availableModelsByProvider
        SettingsStore.shared.selectedModelByProvider = self.selectedModelByProvider

        self.selectedProviderID = newProvider.id
        self.openAIBaseURL = base
        self.updateCurrentProvider()
        self.availableModels = models
        self.selectedModel = models.first ?? self.selectedModel

        self.showingSaveProvider = false
        self.newProviderName = ""; self.newProviderBaseURL = ""; self.newProviderApiKey = ""; self.newProviderModels = ""
    }

    // MARK: - Advanced Settings Card

    private var advancedSettingsCard: some View {
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

    private func promptPreview(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Empty prompt" }
        let singleLine = trimmed.replacingOccurrences(of: "\n", with: " ")
        return singleLine.count > 120 ? String(singleLine.prefix(120)) + "…" : singleLine
    }

    /// Combine a user-visible body with the hidden base prompt to ensure role/intent is always present.
    private func combinedDraftPrompt(_ text: String) -> String {
        let body = SettingsStore.stripBaseDictationPrompt(from: text)
        return SettingsStore.combineBasePrompt(with: body)
    }

    private func requestDeletePrompt(_ profile: SettingsStore.DictationPromptProfile) {
        self.pendingDeletePromptID = profile.id
        self.pendingDeletePromptName = profile.name.isEmpty ? "Untitled Prompt" : profile.name
        self.showingDeletePromptConfirm = true
    }

    private func clearPendingDeletePrompt() {
        self.showingDeletePromptConfirm = false
        self.pendingDeletePromptID = nil
        self.pendingDeletePromptName = ""
    }

    private func deletePendingPrompt() {
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

    private func promptProfileCard(
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
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.green.opacity(0.18)))
                                .foregroundStyle(.green)
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

    private func promptEditorSheet(mode: PromptEditorMode) -> some View {
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

    private func openDefaultPromptViewer() {
        self.draftPromptName = "Default"
        if let override = self.settings.defaultDictationPromptOverride {
            self.draftPromptText = SettingsStore.stripBaseDictationPrompt(from: override)
        } else {
            self.draftPromptText = SettingsStore.defaultDictationPromptBodyText()
        }
        self.promptEditorSessionID = UUID()
        self.promptEditorMode = .defaultPrompt
    }

    private func openNewPromptEditor() {
        self.draftPromptName = "New Prompt"
        self.draftPromptText = ""
        self.promptEditorSessionID = UUID()
        self.promptEditorMode = .newPrompt
    }

    private func openEditor(for profile: SettingsStore.DictationPromptProfile) {
        self.draftPromptName = profile.name
        self.draftPromptText = SettingsStore.stripBaseDictationPrompt(from: profile.prompt)
        self.promptEditorSessionID = UUID()
        self.promptEditorMode = .edit(promptID: profile.id)
    }

    private func closePromptEditor() {
        self.promptEditorMode = nil
        self.draftPromptName = ""
        self.draftPromptText = ""
        self.promptTest.deactivate()
    }

    // MARK: - Prompt Test Gating

    private func isAIPostProcessingConfiguredForDictation() -> Bool {
        DictationAIPostProcessingGate.isConfigured()
    }

    private func savePromptEditor(mode: PromptEditorMode) {
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
