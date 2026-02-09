# Development Log

## 2026-02-10 - Enhanced AI Assistant Multimodal Improvements

### Added Configuration for Image Compression
- Introduced `maxImageDimension` setting in `Settings.qml` (ranging from 256px to 2048px).
- Updated `Main.qml` to dynamically use this setting in `ffmpeg` scaling commands for both clipboard and file inputs.
- This allows users to balance between image quality and `state.json` file size.

### Improved Image Rendering in Chat
- Refactored `MessageBubble.qml` to handle varying image aspect ratios.
- Replaced fixed aspect ratio with dynamic calculation based on image `implicitWidth` and `implicitHeight`.
- Increased preview width to 320px and capped height at 400px to maintain layout consistency.

### State Persistence
- Verified that `state.json` correctly caps message history based on `maxHistoryLength`, preventing indefinite growth when using multimodal inputs.

### Image Interaction
- Added lightbox functionality to enlarge images in the chat.
- Images in `MessageBubble.qml` are now clickable, opening a semi-transparent overlay in `AiChatView.qml` with a high-resolution view of the selected image.
- Support for closing the lightbox via click-outside, close button, or Escape key.
