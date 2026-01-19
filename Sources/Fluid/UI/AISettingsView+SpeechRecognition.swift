//
//  AISettingsView+SpeechRecognition.swift
//  fluid
//
//  Extracted from AISettingsView.swift to keep view body under lint limit.
//

import SwiftUI

extension AISettingsView {
    // MARK: - Speech Recognition Card

    var speechRecognitionCard: some View {
        let activeModel = SettingsStore.shared.selectedSpeechModel
        let otherModels = self.filteredSpeechModels.filter { $0 != activeModel }

        return ThemedCard(hoverEffect: false) {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundStyle(self.theme.palette.accent)
                    Text("Voice Engine")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Spacer()
                }

                // Stats Panel - Dynamic bars that update based on selected model
                self.modelStatsPanel
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.08), lineWidth: 1)
                            )
                    )

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Click a row to preview. Press Activate to load the model.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        ForEach(SpeechProviderFilter.allCases) { option in
                            Button(option.rawValue) {
                                self.providerFilter = option
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.caption)
                            Text("Filter: \(self.providerFilter.rawValue)")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9)
                                        .stroke(.white.opacity(0.12), lineWidth: 1)
                                )
                        )
                    }
                    Menu {
                        ForEach(ModelSortOption.allCases) { option in
                            Button(option.rawValue) {
                                self.modelSortOption = option
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Sort by: \(self.modelSortOption.rawValue)")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9)
                                        .stroke(.white.opacity(0.12), lineWidth: 1)
                                )
                        )
                    }
                }

                // Active + Other models list
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Active Model")
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        self.speechModelCard(for: activeModel)
                    }

                    Divider().padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Other Models")
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        VStack(spacing: 8) {
                            ForEach(otherModels) { model in
                                self.speechModelCard(for: model)
                            }
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        )
                )

                Divider().padding(.vertical, 4)

                // Filler Words Section
                self.fillerWordsSection
            }
            .padding(14)
        }
    }

    /// Stats panel showing speed/accuracy bars that animate when model changes
    var modelStatsPanel: some View {
        let model = self.previewSpeechModel

        return HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
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
                        .font(.system(size: 13))
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Speed and Accuracy - Vertical Liquid Bars (FluidVoice easter egg!)
            HStack(spacing: 16) {
                LiquidBar(
                    fillPercent: model.speedPercent,
                    color: .yellow,
                    secondaryColor: .orange,
                    icon: "bolt.fill",
                    label: "Speed"
                )

                LiquidBar(
                    fillPercent: model.accuracyPercent,
                    color: Color.fluidGreen,
                    secondaryColor: .cyan,
                    icon: "target",
                    label: "Accuracy"
                )
            }
            .frame(width: 140, alignment: .center)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: model.id)
        }
        .padding(.vertical, 6)
    }

    var filteredSpeechModels: [SettingsStore.SpeechModel] {
        var models = SettingsStore.SpeechModel.availableModels

        switch self.providerFilter {
        case .all:
            break
        case .nvidia:
            models = models.filter { $0.provider == .nvidia }
        case .apple:
            models = models.filter { $0.provider == .apple }
        case .openai:
            models = models.filter { $0.provider == .openai }
        }

        if self.englishOnlyFilter {
            models = models.filter { model in
                let label = model.languageSupport.lowercased()
                let title = model.humanReadableName.lowercased()
                return label.contains("english only") || title.contains("english")
            }
        }

        if self.installedOnlyFilter {
            models = models.filter { $0.isInstalled }
        }

        switch self.modelSortOption {
        case .name:
            models.sort { $0.humanReadableName.localizedCaseInsensitiveCompare($1.humanReadableName) == .orderedAscending }
        case .accuracy:
            models.sort { $0.accuracyPercent > $1.accuracyPercent }
        case .speed:
            models.sort { $0.speedPercent > $1.speedPercent }
        }

        return models
    }

    /// Simplified card for selecting a speech model
    func speechModelCard(for model: SettingsStore.SpeechModel) -> some View {
        let isSelected = self.previewSpeechModel == model
        let isActive = self.isActiveSpeechModel(model)

        return HStack(alignment: .top, spacing: 10) {
            // Selection indicator
            Circle()
                .fill(isSelected ? Color.fluidGreen : .white.opacity(0.1))
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.fluidGreen : .white.opacity(0.3), lineWidth: 1)
                )

            // Brand logo/badge - fixed size container for consistency
            ZStack {
                if model.usesAppleLogo {
                    // Apple logo uses SF Symbol
                    Image(systemName: "apple.logo")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: model.brandColorHex) ?? .gray)
                } else {
                    // Text badges (NVIDIA, OpenAI)
                    Text(model.brandName)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: model.brandColorHex) ?? .gray)
                        )
                }
            }
            .frame(width: 48, height: 20, alignment: .center)

            // Title + technical name
            VStack(alignment: .leading, spacing: 2) {
                Text(model.humanReadableName)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? self.theme.palette.primaryText : .secondary)
                if self.showAdvancedSpeechInfo {
                    Text(model.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.7))
                }

                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                        Text("Speed \(Int(model.speedPercent * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "target")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.fluidGreen)
                        Text("Acc \(Int(model.accuracyPercent * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if isSelected && !isActive {
                        Text("Previewing")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                            .background(Capsule().fill(isLoading ? .orange.opacity(0.25) : Color.fluidGreen.opacity(0.25)))
                            .foregroundStyle(isLoading ? .orange : Color.fluidGreen)
                    } else {
                        Button("Activate") {
                            self.activateSpeechModel(model)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(Color.fluidGreen)
                        .fontWeight(.semibold)
                        .shadow(color: Color.fluidGreen.opacity(0.35), radius: 4, x: 0, y: 1)
                        .disabled(self.asr.isRunning)
                    }

                    if !model.usesAppleLogo {
                        if isSelected {
                            Button {
                                self.deleteSpeechModel(model)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .disabled(self.asr.isRunning)
                            .offset(x: isSelected ? 0 : 12)
                            .opacity(isSelected ? 1 : 0)
                        }
                    }
                }
            } else {
                ZStack(alignment: .trailing) {
                    Text("Not downloaded")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .opacity(isSelected ? 0 : 1)

                    Button("Download") {
                        self.previewSpeechModel = model
                        self.downloadSpeechModel(model)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.blue)
                    .disabled(self.asr.isRunning)
                    .offset(x: isSelected ? 0 : 16)
                    .opacity(isSelected ? 1 : 0)
                }
                .frame(width: 120, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? .white.opacity(0.05) : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? .white.opacity(0.25) : .white.opacity(0.05), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isActive ? Color.fluidGreen.opacity(0.9) : .clear, lineWidth: 2)
                )
        )
        .onTapGesture {
            self.previewSpeechModel = model
        }
        .opacity(self.asr.isRunning ? 0.6 : 1.0)
        .allowsHitTesting(!self.asr.isRunning)
    }

    func activateSpeechModel(_ model: SettingsStore.SpeechModel) {
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

    func downloadSpeechModel(_ model: SettingsStore.SpeechModel) {
        guard !self.asr.isRunning else { return }
        let previousActive = SettingsStore.shared.selectedSpeechModel

        Task {
            let shouldRestore = previousActive != model
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
                    if self.previewSpeechModel == model {
                        self.previewSpeechModel = model
                    }
                    self.suppressSpeechProviderSync = false
                }
            }

            await self.downloadModels()
        }
    }

    func deleteSpeechModel(_ model: SettingsStore.SpeechModel) {
        guard !self.asr.isRunning else { return }
        let previousActive = SettingsStore.shared.selectedSpeechModel

        Task {
            let shouldRestore = previousActive != model
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
                    if self.previewSpeechModel == model {
                        self.previewSpeechModel = model
                    }
                    self.suppressSpeechProviderSync = false
                }
            }

            await self.deleteModels()
        }
    }

    func isActiveSpeechModel(_ model: SettingsStore.SpeechModel) -> Bool {
        SettingsStore.shared.selectedSpeechModel == model
    }

    /// Returns the appropriate description text for the currently selected speech model
    var modelDescriptionText: String {
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

    var modelStatusView: some View {
        HStack(spacing: 12) {
            if (self.asr.isDownloadingModel || self.asr.isLoadingModel) && !self.asr.isAsrReady {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(self.asr.isLoadingModel ? "Loading model…" : "Downloading…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if self.asr.isAsrReady {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.fluidGreen).font(.caption)
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

    var fillerWordsSection: some View {
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

    func downloadModels() async {
        do {
            try await self.asr.ensureAsrReady()
        } catch {
            DebugLogger.shared.error("Failed to download models: \(error)", source: "AISettingsView")
        }
    }

    func deleteModels() async {
        do {
            try await self.asr.clearModelCache()
        } catch {
            DebugLogger.shared.error("Failed to delete models: \(error)", source: "AISettingsView")
        }
    }

    // MARK: - Helper Functions

    func setSelectedSpeechProvider(_ provider: SettingsStore.SpeechModel.Provider) {
        self.selectedSpeechProvider = provider
    }
}
