//
//  AISettingsView+AIConfiguration.swift
//  fluid
//
//  Extracted from AISettingsView.swift to keep view body under lint limit.
//

import AppKit
import Security
import SwiftUI

extension AISettingsView {
    // MARK: - Helper Functions

    func providerKey(for providerID: String) -> String {
        // Built-in providers use their ID directly
        if ModelRepository.shared.isBuiltIn(providerID) { return providerID }
        // Custom providers get "custom:" prefix (if not already present)
        if providerID.hasPrefix("custom:") { return providerID }
        return providerID.isEmpty ? self.currentProvider : "custom:\(providerID)"
    }

    func providerDisplayName(for providerID: String) -> String {
        switch providerID {
        case "openai": return "OpenAI"
        case "groq": return "Groq"
        case "apple-intelligence": return "Apple Intelligence"
        default:
            return self.savedProviders.first(where: { $0.id == providerID })?.name ?? providerID.capitalized
        }
    }

    func saveProviderAPIKeys() {
        SettingsStore.shared.providerAPIKeys = self.providerAPIKeys
    }

    func updateCurrentProvider() {
        let url = self.openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.contains("openai.com") { self.currentProvider = "openai"; return }
        if url.contains("groq.com") { self.currentProvider = "groq"; return }
        self.currentProvider = self.providerKey(for: self.selectedProviderID)
    }

    func saveSavedProviders() {
        SettingsStore.shared.savedProviders = self.savedProviders
    }

    func isLocalEndpoint(_ urlString: String) -> Bool {
        return ModelRepository.shared.isLocalEndpoint(urlString)
    }

    func hasReasoningConfigForCurrentModel() -> Bool {
        let pKey = self.providerKey(for: self.selectedProviderID)
        if SettingsStore.shared.hasCustomReasoningConfig(forModel: self.selectedModel, provider: pKey) {
            if let config = SettingsStore.shared.getReasoningConfig(forModel: selectedModel, provider: pKey) {
                return config.isEnabled
            }
        }
        return SettingsStore.shared.isReasoningModel(self.selectedModel)
    }

    func addNewModel() {
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

    func handleAPIKeyButtonTapped() {
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
    func presentKeychainAccessAlert(message: String) {
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

    func testAPIConnection() async {
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
                    self.connectionErrorMessage = "Failed to create test payload"
                }
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = jsonData
            request.timeoutInterval = 12

            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 200, httpResponse.statusCode < 300 {
                await MainActor.run {
                    self.connectionStatus = .success
                    self.connectionErrorMessage = ""
                }
            } else if let httpResponse = response as? HTTPURLResponse {
                await MainActor.run {
                    self.connectionStatus = .failed
                    self.connectionErrorMessage = "HTTP \(httpResponse.statusCode)"
                }
            } else {
                await MainActor.run {
                    self.connectionStatus = .failed
                    self.connectionErrorMessage = "Unexpected response"
                }
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

    var aiConfigurationCard: some View {
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

    var apiKeyWarningView: some View {
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

    var helpSectionView: some View {
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

    func helpStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.caption).fontWeight(.semibold).frame(width: 16, alignment: .trailing)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    var providerConfigurationSection: some View {
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

    var providerPickerRow: some View {
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

    var builtInProvidersList: [(id: String, name: String)] {
        ModelRepository.shared.builtInProvidersList(
            includeAppleIntelligence: true,
            appleIntelligenceAvailable: AppleIntelligenceService.isAvailable
        )
    }

    func handleProviderChange(_ newValue: String) {
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

    func startEditingProvider() {
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

    func deleteCurrentProvider() {
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

    var editProviderSection: some View {
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

    func saveEditedProvider() {
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

    var appleIntelligenceBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "apple.logo").font(.system(size: 14))
            Text("On-Device").fontWeight(.medium)
            Text("•").foregroundStyle(.secondary)
            Image(systemName: "lock.shield.fill").font(.system(size: 12))
            Text("Private").fontWeight(.medium)
        }
        .font(.caption).foregroundStyle(Color.fluidGreen)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.fluidGreen.opacity(0.15))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                Color.fluidGreen.opacity(0.3),
                lineWidth: 1
            )))
    }

    var appleIntelligenceModelRow: some View {
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

    var standardModelRow: some View {
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

    func deleteSelectedModel() {
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

    func fetchModelsForCurrentProvider() async {
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

    func openReasoningConfig() {
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

    var addModelSection: some View {
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

    var reasoningConfigSection: some View {
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

    func saveReasoningConfig() {
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

    var connectionTestSection: some View {
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
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.fluidGreen).font(.caption)
                    Text("Connection verified").font(.caption).foregroundStyle(Color.fluidGreen)
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

    var apiKeyEditorSheet: some View {
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

    var addProviderSection: some View {
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

    func saveNewProvider() {
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
}
