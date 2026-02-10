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
- Fixed `StdioWriter is not a type` error by switching to file-based payload delivery instead of stdin.
- Fixed ydotool mouse/keyboard automation by adding automatic daemon startup check and better error messages.
- Added settings for enabling/disabling AI tools and auto-approving tool execution without confirmation.
- Added standalone auto-approve toggle that is always visible when tools are enabled.
- Fixed double tool execution issue by tracking processed tool call IDs and preventing duplicates.
- Fixed screenshot tool flow to automatically continue conversation after capturing image.
- Added protection against duplicate tool result submissions.
- Clear processed tool history on new user messages to prevent stale data.
- Updated default system prompt to instruct AI to use screenshots effectively - taking screenshots before and after actions to verify results.
- Fixed missing `lastToolCallId` property that was causing screenshot tool to fail.
- Fixed `clearMessages()` to properly reset all tool state (processed IDs, executing IDs, pending calls, screenshots in progress).
- Added `executingToolCallIds` tracking to prevent concurrent execution of the same tool call.
- Added `screenshotInProgress` flag to properly handle async screenshot flow.
- Fixed screenshot tool to use `pendingImages` change signal instead of race-prone `Qt.callLater`.
- Tool process now cleans up executing IDs when finished.
- Added `saveStateImmediate()` function for immediate state persistence (bypassing debounce).
- Fixed `clearMessages()` to use immediate save and clear all state including `chatInputText`.
- Added logging to `sendMessage()`, `loadStateFromCache()`, `performSaveState()`, and `buildConversationHistory()` to help debug state issues.
- Clear all tool tracking state when loading from cache to prevent stale tool data.
- Fixed race condition in `sendOpenAIRequest()`: `FileView.setText()` is asynchronous by default (`blockWrites` is false), so starting the curl process immediately after writing the payload could cause curl to read the stale payload from the previous request. Fixed by setting `blockWrites: true` on the payload `FileView`, making `setText()` synchronous. The payload is a JSON string so the UI block is negligible.
- Fixed tool call continuation: `sendToolResult()` was blocked by `processedToolCallIds` which had the call ID added earlier in `onExited` (for preventing duplicate confirmation prompts). Separated tracking into `processedToolCallIds` (confirmation prompts), `executingToolCallIds` (in-flight execution), and `sentToolResultIds` (submitted results).
- Mouse, keyboard, and click tools (`mouse_move`, `mouse_click`, `type_text`) now temporarily hide the panel before executing and reopen it after completion. This prevents the panel from stealing focus or blocking desktop interactions during automation.

### Computer Use & Tool Integration
- Implemented OpenAI Tool Calling infrastructure.
- Added `computer_action` tool allowing the AI to:
    - Take screenshots autonomously.
    - Execute `niri msg` actions (native window management).
    - Execute shell commands.
    - Type text and send key combos (via `wtype` or `ydotool`).
- The AI can now perform multi-step tasks by observing the screen and reacting with system commands.
- Integrated `uinput` support via a Python-based bridge (using available system utilities).
