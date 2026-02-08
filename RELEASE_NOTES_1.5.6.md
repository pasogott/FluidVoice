
## Overlay + AI processing
- Fix overlay disappearing during AI refinement; status stays visible until paste completes.
- Add left-to-right shimmer for processing status text (e.g., Transcribing/Refining) across both notch and bottom overlays.
- Flatten the voice visualizer during AI processing so the status shimmer is the primary feedback.
- Remove UI stall caused by the LLM timeout task race; rely on request/session timeout instead.

## AI Settings + Providers
- Improve provider verification errors and guidance.
- Fix Anthropic verification/auth headers and correct endpoint handling.
- Improve model listing with better error handling and Anthropic header support.

## Reliability
- Prevent crash when spamming the record hotkey (guard re-entrant ASR start).

## Streak
- Add option to exclude weekends from streak breaks.

## Assets
- Refresh app icon assets.
