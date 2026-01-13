import Foundation
import MediaRemoteAdapter

/// Service that wraps MediaRemoteAdapter's MediaController to provide
/// controlled pause/resume functionality during transcription.
///
/// This service ensures we only pause media if it's currently playing,
/// and only resume if we were the ones who paused it.
@MainActor
final class MediaPlaybackService {
    static let shared = MediaPlaybackService()

    private let mediaController = MediaController()

    private init() {}

    // MARK: - Public API

    /// Pauses system media playback if something is currently playing.
    ///
    /// - Returns: `true` if we successfully paused playback, `false` if nothing was playing
    ///   or if we couldn't determine playback state.
    func pauseIfPlaying() async -> Bool {
        return await withCheckedContinuation { continuation in
            self.mediaController.getTrackInfo { [weak self] trackInfo in
                guard let self = self else {
                    continuation.resume(returning: false)
                    return
                }

                // If no track info is available, nothing is playing
                guard let trackInfo = trackInfo else {
                    DebugLogger.shared.debug(
                        "MediaPlaybackService: No track info available, nothing to pause",
                        source: "MediaPlaybackService"
                    )
                    continuation.resume(returning: false)
                    return
                }

                // Determine if media is currently playing
                // Use isPlaying if available, otherwise check playbackRate
                let isPlaying: Bool
                if let playing = trackInfo.payload.isPlaying {
                    isPlaying = playing
                } else {
                    // playbackRate of 1.0 typically means playing, 0.0 means paused
                    isPlaying = (trackInfo.payload.playbackRate ?? 0.0) > 0.0
                }

                // Log what we found
                DebugLogger.shared.debug(
                    """
                    MediaPlaybackService: Track info received
                    - App: \(trackInfo.payload.applicationName ?? "Unknown")
                    - Bundle: \(trackInfo.payload.bundleIdentifier ?? "Unknown")
                    - Title: \(trackInfo.payload.title ?? "Unknown")
                    - isPlaying: \(trackInfo.payload.isPlaying?.description ?? "nil")
                    - playbackRate: \(trackInfo.payload.playbackRate?.description ?? "nil")
                    - Determined playing: \(isPlaying)
                    """,
                    source: "MediaPlaybackService"
                )

                if isPlaying {
                    DebugLogger.shared.info(
                        "MediaPlaybackService: Media is playing, sending pause command",
                        source: "MediaPlaybackService"
                    )
                    self.mediaController.pause()
                    continuation.resume(returning: true)
                } else {
                    DebugLogger.shared.debug(
                        "MediaPlaybackService: Media is not playing, no action needed",
                        source: "MediaPlaybackService"
                    )
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Resumes media playback only if we were the ones who paused it.
    ///
    /// - Parameter wePaused: `true` if `pauseIfPlaying()` returned `true` for this session.
    func resumeIfWePaused(_ wePaused: Bool) async {
        guard wePaused else {
            DebugLogger.shared.debug(
                "MediaPlaybackService: We didn't pause media, not resuming",
                source: "MediaPlaybackService"
            )
            return
        }

        DebugLogger.shared.info(
            "MediaPlaybackService: Resuming media playback (we paused it)",
            source: "MediaPlaybackService"
        )

        // Use explicit play() command - never toggle
        mediaController.play()
    }
}
