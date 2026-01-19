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

enum PromptEditorMode: Identifiable, Equatable {
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

enum ModelSortOption: String, CaseIterable, Identifiable {
    case name = "Model Name"
    case accuracy = "Accuracy"
    case speed = "Speed"

    var id: String { self.rawValue }
}

enum SpeechProviderFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case nvidia = "NVIDIA"
    case apple = "Apple"
    case openai = "OpenAI"

    var id: String { self.rawValue }
}

struct AISettingsView: View {
    @EnvironmentObject var appServices: AppServices
    @EnvironmentObject var menuBarManager: MenuBarManager
    @Environment(\.theme) var theme
    @ObservedObject var promptTest = DictationPromptTestCoordinator.shared

    var asr: ASRService { self.appServices.asr }

    // MARK: - State Variables (moved from ContentView)

    @ObservedObject var settings = SettingsStore.shared

    @State var appear = false
    @State var openAIBaseURL: String = ModelRepository.shared.defaultBaseURL(for: "openai")
    @State var enableAIProcessing: Bool = false

    // Model Management
    @State var availableModelsByProvider: [String: [String]] = [:]
    @State var selectedModelByProvider: [String: String] = [:]
    @State var availableModels: [String] = ["gpt-4.1"]
    @State var selectedModel: String = "gpt-4.1"
    @State var showingAddModel: Bool = false
    @State var newModelName: String = ""
    @State var isFetchingModels: Bool = false
    @State var fetchModelsError: String? = nil

    // Reasoning Configuration
    @State var showingReasoningConfig: Bool = false
    @State var editingReasoningParamName: String = "reasoning_effort"
    @State var editingReasoningParamValue: String = "low"
    @State var editingReasoningEnabled: Bool = false

    // Provider Management
    @State var providerAPIKeys: [String: String] = [:]
    @State var currentProvider: String = "openai"
    @State var savedProviders: [SettingsStore.SavedProvider] = []
    @State var selectedProviderID: String = SettingsStore.shared.selectedProviderID

    // Connection Testing
    @State var isTestingConnection: Bool = false
    @State var connectionStatus: AIConnectionStatus = .unknown
    @State var connectionErrorMessage: String = ""

    // UI State
    @State var showHelp: Bool = false
    @State var showingSaveProvider: Bool = false
    @State var showAPIKeyEditor: Bool = false

    // Speech Model Controls
    @State var modelSortOption: ModelSortOption = .name
    @State var providerFilter: SpeechProviderFilter = .all
    @State var englishOnlyFilter: Bool = false
    @State var installedOnlyFilter: Bool = false
    @State var showSpeechFilters: Bool = false

    @State var showingEditProvider: Bool = false

    // Provider Form State
    @State var newProviderName: String = ""
    @State var newProviderBaseURL: String = ""
    @State var newProviderApiKey: String = ""
    @State var newProviderModels: String = ""
    @State var editProviderName: String = ""
    @State var editProviderBaseURL: String = ""

    // Keychain State
    @State var showKeychainPermissionAlert: Bool = false
    @State var keychainPermissionMessage: String = ""

    // Filler Words State - local state to ensure UI reactivity
    @State var removeFillerWordsEnabled: Bool = SettingsStore.shared.removeFillerWordsEnabled

    // Dictation Prompt Profiles UI
    @State var promptEditorMode: PromptEditorMode? = nil
    @State var draftPromptName: String = ""
    @State var draftPromptText: String = ""
    @State var promptEditorSessionID: UUID = .init()

    // Prompt Deletion UI
    @State var showingDeletePromptConfirm: Bool = false
    @State var pendingDeletePromptID: String? = nil
    @State var pendingDeletePromptName: String = ""

    // Speech Model Provider Tab Selection
    @State var selectedSpeechProvider: SettingsStore.SpeechModel.Provider = .nvidia
    @State var previewSpeechModel: SettingsStore.SpeechModel = SettingsStore.shared.selectedSpeechModel
    @State var showAdvancedSpeechInfo: Bool = false
    @State var suppressSpeechProviderSync: Bool = false
    @State var skipNextSpeechModelSync: Bool = false

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
}
