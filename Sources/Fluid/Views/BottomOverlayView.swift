//
//  BottomOverlayView.swift
//  Fluid
//
//  Bottom overlay for transcription (alternative to notch overlay)
//

import AppKit
import Combine
import SwiftUI

// MARK: - Bottom Overlay Window Controller

@MainActor
final class BottomOverlayWindowController {
    static let shared = BottomOverlayWindowController()

    private var window: NSPanel?
    private var audioSubscription: AnyCancellable?
    private var pendingResizeWorkItem: DispatchWorkItem?

    private init() {
        NotificationCenter.default.addObserver(forName: NSNotification.Name("OverlayOffsetChanged"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.positionWindow()
            }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("OverlaySizeChanged"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateSizeAndPosition()
            }
        }
    }

    func show(audioPublisher: AnyPublisher<CGFloat, Never>, mode: OverlayMode) {
        self.pendingResizeWorkItem?.cancel()
        self.pendingResizeWorkItem = nil
        BottomOverlayPromptMenuController.shared.hide()

        // Update mode in content state
        NotchContentState.shared.mode = mode
        switch mode {
        case .dictation: NotchContentState.shared.promptPickerMode = .dictate
        case .edit, .write, .rewrite: NotchContentState.shared.promptPickerMode = .edit
        case .command: break
        }
        NotchContentState.shared.updateTranscription("")
        NotchContentState.shared.bottomOverlayAudioLevel = 0

        // Subscribe to audio levels and route through NotchContentState
        self.audioSubscription?.cancel()
        self.audioSubscription = audioPublisher
            .receive(on: DispatchQueue.main)
            .sink { level in
                NotchContentState.shared.bottomOverlayAudioLevel = level
            }

        // Create window if needed
        if self.window == nil {
            self.createWindow()
        }

        // Position at bottom center of main screen
        self.positionWindow()

        // Show with animation
        self.window?.alphaValue = 0
        self.window?.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.window?.animator().alphaValue = 1
        }
    }

    func hide() {
        // Cancel audio subscription
        self.audioSubscription?.cancel()
        self.audioSubscription = nil
        self.pendingResizeWorkItem?.cancel()
        self.pendingResizeWorkItem = nil
        BottomOverlayPromptMenuController.shared.hide()

        // Reset state
        NotchContentState.shared.setProcessing(false)
        NotchContentState.shared.bottomOverlayAudioLevel = 0
        NotchContentState.shared.targetAppIcon = nil

        guard let window = window else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        } completionHandler: {
            window.orderOut(nil)
        }
    }

    func setProcessing(_ processing: Bool) {
        NotchContentState.shared.setProcessing(processing)
    }

    func refreshSizeForContent() {
        self.pendingResizeWorkItem?.cancel()

        // Debounce rapid streaming updates to avoid resize thrash.
        let resizeWorkItem = DispatchWorkItem { [weak self] in
            self?.updateSizeAndPosition()
        }
        self.pendingResizeWorkItem = resizeWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: resizeWorkItem)
    }

    /// Update window size based on current SwiftUI content and re-position
    private func updateSizeAndPosition() {
        guard let window = window, let hostingView = window.contentView as? NSHostingView<BottomOverlayView> else { return }

        // Re-calculate fitting size for the new layout constants
        let newSize = hostingView.fittingSize

        // Avoid redundant content-size updates while AppKit is already resolving constraints.
        // Re-applying the same size can trigger unnecessary update-constraints churn.
        let currentSize = window.contentView?.frame.size ?? window.frame.size
        let widthChanged = abs(currentSize.width - newSize.width) > 0.5
        let heightChanged = abs(currentSize.height - newSize.height) > 0.5

        if widthChanged || heightChanged {
            // Resize from the current origin to avoid AppKit's default top-left anchoring,
            // which can visually push the overlay down before we re-position it.
            let currentOrigin = window.frame.origin
            let resizedFrame = NSRect(origin: currentOrigin, size: newSize)
            window.setFrame(resizedFrame, display: false)
        }

        // Re-position
        self.positionWindow()
    }

    private func createWindow() {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // SwiftUI handles shadow
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        let contentView = BottomOverlayView()
        let hostingView = NSHostingView(rootView: contentView)

        // Let SwiftUI determine the size
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: fittingSize)

        // Make hosting view fully transparent
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        panel.setContentSize(fittingSize)
        panel.contentView = hostingView

        self.window = panel
    }

    private func positionWindow() {
        // Safe check for window and screen availability
        guard let window = window else { return }

        // Use the screen that contains the window, or fallback to the main screen
        let screen = window.screen ?? NSScreen.main
        guard let screen = screen else { return }

        let fullFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let windowSize = window.frame.size

        // Horizontal centering
        let x = fullFrame.midX - windowSize.width / 2

        // Vertical positioning with safety clamping
        let offset = SettingsStore.shared.overlayBottomOffset

        // Calculate raw position
        var y = visibleFrame.minY + CGFloat(offset)

        // Safety Clamping:
        // 1. Min: Ensure it's at least visibleFrame.minY (not below the dock/visible area)
        // 2. Max: Ensure it doesn't cross the top of the visible frame minus its own height
        let minY = visibleFrame.minY + 10 // Small buffer from absolute bottom
        let maxY = visibleFrame.maxY - windowSize.height - 40 // Buffer from top

        y = max(min(y, maxY), minY)

        // Apply position directly to avoid implicit frame animations during hover-driven resizes.
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

@MainActor
final class BottomOverlayPromptMenuController {
    static let shared = BottomOverlayPromptMenuController()

    private var menuWindow: NSPanel?
    private var hostingView: NSHostingView<BottomOverlayPromptMenuView>?
    private var selectorFrameInScreen: CGRect = .zero
    private weak var parentWindow: NSWindow?
    private var menuMaxWidth: CGFloat = 220
    private var menuGap: CGFloat = 6

    private var isHoveringSelector = false
    private var isHoveringMenu = false
    private var pendingShowWorkItem: DispatchWorkItem?
    private var pendingHideWorkItem: DispatchWorkItem?
    private var pendingPositionWorkItem: DispatchWorkItem?

    private init() {}

    func updateAnchor(selectorFrameInScreen: CGRect, parentWindow: NSWindow?, maxWidth: CGFloat, menuGap: CGFloat) {
        guard selectorFrameInScreen.width > 0, selectorFrameInScreen.height > 0 else { return }

        let resolvedMaxWidth = max(maxWidth, 120)
        let widthChanged = abs(self.menuMaxWidth - resolvedMaxWidth) > 0.5

        self.selectorFrameInScreen = selectorFrameInScreen
        self.parentWindow = parentWindow
        self.menuMaxWidth = resolvedMaxWidth
        self.menuGap = max(menuGap, 2)

        if self.menuWindow?.isVisible == true {
            if widthChanged {
                self.updateMenuContent()
            }
            self.attachToParentWindowIfNeeded()
            self.scheduleMenuPositionUpdate()
        }
    }

    func selectorHoverChanged(_ hovering: Bool) {
        self.isHoveringSelector = hovering
        self.updateVisibility()
    }

    func menuHoverChanged(_ hovering: Bool) {
        self.isHoveringMenu = hovering
        self.updateVisibility()
    }

    func hide() {
        self.pendingShowWorkItem?.cancel()
        self.pendingShowWorkItem = nil
        self.pendingHideWorkItem?.cancel()
        self.pendingHideWorkItem = nil
        self.pendingPositionWorkItem?.cancel()
        self.pendingPositionWorkItem = nil

        self.isHoveringSelector = false
        self.isHoveringMenu = false

        if let menuWindow = self.menuWindow, let parent = menuWindow.parent {
            parent.removeChildWindow(menuWindow)
        }
        self.menuWindow?.orderOut(nil)
    }

    private func updateVisibility() {
        let shouldShow = self.isHoveringSelector || self.isHoveringMenu

        if shouldShow {
            self.pendingHideWorkItem?.cancel()
            self.pendingHideWorkItem = nil

            if self.menuWindow?.isVisible == true {
                self.scheduleMenuPositionUpdate()
                return
            }

            self.pendingShowWorkItem?.cancel()
            let showTask = DispatchWorkItem { [weak self] in
                self?.showMenuIfPossible()
            }
            self.pendingShowWorkItem = showTask
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: showTask)
            return
        }

        self.pendingShowWorkItem?.cancel()
        self.pendingShowWorkItem = nil

        self.pendingHideWorkItem?.cancel()
        let hideTask = DispatchWorkItem { [weak self] in
            self?.hideIfNotHovered()
        }
        self.pendingHideWorkItem = hideTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: hideTask)
    }

    private func hideIfNotHovered() {
        guard !self.isHoveringSelector, !self.isHoveringMenu else { return }
        self.pendingPositionWorkItem?.cancel()
        self.pendingPositionWorkItem = nil
        if let menuWindow = self.menuWindow, let parent = menuWindow.parent {
            parent.removeChildWindow(menuWindow)
        }
        self.menuWindow?.orderOut(nil)
    }

    private func scheduleMenuPositionUpdate() {
        guard self.pendingPositionWorkItem == nil else { return }

        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingPositionWorkItem = nil
            self.updateMenuSizeAndPosition()
        }

        self.pendingPositionWorkItem = task
        DispatchQueue.main.async(execute: task)
    }

    private func showMenuIfPossible() {
        guard self.selectorFrameInScreen.width > 0, self.selectorFrameInScreen.height > 0 else { return }

        self.createWindowIfNeeded()
        self.updateMenuContent()
        self.attachToParentWindowIfNeeded()
        self.updateMenuSizeAndPosition()
        self.menuWindow?.orderFrontRegardless()
    }

    private func createWindowIfNeeded() {
        guard self.menuWindow == nil else { return }

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        let contentView = BottomOverlayPromptMenuView(
            maxWidth: self.menuMaxWidth,
            onHoverChanged: { [weak self] hovering in
                self?.menuHoverChanged(hovering)
            },
            onDismissRequested: { [weak self] in
                self?.hide()
            }
        )

        let hostingView = NSHostingView(rootView: contentView)
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: fittingSize)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        panel.setContentSize(fittingSize)
        panel.contentView = hostingView

        self.hostingView = hostingView
        self.menuWindow = panel
    }

    private func updateMenuContent() {
        let rootView = BottomOverlayPromptMenuView(
            maxWidth: self.menuMaxWidth,
            onHoverChanged: { [weak self] hovering in
                self?.menuHoverChanged(hovering)
            },
            onDismissRequested: { [weak self] in
                self?.hide()
            }
        )
        self.hostingView?.rootView = rootView
    }

    private func attachToParentWindowIfNeeded() {
        guard let menuWindow = self.menuWindow else { return }

        if let currentParent = menuWindow.parent, currentParent !== self.parentWindow {
            currentParent.removeChildWindow(menuWindow)
        }

        if let parentWindow = self.parentWindow, menuWindow.parent !== parentWindow {
            parentWindow.addChildWindow(menuWindow, ordered: .above)
        }
    }

    private func updateMenuSizeAndPosition() {
        guard let menuWindow = self.menuWindow, let hostingView = self.hostingView else { return }
        guard self.selectorFrameInScreen.width > 0, self.selectorFrameInScreen.height > 0 else { return }

        let fittingSize = hostingView.fittingSize
        guard fittingSize.width > 0, fittingSize.height > 0 else { return }

        let preferredX = self.selectorFrameInScreen.midX - (fittingSize.width / 2)
        let preferredY = self.selectorFrameInScreen.minY - self.menuGap - fittingSize.height

        let screen = self.parentWindow?.screen
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: self.selectorFrameInScreen.midX, y: self.selectorFrameInScreen.midY)) })
            ?? NSScreen.main

        var targetX = preferredX
        var targetY = preferredY

        if let screen {
            let visible = screen.visibleFrame
            let horizontalInset: CGFloat = 8
            let verticalInset: CGFloat = 8

            if fittingSize.width < visible.width - (horizontalInset * 2) {
                targetX = max(visible.minX + horizontalInset, min(preferredX, visible.maxX - fittingSize.width - horizontalInset))
            } else {
                targetX = visible.minX + horizontalInset
            }

            if fittingSize.height < visible.height - (verticalInset * 2) {
                targetY = max(visible.minY + verticalInset, min(preferredY, visible.maxY - fittingSize.height - verticalInset))
            } else {
                targetY = visible.minY + verticalInset
            }
        }

        let targetFrame = NSRect(x: targetX, y: targetY, width: fittingSize.width, height: fittingSize.height)
        let currentFrame = menuWindow.frame
        let frameTolerance: CGFloat = 0.5
        let isSameFrame =
            abs(currentFrame.origin.x - targetFrame.origin.x) <= frameTolerance &&
            abs(currentFrame.origin.y - targetFrame.origin.y) <= frameTolerance &&
            abs(currentFrame.size.width - targetFrame.size.width) <= frameTolerance &&
            abs(currentFrame.size.height - targetFrame.size.height) <= frameTolerance

        if !isSameFrame {
            menuWindow.setFrame(targetFrame, display: false)
        }
    }
}

