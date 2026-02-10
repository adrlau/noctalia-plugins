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
- Added zoom support (up to 500%) via mouse wheel and panning via Flickable.

### Technical Improvements
- Refactored OpenAI API requests to use a temporary file for JSON payloads. This avoids "Argument list too long" errors when sending multiple or large Base64 images via `curl`.
- Integrated `ydotool` and `niri` tools for automation support.
- Implemented Function Calling / Tools support in `ProviderLogic.js` and `Main.qml`.
- Added a confirmation UI in `AiChatView.qml` to let users approve or deny AI-requested system actions.
- Increased screenshot capture delay to 2 seconds for better compositor synchronization.
- Fixed `TypeError` in `AiChatView.qml` by adding optional chaining when accessing `mainInstance.pendingImages`.

### Computer Use & Tool Integration
- Implemented OpenAI Tool Calling infrastructure.
- Added `computer_action` tool allowing the AI to:
    - Take screenshots autonomously.
    - Execute `niri msg` actions (native window management).
    - Execute shell commands.
    - Type text and send key combos (via `wtype` or `ydotool`).
- The AI can now perform multi-step tasks by observing the screen and reacting with system commands.
- Integrated `uinput` support via a Python-based bridge (using available system utilities).