private struct BottomOverlayPromptMenuView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var contentState = NotchContentState.shared

    let maxWidth: CGFloat
    let onHoverChanged: (Bool) -> Void
    let onDismissRequested: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach(SettingsStore.PromptMode.visiblePromptModes, id: \.rawValue) { mode in
                    Button(action: {
                        let normalizedMode = mode.normalized
                        if !self.contentState.isProcessing {
                            self.contentState.onPromptModeSwitchRequested?(normalizedMode)
                        }
                        self.contentState.promptPickerMode = normalizedMode
                    }) {
                        Text(mode.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(self.contentState.promptPickerMode == mode ? Color.white.opacity(0.18) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 6)

            Button(action: {
                self.settings.setSelectedPromptID(nil, for: self.contentState.promptPickerMode)
                self.restoreTypingTargetApp()
                self.onDismissRequested()
            }) {
                HStack {
                    Text("Default")
                    Spacer()
                    if self.settings.selectedPromptID(for: self.contentState.promptPickerMode) == nil {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)

            if !self.settings.promptProfiles(for: self.contentState.promptPickerMode).isEmpty {
                Divider()
                    .padding(.vertical, 4)

                ForEach(self.settings.promptProfiles(for: self.contentState.promptPickerMode)) { profile in
                    Button(action: {
                        self.settings.setSelectedPromptID(profile.id, for: self.contentState.promptPickerMode)
                        self.restoreTypingTargetApp()
                        self.onDismissRequested()
                    }) {
                        HStack {
                            Text(profile.name.isEmpty ? "Untitled" : profile.name)
                            Spacer()
                            if self.settings.selectedPromptID(for: self.contentState.promptPickerMode) == profile.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .frame(maxWidth: self.maxWidth)
        .onHover { hovering in
            self.onHoverChanged(hovering)
        }
    }

    private func restoreTypingTargetApp() {
        let pid = NotchContentState.shared.recordingTargetPID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let pid { _ = TypingService.activateApp(pid: pid) }
        }
    }

}

private struct PromptSelectorAnchorReader: NSViewRepresentable {
    let onFrameChange: (CGRect, NSWindow?) -> Void

    func makeNSView(context: Context) -> AnchorReportingView {
        let view = AnchorReportingView()
        view.onFrameChange = self.onFrameChange
        return view
    }

    func updateNSView(_ nsView: AnchorReportingView, context: Context) {
        nsView.onFrameChange = self.onFrameChange
    }

    final class AnchorReportingView: NSView {
        var onFrameChange: ((CGRect, NSWindow?) -> Void)?
        private var windowObservers: [NSObjectProtocol] = []
        private var lastReportedFrameInScreen: CGRect = .null
        private weak var lastReportedWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            self.installWindowObservers()
            self.reportFrame(force: true)
        }

        override func layout() {
            super.layout()
            self.reportFrame()
        }

        deinit {
            self.cleanup()
        }

        func cleanup() {
            for observer in self.windowObservers {
                NotificationCenter.default.removeObserver(observer)
            }
            self.windowObservers.removeAll()
        }

        private func installWindowObservers() {
            self.cleanup()
            guard let window = self.window else { return }

            let center = NotificationCenter.default
            self.windowObservers.append(
                center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
                    self?.reportFrame()
                }
            )
            self.windowObservers.append(
                center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                    self?.reportFrame()
                }
            )
            self.windowObservers.append(
                center.addObserver(forName: NSWindow.didChangeScreenNotification, object: window, queue: .main) { [weak self] _ in
                    self?.reportFrame()
                }
            )
        }

        func reportFrame(force: Bool = false) {
            guard let window = self.window else {
                if force || !self.lastReportedFrameInScreen.isNull {
                    self.lastReportedFrameInScreen = .null
                    self.lastReportedWindow = nil
                    self.onFrameChange?(CGRect.zero, nil)
                }
                return
            }

            let frameInWindow = self.convert(self.bounds, to: nil)
            let frameInScreen = window.convertToScreen(frameInWindow)
            let frameTolerance: CGFloat = 0.5
            let hasLastFrame = !self.lastReportedFrameInScreen.isNull
            let frameChanged = !hasLastFrame ||
                abs(frameInScreen.origin.x - self.lastReportedFrameInScreen.origin.x) > frameTolerance ||
                abs(frameInScreen.origin.y - self.lastReportedFrameInScreen.origin.y) > frameTolerance ||
                abs(frameInScreen.size.width - self.lastReportedFrameInScreen.size.width) > frameTolerance ||
                abs(frameInScreen.size.height - self.lastReportedFrameInScreen.size.height) > frameTolerance
            let windowChanged = self.lastReportedWindow !== window

            guard force || frameChanged || windowChanged else { return }

            self.lastReportedFrameInScreen = frameInScreen
            self.lastReportedWindow = window
            self.onFrameChange?(frameInScreen, window)
        }
    }
}

// MARK: - Bottom Overlay SwiftUI View

struct BottomOverlayView: View {
    @ObservedObject private var contentState = NotchContentState.shared
    @ObservedObject private var appServices = AppServices.shared
    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.theme) private var theme

    struct LayoutConstants {
        let hPadding: CGFloat
        let vPadding: CGFloat
        let waveformWidth: CGFloat
        let waveformHeight: CGFloat
        let iconSize: CGFloat
        let transFontSize: CGFloat
        let modeFontSize: CGFloat
        let cornerRadius: CGFloat
        let barCount: Int
        let barWidth: CGFloat
        let barSpacing: CGFloat
        let minBarHeight: CGFloat
        let maxBarHeight: CGFloat

        static func get(for size: SettingsStore.OverlaySize) -> LayoutConstants {
            switch size {
            case .small:
                return LayoutConstants(
                    hPadding: 14,
                    vPadding: 8,
                    waveformWidth: 90,
                    waveformHeight: 20,
                    iconSize: 16,
                    transFontSize: 11,
                    modeFontSize: 10,
                    cornerRadius: 14,
                    barCount: 7,
                    barWidth: 3.0,
                    barSpacing: 3.5,
                    minBarHeight: 5,
                    maxBarHeight: 16
                )
            case .medium:
                return LayoutConstants(
                    hPadding: 18,
                    vPadding: 12,
                    waveformWidth: 130,
                    waveformHeight: 32,
                    iconSize: 20,
                    transFontSize: 13,
                    modeFontSize: 12,
                    cornerRadius: 18,
                    barCount: 9,
                    barWidth: 3.5,
                    barSpacing: 4.5,
                    minBarHeight: 6,
                    maxBarHeight: 28
                )
            case .large:
                return LayoutConstants(
                    hPadding: 24,
                    vPadding: 18,
                    waveformWidth: 180,
                    waveformHeight: 48,
                    iconSize: 26,
                    transFontSize: 15,
                    modeFontSize: 14,
                    cornerRadius: 24,
                    barCount: 11,
                    barWidth: 5.0,
                    barSpacing: 6.0,
                    minBarHeight: 8,
                    maxBarHeight: 44
                )
            }
        }
    }

    private var layout: LayoutConstants {
        LayoutConstants.get(for: self.settings.overlaySize)
    }

    private var modeColor: Color {
        self.contentState.mode.notchColor
    }

    private var modeLabel: String {
        switch self.contentState.mode {
        case .dictation: return "Dictate"
        case .edit, .rewrite, .write: return "Edit"
        case .command: return "Command"
        }
    }

    private var processingLabel: String {
        switch self.contentState.mode {
        case .dictation: return "Refining..."
        case .edit, .rewrite, .write: return "Thinking..."
        case .command: return "Working..."
        }
    }

    // ContentView writes transient status strings into transcriptionText while processing
    // (e.g. "Transcribing...", "Refining..."). Prefer that when present.
    private var processingStatusText: String {
        let t = self.contentState.transcriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? self.processingLabel : t
    }

    private var hasTranscription: Bool {
        !self.contentState.transcriptionText.isEmpty
    }

    private var isPromptSelectableMode: Bool {
        self.contentState.mode == .dictation ||
            self.contentState.mode == .edit ||
            self.contentState.mode == .write ||
            self.contentState.mode == .rewrite
    }

    private var selectedPromptLabel: String {
        if let profile = self.settings.selectedPromptProfile(for: self.contentState.promptPickerMode) {
            let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Untitled" : name
        }
        return "Default"
    }

    private var promptSelectorFontSize: CGFloat {
        max(self.layout.modeFontSize - 1, 9)
    }

    private var promptSelectorVerticalPadding: CGFloat {
        4
    }

    private var promptMenuGap: CGFloat {
        max(4, self.layout.vPadding * 0.35)
    }

    private var promptSelectorCornerRadius: CGFloat {
        max(self.layout.cornerRadius * 0.42, 8)
    }

    private var promptSelectorMaxWidth: CGFloat {
        self.layout.waveformWidth * 1.75
    }

    private var previewMaxHeight: CGFloat {
        self.layout.transFontSize * 4.2
    }

    private var previewMaxWidth: CGFloat {
        self.layout.waveformWidth * 2.2
    }

    private var transcriptionVerticalPadding: CGFloat {
        max(4, self.layout.vPadding / 2)
    }

    private var transcriptionPreviewText: String {
        self.contentState.cachedPreviewText
    }

    private func closePromptMenu() {
        BottomOverlayPromptMenuController.shared.hide()
    }

    private func handlePromptSelectorHover(_ hovering: Bool) {
        guard self.isPromptSelectableMode, !self.contentState.isProcessing else {
            BottomOverlayPromptMenuController.shared.hide()
            return
        }
        BottomOverlayPromptMenuController.shared.selectorHoverChanged(hovering)
    }

    private func handlePromptSelectorFrameChange(_ frameInScreen: CGRect, window: NSWindow?) {
        guard self.isPromptSelectableMode, !self.contentState.isProcessing else {
            BottomOverlayPromptMenuController.shared.hide()
            return
        }

        BottomOverlayPromptMenuController.shared.updateAnchor(
            selectorFrameInScreen: frameInScreen,
            parentWindow: window,
            maxWidth: self.promptSelectorMaxWidth,
            menuGap: self.promptMenuGap
        )
    }

    private var promptSelectorTrigger: some View {
        HStack(spacing: 5) {
            Text("Prompt:")
                .font(.system(size: self.promptSelectorFontSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Text(self.selectedPromptLabel)
                .font(.system(size: self.promptSelectorFontSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
            Image(systemName: "chevron.up")
                .font(.system(size: max(self.promptSelectorFontSize - 1, 8), weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, self.promptSelectorVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: self.promptSelectorCornerRadius)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: self.promptSelectorCornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.14),
                                    Color.white.opacity(0.08),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    private var promptSelectorView: some View {
        self.promptSelectorTrigger
            .background(
                PromptSelectorAnchorReader { frameInScreen, window in
                    self.handlePromptSelectorFrameChange(frameInScreen, window: window)
                }
                .allowsHitTesting(false)
            )
            .frame(maxWidth: self.promptSelectorMaxWidth, alignment: .center)
            .contentShape(Rectangle())
            .onHover { hovering in
                self.handlePromptSelectorHover(hovering)
            }
            .onTapGesture {
                guard self.isPromptSelectableMode, !self.contentState.isProcessing else { return }
                BottomOverlayPromptMenuController.shared.selectorHoverChanged(true)
            }
    }

    var body: some View {
        VStack(spacing: max(4, self.layout.vPadding / 2)) {
            if self.isPromptSelectableMode && !self.contentState.isProcessing {
                self.promptSelectorView
            }

            VStack(spacing: self.layout.vPadding / 2) {
                // Transcription text area (wrapped)
                Group {
                    if self.hasTranscription && !self.contentState.isProcessing {
                        let previewText = self.transcriptionPreviewText
                        if !previewText.isEmpty {
                            ScrollViewReader { proxy in
                                ScrollView(.vertical, showsIndicators: false) {
                                    Text(previewText)
                                        .font(.system(size: self.layout.transFontSize, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.9))
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Color.clear.frame(height: 1).id("bottom")
                                }
                                .frame(width: self.previewMaxWidth)
                                .frame(maxHeight: self.previewMaxHeight)
                                .clipped()
                                .onAppear {
                                    DispatchQueue.main.async {
                                        proxy.scrollTo("bottom", anchor: .bottom)
                                    }
                                }
                                .onChange(of: previewText) { _, _ in
                                    DispatchQueue.main.async {
                                        proxy.scrollTo("bottom", anchor: .bottom)
                                    }
                                }
                            }
                            .padding(.vertical, self.transcriptionVerticalPadding)
                        }
                    } else if self.contentState.isProcessing {
                        ShimmerText(
                            text: self.processingStatusText,
                            color: self.modeColor,
                            font: .system(size: self.layout.transFontSize, weight: .medium)
                        )
                    }
                }
                .frame(
                    maxWidth: self.previewMaxWidth,
                    minHeight: self.hasTranscription || self.contentState.isProcessing ? self.layout.transFontSize * 1.5 : 0
                )

                // Waveform + Mode label row
                HStack(spacing: self.layout.hPadding / 1.5) {
                    // Target app icon (the app where text will be typed)
                    if let appIcon = contentState.targetAppIcon {
                        let showModelLoading = !self.appServices.asr.isAsrReady &&
                            (self.appServices.asr.isLoadingModel || self.appServices.asr.isDownloadingModel)
                        VStack(spacing: 2) {
                            if showModelLoading {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                            Image(nsImage: appIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: self.layout.iconSize, height: self.layout.iconSize)
                                .clipShape(RoundedRectangle(cornerRadius: self.layout.iconSize / 4))
                        }
                    }

                    // Waveform visualization
                    BottomWaveformView(color: self.modeColor, layout: self.layout)
                        .frame(width: self.layout.waveformWidth, height: self.layout.waveformHeight)

                    // Mode label + model load hint
                    VStack(alignment: .leading, spacing: 2) {
                        Text(self.modeLabel)
                            .font(.system(size: self.layout.modeFontSize, weight: .semibold))
                            .foregroundStyle(self.modeColor)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .onHover { hovering in
                                self.handlePromptSelectorHover(hovering)
                            }
                            .onTapGesture {
                                guard self.isPromptSelectableMode, !self.contentState.isProcessing else { return }
                                BottomOverlayPromptMenuController.shared.selectorHoverChanged(true)
                            }

                        if !self.appServices.asr.isAsrReady &&
                            (self.appServices.asr.isLoadingModel || self.appServices.asr.isDownloadingModel)
                        {
                            Text("Loading model…")
                                .font(.system(size: max(self.layout.modeFontSize - 2, 9), weight: .medium))
                                .foregroundStyle(.orange.opacity(0.85))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, self.layout.hPadding)
            .padding(.vertical, self.layout.vPadding)
            .background(
                ZStack {
                    // Solid pitch black background
                    RoundedRectangle(cornerRadius: self.layout.cornerRadius)
                        .fill(Color.black)

                    // Inner border
                    RoundedRectangle(cornerRadius: self.layout.cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.08),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
            )
        }
        .onChange(of: self.contentState.cachedPreviewText) { _, _ in
            BottomOverlayWindowController.shared.refreshSizeForContent()
        }
        .onChange(of: self.contentState.mode) { _, _ in
            if !self.isPromptSelectableMode || self.contentState.isProcessing {
                self.closePromptMenu()
            }
            switch self.contentState.mode {
            case .dictation: self.contentState.promptPickerMode = .dictate
            case .edit, .write, .rewrite: self.contentState.promptPickerMode = .edit
            case .command: break
            }
            BottomOverlayWindowController.shared.refreshSizeForContent()
        }
        .onChange(of: self.contentState.isProcessing) { _, processing in
            if processing {
                self.closePromptMenu()
            }
            BottomOverlayWindowController.shared.refreshSizeForContent()
        }
        .onDisappear {
            self.closePromptMenu()
        }
        // TODO: Add tap-to-expand for command mode history (future enhancement)
        // .contentShape(Rectangle())
        // .onTapGesture {
        //     if contentState.mode == .command && !contentState.commandConversationHistory.isEmpty {
        //         NotchOverlayManager.shared.onNotchClicked?()
        //     }
        // }
        .animation(.easeInOut(duration: 0.15), value: self.hasTranscription)
        .animation(.easeInOut(duration: 0.2), value: self.contentState.mode)
        .animation(.easeInOut(duration: 0.2), value: self.contentState.isProcessing)
    }
}

// MARK: - Bottom Waveform View (reads from NotchContentState)

struct BottomWaveformView: View {
    let color: Color
    let layout: BottomOverlayView.LayoutConstants

    @ObservedObject private var contentState = NotchContentState.shared
    // Initialize with max possible bar count (11 for large) to prevent index-out-of-range before onAppear
    @State private var barHeights: [CGFloat] = Array(repeating: 6, count: 11)
    @State private var noiseThreshold: CGFloat = .init(SettingsStore.shared.visualizerNoiseThreshold)

    private var barCount: Int { self.layout.barCount }
    private var barWidth: CGFloat { self.layout.barWidth }
    private var barSpacing: CGFloat { self.layout.barSpacing }
    private var minHeight: CGFloat { self.layout.minBarHeight }
    private var maxHeight: CGFloat { self.layout.maxBarHeight }

    private var currentGlowIntensity: CGFloat {
        self.contentState.isProcessing ? 0.0 : 0.5
    }

    private var currentGlowRadius: CGFloat {
        self.contentState.isProcessing ? 0.0 : 4
    }

    /// Safe accessor for bar heights to prevent index-out-of-range crashes
    private func safeBarHeight(at index: Int) -> CGFloat {
        guard index >= 0 && index < self.barHeights.count else {
            return self.minHeight
        }
        return self.barHeights[index]
    }

    var body: some View {
        HStack(spacing: self.barSpacing) {
            ForEach(0..<self.barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: self.barWidth / 2)
                    .fill(self.color)
                    .frame(width: self.barWidth, height: self.safeBarHeight(at: index))
                    .shadow(color: self.color.opacity(self.currentGlowIntensity), radius: self.currentGlowRadius, x: 0, y: 0)
            }
        }
        .onChange(of: self.contentState.bottomOverlayAudioLevel) { _, level in
            if !self.contentState.isProcessing {
                self.updateBars(level: level)
            }
        }
        .onChange(of: self.contentState.isProcessing) { _, processing in
            if processing {
                self.setFlatProcessingBars()
            } else {
                // Resume from silence; next audio tick will animate up.
                self.updateBars(level: 0)
            }
        }
        .onChange(of: self.layout.barCount) { _, newCount in
            self.barHeights = Array(repeating: self.minHeight, count: newCount)
        }
        .onAppear {
            // Ensure bar count matches current layout
            if self.barHeights.count != self.barCount {
                self.barHeights = Array(repeating: self.minHeight, count: self.barCount)
            }
            if self.contentState.isProcessing {
                self.setFlatProcessingBars()
            } else {
                self.updateBars(level: 0)
            }
        }
        .onDisappear {
            // No timers to clean up.
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            // Update threshold when user changes sensitivity setting
            let newThreshold = CGFloat(SettingsStore.shared.visualizerNoiseThreshold)
            if newThreshold != self.noiseThreshold {
                self.noiseThreshold = newThreshold
            }
        }
    }

    private func setFlatProcessingBars() {
        // Ensure array is properly sized before modifying
        guard self.barHeights.count >= self.barCount else { return }

        // During AI processing we want the visualizer to settle to silence (flat).
        withAnimation(.easeOut(duration: 0.18)) {
            for i in 0..<self.barCount {
                self.barHeights[i] = self.minHeight
            }
        }
    }

    private func updateBars(level: CGFloat) {
        // Ensure array is properly sized before modifying
        guard self.barHeights.count >= self.barCount else { return }

        let normalizedLevel = min(max(level, 0), 1)
        let isActive = normalizedLevel > self.noiseThreshold // Use user's sensitivity setting

        withAnimation(.spring(response: 0.08, dampingFraction: 0.55)) {
            for i in 0..<self.barCount {
                let centerDistance = abs(CGFloat(i) - CGFloat(self.barCount - 1) / 2)
                let centerFactor = 1.0 - (centerDistance / CGFloat(self.barCount / 2)) * 0.3

                if isActive, self.noiseThreshold < 1.0 {
                    // Amplify the level for more dramatic response
                    // Safety check: ensure denominator is never zero
                    let denominator = max(1.0 - self.noiseThreshold, 0.001)
                    let adjustedLevel = max(min((normalizedLevel - self.noiseThreshold) / denominator, 1.0), 0.0)

                    let amplifiedLevel = pow(adjustedLevel, 0.6) // More responsive to quieter sounds
                    let randomVariation = CGFloat.random(in: 0.8...1.0)
                    self.barHeights[i] = self.minHeight + (self.maxHeight - self.minHeight) * amplifiedLevel * centerFactor * randomVariation
                } else {
                    self.barHeights[i] = self.minHeight
                }
            }
        }
    }
}
