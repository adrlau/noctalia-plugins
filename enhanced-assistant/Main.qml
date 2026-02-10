import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import "ProviderLogic.js" as ProviderLogic
import "Constants.js" as Constants

Item {
  id: root

  property var pluginApi: null
  property string _responseBuffer: ""

  // AI Chat state
  property var messages: []
  property bool isGenerating: false
  property string currentResponse: ""
  property var currentToolCalls: []
  property string errorMessage: ""
  property bool isManuallyStopped: false

  // Tool Confirmation State
  property var pendingToolCall: null // { id, name, args }
  property var processedToolCallIds: [] // Track which tool calls have been prompted for confirmation
  property var executingToolCallIds: [] // Track which tool calls are currently executing
  property var sentToolResultIds: [] // Track which tool results have been sent back to the API
  property string lastToolCallId: "" // Track screenshot tool calls
  property bool screenshotInProgress: false
  property int clipboardRetries: 0 // Track clipboard retries

  // Cache directory for state (messages)
  readonly property string cacheDir: typeof Settings !== 'undefined' && Settings.cacheDir ? Settings.cacheDir + "plugins/enhanced-assistant/" : ""
  readonly property string stateCachePath: cacheDir + "state.json"
  readonly property string tempPayloadPath: cacheDir + "payload.json"

  property string chatInputText: "" // Chat input state
  property int chatInputCursorPosition: 0 // Chat input cursor position
  property var pendingImages: [] // Array of { url: "path/to/local/preview", base64: "..." }

  // Tool Definitions
  readonly property var toolDefinitions: [
    {
      "type": "function",
      "function": {
        "name": "mouse_move",
        "description": "Move the mouse cursor to a specific coordinate",
        "parameters": {
          "type": "object",
          "properties": {
            "x": { "type": "integer", "description": "X coordinate" },
            "y": { "type": "integer", "description": "Y coordinate" }
          },
          "required": ["x", "y"]
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "mouse_click",
        "description": "Click a mouse button",
        "parameters": {
          "type": "object",
          "properties": {
            "button": { "type": "string", "description": "Button to click (left, right, middle)", "enum": ["left", "right", "middle"] }
          },
          "required": ["button"]
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "type_text",
        "description": "Type text using the keyboard",
        "parameters": {
          "type": "object",
          "properties": {
            "text": { "type": "string", "description": "Text to type" }
          },
          "required": ["text"]
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "take_screenshot",
        "description": "Take a screenshot of the current screen and add it to the chat"
      }
    },
    {
      "type": "function",
      "function": {
        "name": "spawn_application",
        "description": "Spawn an application using niri msg action spawn",
        "parameters": {
          "type": "object",
          "properties": {
            "command": { "type": "string", "description": "Command to run (e.g. 'alacritty', 'firefox')" }
          },
          "required": ["command"]
        }
      }
    }
  ]

  // OpenAI Settings
  readonly property string model: pluginApi?.pluginSettings?.ai?.model || "gpt-4o-mini"
  readonly property real temperature: pluginApi?.pluginSettings?.ai?.temperature || 0.7
  readonly property string systemPrompt: pluginApi?.pluginSettings?.ai?.systemPrompt || ""
  readonly property int maxImageDimension: pluginApi?.pluginSettings?.ai?.maxImageDimension || 800
  readonly property bool toolsEnabled: pluginApi?.pluginSettings?.ai?.toolsEnabled ?? true
  readonly property bool autoApproveTools: pluginApi?.pluginSettings?.ai?.autoApproveTools ?? false
  readonly property bool openaiLocal: pluginApi?.pluginSettings?.ai?.openaiLocal ?? false
  readonly property string openaiBaseUrl: {
    var url = pluginApi?.pluginSettings?.ai?.openaiBaseUrl || "";
    if (url === "")
      return "https://api.openai.com/v1/chat/completions";
    return url;
  }

  // Environment variable API key - priority over settings
  readonly property string envApiKey: Quickshell.env("NOCTALIA_EA_OPENAI_API_KEY") || ""
  readonly property string settingsApiKey: pluginApi?.pluginSettings?.ai?.apiKey || ""
  readonly property string apiKey: envApiKey !== "" ? envApiKey : settingsApiKey
  readonly property bool apiKeyManagedByEnv: envApiKey !== ""

  property bool hasDependencies: true
  property string dependencyError: ""

  Component.onCompleted: {
    Logger.i("EnhancedAssistant", "Plugin initialized");
    ensureCacheDir();
    checkDependencies();
  }

  function takeScreenshotAndPaste() {
    screenshotTimer.start();
  }

  Timer {
    id: screenshotTimer
    interval: 500
    onTriggered: {
      if (pluginApi) {
        pluginApi.withCurrentScreen(function (screen) {
          pluginApi.closePanel(screen);
          screenshotProcess.running = true;
        });
      }
    }
  }

  Process {
    id: screenshotProcess
    command: ["niri", "msg", "action", "screenshot-screen"]
    onExited: (exitCode) => {
      postScreenshotTimer.start();
    }
  }

  Timer {
    id: postScreenshotTimer
    interval: 2000 // Increased from 500/1500 as requested
    onTriggered: {
      if (pluginApi) {
        pluginApi.withCurrentScreen(function (screen) {
          pluginApi.openPanel(screen);
          // Wait a bit for clipboard to update before pasting
          Qt.callLater(() => {
            // For manual screenshots (not tool), just paste the image
            if (!root.lastToolCallId) {
                root.tryPasteImage();
                return;
            }
            // For tool-initiated screenshots, wait for image processing
            root.tryPasteImage();
          });
        });
      }
    }
  }

  Timer {
    id: clipboardRetryTimer
    interval: 500
    onTriggered: clipboardTypeChecker.running = true
  }

  function handleScreenshotError(reason) {
    if (root.screenshotInProgress && root.lastToolCallId) {
        root.screenshotInProgress = false;
        var callId = root.lastToolCallId;
        root.lastToolCallId = "";
        root.pendingToolCall = null;
        
        // Use sendToolResult for errors as it handles the standard flow
        sendToolResult(callId, "Error: " + reason);
    } else {
        Logger.w("EnhancedAssistant", "Screenshot failed: " + reason);
        root.screenshotInProgress = false;
    }
  }
  
  // Watch for image processing completion for screenshot tool
  onPendingImagesChanged: {
    if (root.screenshotInProgress && root.pendingImages.length > 0) {
        var callId = root.lastToolCallId;
        root.lastToolCallId = "";
        root.pendingToolCall = null;
        root.screenshotInProgress = false;

        // 1. Add tool result FIRST (to close the tool call)
        addMessage("tool", "Screenshot captured successfully.", [], null, callId);
        root.sentToolResultIds.push(callId);
        
        // 2. Add user message with image SECOND (as new context)
        addMessage("user", "Here is the screenshot.", root.pendingImages.map(img => img.base64));
        root.pendingImages = [];

        // 3. Trigger request manually
        Qt.callLater(function() {
            if (!root.isGenerating) {
                root.isGenerating = true;
            }
            root.currentResponse = "";
            root.currentToolCalls = [];
            sendOpenAIRequest();
        });
    }
  }

  function ensureCacheDir() {
    if (cacheDir) {
      Quickshell.execDetached(["mkdir", "-p", cacheDir]);
    }
  }

  function checkDependencies() {
    dependencyChecker.running = true;
  }

  Process {
    id: dependencyChecker
    command: ["sh", "-c", "which ffmpeg && which wl-paste && which ydotool"]
    onExited: (exitCode) => {
      if (exitCode !== 0) {
        root.hasDependencies = false;
        root.dependencyError = "Missing dependencies (ffmpeg, wl-paste, or ydotool). Multimodal and tool support limited.";
        Logger.w("EnhancedAssistant", root.dependencyError);
      }
    }
  }

  function tryPasteImage() {
    if (!root.hasDependencies) {
      handleScreenshotError("Missing dependencies");
      return;
    }
    root.clipboardRetries = 0;
    clipboardTypeChecker.running = true;
  }

  Process {
    id: clipboardTypeChecker
    command: ["wl-paste", "--list-types"]
    stdout: StdioCollector {}
    onExited: (exitCode) => {
      if (exitCode === 0) {
        var types = stdout.text;
        if (types.indexOf("image/png") !== -1) {
          processClipboardImage("image/png");
          return;
        }
        if (types.indexOf("image/jpeg") !== -1) {
          processClipboardImage("image/jpeg");
          return;
        }
      }

      // Retry or fail
      if (root.clipboardRetries < 5) {
          root.clipboardRetries++;
          Logger.d("EnhancedAssistant", "Clipboard image not found, retrying... (" + root.clipboardRetries + "/5)");
          clipboardRetryTimer.start();
      } else {
          handleScreenshotError("Clipboard does not contain an image or format is unsupported");
      }
    }
  }

  function processClipboardImage(mimeType) {
    if (imageProcessor.running) imageProcessor.terminate();
    
    var tempId = Date.now().toString();
    imageProcessor.tempId = tempId;
    
    var rawPath = cacheDir + "raw_" + tempId + ".png";
    var compressedPath = cacheDir + "comp_" + tempId + ".jpg";
    
    Logger.d("EnhancedAssistant", "Processing clipboard image with max dimension: " + root.maxImageDimension);

    // Be explicit with wl-paste type if known
    var typeFlag = mimeType ? `-t "${mimeType}"` : "";

    // Added debug listing of compressed file size
    var cmd = `wl-paste ${typeFlag} > "${rawPath}" && ` +
              `ffmpeg -i "${rawPath}" -vf "scale='if(gt(iw,ih),min(${root.maxImageDimension},iw),-1)':'if(gt(ih,iw),min(${root.maxImageDimension},ih),-1)'" -q:v 10 "${compressedPath}" && ` +
              `ls -lh "${compressedPath}" && ` +
              `base64 -w0 "${compressedPath}" && ` +
              `rm "${rawPath}"`;
              
    imageProcessor.command = ["sh", "-c", cmd];
    imageProcessor.running = true;
  }

  function processImageFile(url) {
    if (imageProcessor.running) imageProcessor.terminate();

    var path = url.replace("file://", "");
    var tempId = Date.now().toString();
    
    imageProcessor.tempId = tempId;
    
    var compressedPath = cacheDir + "comp_" + tempId + ".jpg";
    
    var cmd = `ffmpeg -i "${path}" -vf "scale='if(gt(iw,ih),min(${root.maxImageDimension},iw),-1)':'if(gt(ih,iw),min(${root.maxImageDimension},ih),-1)'" -q:v 10 "${compressedPath}" && ` +
              `ls -lh "${compressedPath}" && ` +
              `base64 -w0 "${compressedPath}"`;
              
    imageProcessor.command = ["sh", "-c", cmd];
    imageProcessor.running = true;
  }

  Process {
    id: imageProcessor
    property string tempId: ""
    
    stdout: StdioCollector {}
    onExited: (exitCode) => {
      if (exitCode === 0) {
        var output = stdout.text.trim();
        // The output will contain the ls -lh line followed by the base64 string
        // We need to extract just the base64 string (last line usually)
        var lines = output.split('\n');
        var b64 = lines[lines.length - 1];
        
        // Log the size info for debugging
        if (lines.length > 1) {
            Logger.d("EnhancedAssistant", "Compressed image info: " + lines[0]);
        }
        
        var compressedPath = cacheDir + "comp_" + tempId + ".jpg";
        
        root.pendingImages = [...root.pendingImages, {
          "path": "file://" + compressedPath,
          "base64": "data:image/jpeg;base64," + b64
        }];
      } else {
        Logger.e("EnhancedAssistant", "Image processing failed with exit code " + exitCode);
        handleScreenshotError("Image processing failed");
      }
    }
  }

  function removePendingImage(index) {
    var updated = [...root.pendingImages];
    var img = updated[index];
    if (img) {
      var path = img.path.replace("file://", "");
      Quickshell.execDetached(["rm", path]);
    }
    updated.splice(index, 1);
    root.pendingImages = updated;
  }

  // FileView for state cache (messages)
  FileView {
    id: stateCacheFile
    path: root.stateCachePath
    watchChanges: false

    onLoaded: {
      loadStateFromCache();
    }

    onLoadFailed: function (error) {
      if (error === 2) {
        Logger.d("EnhancedAssistant", "No cache file found, starting fresh");
      } else {
        Logger.e("EnhancedAssistant", "Failed to load state cache: " + error);
      }
    }
  }

  // Temporary payload file for API requests
  FileView {
    id: payloadFile
    path: root.tempPayloadPath
    watchChanges: false
    // Block the UI thread until the write completes. This prevents a race
    // condition where curl starts before the new payload is on disk and reads
    // the stale payload from the previous request. The payload is just a JSON
    // string so the block is negligible.
    blockWrites: true
  }

  function loadStateFromCache() {
    var content = stateCacheFile.text();
    var result = ProviderLogic.processLoadedState(content);

    if (!result) return;
    if (result.error) {
      Logger.e("EnhancedAssistant", "Failed to parse state cache: " + result.error);
      return;
    }

    root.messages = result.messages;
    root.chatInputText = result.chatInputText;
    root.chatInputCursorPosition = result.chatInputCursorPosition;
    root.processedToolCallIds = []; // Clear tool tracking on load
    root.executingToolCallIds = [];
    root.sentToolResultIds = [];
    root.pendingToolCall = null;
    root.lastToolCallId = "";
    root.currentToolCalls = [];
    root.screenshotInProgress = false;
    Logger.i("EnhancedAssistant", "Loaded state: " + root.messages.length + " messages");
  }

  // Debounced save timer
  Timer {
    id: saveStateTimer
    interval: 500
    onTriggered: performSaveState()
  }

  property bool saveStateQueued: false

  function saveState() {
    saveStateQueued = true;
    saveStateTimer.restart();
  }

  function saveStateImmediate() {
    saveStateQueued = true;
    performSaveState();
  }

  function performSaveState() {
    if (!saveStateQueued || !cacheDir)
      return;
    saveStateQueued = false;

    try {
      ensureCacheDir();
      var maxHistory = pluginApi?.pluginSettings?.ai?.maxHistoryLength || 100;
      var dataStr = ProviderLogic.prepareStateForSave(
        root.messages,
        maxHistory,
        root.chatInputText,
        root.chatInputCursorPosition
      );
      stateCacheFile.setText(dataStr);
      Logger.d("EnhancedAssistant", "State saved: " + root.messages.length + " messages");
    } catch (e) {
      Logger.e("EnhancedAssistant", "Failed to save state cache: " + e);
    }
  }

  function addMessage(role, content, images, tool_calls, tool_call_id) {
    var newMessage = {
      "id": Date.now().toString(),
      "role": role,
      "content": content || null,
      "images": images || [],
      "tool_calls": tool_calls || null,
      "tool_call_id": tool_call_id || null,
      "timestamp": new Date().toISOString()
    };
    root.messages = [...root.messages, newMessage];
    saveState();
    return newMessage;
  }

  function clearMessages() {
    Logger.i("EnhancedAssistant", "Clearing chat history...");
    root.messages = [];
    root.processedToolCallIds = [];
    root.executingToolCallIds = [];
    root.sentToolResultIds = [];
    root.pendingToolCall = null;
    root.lastToolCallId = "";
    root.currentToolCalls = [];
    root.screenshotInProgress = false;
    root.pendingImages = [];
    root.isGenerating = false;
    root.isManuallyStopped = false;
    root.chatInputText = "";
    root.chatInputCursorPosition = 0;
    // Use immediate save to ensure state is persisted before any new messages
    saveStateImmediate();
    Logger.i("EnhancedAssistant", "Chat history cleared and saved");
  }

  function sendMessage(userMessage) {
    if ((!userMessage || userMessage.trim() === "") && root.pendingImages.length === 0) return;
    if (root.isGenerating) return;

    if (!openaiLocal && (!apiKey || apiKey.trim() === "")) {
      root.errorMessage = pluginApi?.tr("errors.noApiKey") || "Please configure your API key in settings";
      ToastService.showError(root.errorMessage);
      return;
    }

    // Clear processed tool call IDs on new user message to prevent stale data
    root.processedToolCallIds = [];
    root.executingToolCallIds = [];
    root.sentToolResultIds = [];
    
    Logger.i("EnhancedAssistant", "Sending message with " + root.messages.length + " messages in history");
    
    addMessage("user", userMessage.trim(), root.pendingImages.map(img => img.base64));
    root.pendingImages = [];

    root.isGenerating = true;
    root.isManuallyStopped = false;
    root.currentResponse = "";
    root.currentToolCalls = [];
    root.errorMessage = "";

    sendOpenAIRequest();
  }

  function editMessage(id, newContent) {
    if (root.isGenerating) return;
    if (!newContent || newContent.trim() === "") return;
    var index = -1;
    for (var i = 0; i < root.messages.length; i++) {
      if (root.messages[i].id === id) {
        index = i;
        break;
      }
    }
    if (index === -1) return;
    root.messages = root.messages.slice(0, index);
    sendMessage(newContent);
  }

  function regenerateLastResponse() {
    if (root.isGenerating || root.messages.length < 2) return;

    var lastIndex = -1;
    for (var i = root.messages.length - 1; i >= 0; i--) {
      if (root.messages[i].role === "assistant") {
        lastIndex = i;
        break;
      }
    }

    if (lastIndex >= 0) {
      root.messages = root.messages.slice(0, lastIndex);
      saveState();
      root.isGenerating = true;
      root.currentResponse = "";
      root.currentToolCalls = [];
      root.errorMessage = "";
      sendOpenAIRequest();
    }
  }

  function stopGeneration() {
    if (!root.isGenerating) return;
    root.isManuallyStopped = true;
    if (openaiProcess.running) openaiProcess.running = false;
    root.isGenerating = false;
    if (root.currentResponse.trim() !== "" || root.currentToolCalls.length > 0) {
        // Save current progress if any
        addMessage("assistant", root.currentResponse.trim(), [], root.currentToolCalls.length > 0 ? root.currentToolCalls : null);
    }
    root.currentResponse = "";
    root.currentToolCalls = [];
  }

  function buildConversationHistory() {
    var history = [];
    for (var i = 0; i < root.messages.length; i++) {
      var msg = root.messages[i];
      var entry = {
        "role": msg.role,
        "content": msg.content,
        "images": msg.images || []
      };
      if (msg.tool_calls) entry.tool_calls = msg.tool_calls;
      if (msg.tool_call_id) entry.tool_call_id = msg.tool_call_id;
      history.push(entry);
    }
    Logger.d("EnhancedAssistant", "Building conversation history with " + history.length + " messages");
    return history;
  }

  Process {
    id: openaiProcess
    property string buffer: ""

    stdout: SplitParser {
      onRead: function (data) {
        openaiProcess.handleStreamData(data);
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text && text.trim() !== "") {
          Logger.e("EnhancedAssistant", "OpenAI stderr: " + text);
        }
      }
    }

    function handleStreamData(data) {
      var result = ProviderLogic.parseOpenAIStream(data);
      if (!result) return;
      
      if (result.content) {
        root.currentResponse += result.content;
      } else if (result.tool_calls) {
        for (var i = 0; i < result.tool_calls.length; i++) {
          var call = result.tool_calls[i];
          var index = call.index;
          
          if (!root.currentToolCalls[index]) {
            root.currentToolCalls[index] = {
              "id": call.id || "",
              "type": "function",
              "function": {
                "name": (call.function && call.function.name) ? call.function.name : "",
                "arguments": (call.function && call.function.arguments) ? call.function.arguments : ""
              }
            };
          } else {
            if (call.id) root.currentToolCalls[index].id = call.id;
            if (call.function && call.function.name) root.currentToolCalls[index].function.name += call.function.name;
            if (call.function && call.function.arguments) root.currentToolCalls[index].function.arguments += call.function.arguments;
          }
        }
      } else if (result.error) {
        Logger.e("EnhancedAssistant", "OpenAI stream error: " + result.error);
      }
    }

    onExited: function (exitCode, exitStatus) {
      if (root.isManuallyStopped) {
        root.isManuallyStopped = false;
        return;
      }
      root.isGenerating = false;
      if (exitCode !== 0 && root.currentResponse === "" && root.currentToolCalls.length === 0) {
        if (root.errorMessage === "") {
          root.errorMessage = openaiLocal ? "Local inference server is not reachable." : "Request failed";
        }
        return;
      }

      if (root.currentResponse.trim() !== "" || root.currentToolCalls.length > 0) {
        addMessage("assistant", root.currentResponse.trim(), [], root.currentToolCalls.length > 0 ? root.currentToolCalls : null);
        
        if (root.currentToolCalls.length > 0 && toolsEnabled) {
            // Filter out already processed tool calls
            var newToolCalls = [];
            for (var j = 0; j < root.currentToolCalls.length; j++) {
                var tc = root.currentToolCalls[j];
                if (root.processedToolCallIds.indexOf(tc.id) === -1) {
                    newToolCalls.push(tc);
                }
            }
            
            if (newToolCalls.length > 0) {
                // We only handle one tool call at a time for simplicity with confirmation
                var firstCall = newToolCalls[0];
                root.pendingToolCall = {
                    "id": firstCall.id,
                    "name": firstCall.function.name,
                    "args": firstCall.function.arguments
                };
                
                // Mark this tool call as processed
                root.processedToolCallIds.push(firstCall.id);
                // Limit array size to prevent memory growth
                if (root.processedToolCallIds.length > 100) {
                    root.processedToolCallIds = root.processedToolCallIds.slice(-50);
                }
                
                // Auto-approve if setting is enabled
                if (root.autoApproveTools) {
                    Qt.callLater(function() {
                        confirmToolExecution(true);
                    });
                }
            }
        }
      }
      
      root.chatInputText = "";
      root.chatInputCursorPosition = 0;
      root.saveState();
      openaiProcess.buffer = "";
      root.currentToolCalls = [];
    }
  }

  function confirmToolExecution(confirmed) {
    if (!root.pendingToolCall) return;
    
    var call = root.pendingToolCall;
    root.pendingToolCall = null;

    // Check if already executing
    if (root.executingToolCallIds.indexOf(call.id) !== -1) {
        Logger.w("EnhancedAssistant", "Tool call " + call.id + " is already executing, skipping");
        return;
    }
    
    // Mark as executing
    root.executingToolCallIds.push(call.id);

    if (!confirmed) {
        sendToolResult(call.id, "User rejected tool execution.");
        return;
    }

    var args = {};
    try {
        args = JSON.parse(call.args);
    } catch (e) {}

    switch (call.name) {
        case "take_screenshot":
            // Start screenshot timer directly - postScreenshotTimer will handle result
            root.lastToolCallId = call.id;
            root.screenshotInProgress = true;
            screenshotTimer.start();
            break;
        case "mouse_move":
        case "mouse_click":
        case "type_text":
            // Hide panel so it doesn't interfere with desktop interaction
            ensureYdotooldRunning();
            root.hidePanelAndRunTool(call);
            break;
        case "spawn_application":
            toolProcess.toolName = "spawn_application";
            toolProcess.reopenPanel = false;
            toolProcess.command = ["niri", "msg", "action", "spawn", "--", args.command];
            toolProcess.callId = call.id;
            toolProcess.running = true;
            break;
        default:
            sendToolResult(call.id, "Error: Unknown tool " + call.name);
    }
  }

  // Hides the panel, waits briefly for the compositor to process the change,
  // then starts the actual tool process. This prevents the panel from
  // stealing focus or blocking mouse/keyboard interactions on the desktop.
  function hidePanelAndRunTool(call) {
    var args = {};
    try { args = JSON.parse(call.args); } catch (e) {}

    var cmd;
    switch (call.name) {
      case "mouse_move":
        var x = args.x || 0;
        var y = args.y || 0;
        cmd = ["sh", "-c", "ydotool mousemove -- " + x + " " + y + " 2>&1"];
        break;
      case "mouse_click":
        var btn = "0xC0"; // Left
        if (args.button === "right") btn = "0xC1";
        if (args.button === "middle") btn = "0xC2";
        cmd = ["sh", "-c", "ydotool click " + btn + " 2>&1"];
        break;
      case "type_text":
        var text = (args.text || "").replace(/"/g, '\\"');
        cmd = ["sh", "-c", "ydotool type \"" + text + "\" 2>&1"];
        break;
    }

    toolProcess.toolName = call.name;
    toolProcess.callId = call.id;
    toolProcess.reopenPanel = true;
    toolProcess._pendingCommand = cmd;

    if (pluginApi) {
      pluginApi.withCurrentScreen(function (screen) {
        pluginApi.closePanel(screen);
        // Brief delay so the compositor can hide the panel before the tool acts
        panelHideToolTimer.start();
      });
    } else {
      // Fallback: run directly if pluginApi is unavailable
      toolProcess.command = cmd;
      toolProcess.running = true;
    }
  }

  Timer {
    id: panelHideToolTimer
    interval: 300
    onTriggered: {
      toolProcess.command = toolProcess._pendingCommand;
      toolProcess.running = true;
    }
  }

  Process {
    id: toolProcess
    property string callId: ""
    property string toolName: ""
    property bool reopenPanel: false
    property var _pendingCommand: []
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: (exitCode) => {
        var output = stdout.text || "";
        var errOutput = stderr.text || "";
        var resultMsg = "Success";
        
        // Remove from executing list
        var idx = root.executingToolCallIds.indexOf(callId);
        if (idx !== -1) {
            root.executingToolCallIds.splice(idx, 1);
        }
        
        if (exitCode !== 0) {
            resultMsg = "Failed with exit code " + exitCode;
            if (errOutput.trim() !== "") {
                resultMsg += ": " + errOutput.trim();
            } else if (output.trim() !== "") {
                resultMsg += ": " + output.trim();
            }
            
            // Check for common ydotoold not running error
            if (errOutput.indexOf("Connection refused") !== -1 || errOutput.indexOf("socket") !== -1 || exitCode === 2) {
                resultMsg += " (ydotoold daemon may not be running. Start it with: ydotoold &)";
            }
        }
        
        var savedResultMsg = resultMsg;
        var savedCallId = callId;

        // Reopen the panel if it was hidden for this tool
        if (reopenPanel && pluginApi) {
            pluginApi.withCurrentScreen(function (screen) {
                pluginApi.openPanel(screen);
                sendToolResult(savedCallId, savedResultMsg);
            });
        } else {
            sendToolResult(savedCallId, savedResultMsg);
        }
        reopenPanel = false;
    }
  }
  
  // Process to check/start ydotoold daemon
  Process {
    id: ydotooldChecker
    command: ["sh", "-c", "pgrep -x ydotoold > /dev/null || (ydotoold &)"]
    onExited: (exitCode) => {
        if (exitCode !== 0) {
            Logger.w("EnhancedAssistant", "Could not start ydotoold daemon automatically. Please start it manually.");
        }
    }
  }
  
  function ensureYdotooldRunning() {
      ydotooldChecker.running = true;
  }

  function sendToolResult(callId, result) {
    // Prevent duplicate sends
    if (root.sentToolResultIds.indexOf(callId) !== -1) {
        Logger.w("EnhancedAssistant", "Tool result already sent for " + callId + ", skipping duplicate");
        return;
    }
    
    addMessage("tool", result, [], null, callId);
    // Mark as sent to prevent duplicates
    root.sentToolResultIds.push(callId);
    // Limit array size to prevent memory growth
    if (root.sentToolResultIds.length > 100) {
        root.sentToolResultIds = root.sentToolResultIds.slice(-50);
    }
    
    // Small delay to ensure message is saved before continuing
    Qt.callLater(function() {
        if (!root.isGenerating) {
            root.isGenerating = true;
        }
        root.currentResponse = "";
        root.currentToolCalls = [];
        sendOpenAIRequest();
    });
  }

  function sendOpenAIRequest() {
    var history = buildConversationHistory();
    // Only include tools if they are enabled
    var toolsToUse = toolsEnabled ? toolDefinitions : [];
    var commandData = ProviderLogic.buildOpenAICommand(openaiBaseUrl, apiKey, model, systemPrompt, history, temperature, toolsToUse);
    
    // Write payload to temp file to avoid command line length limits.
    // blockWrites is enabled on payloadFile so this call is synchronous —
    // the file is guaranteed to be on disk before we start curl.
    payloadFile.setText(commandData.payload);
    
    // Use file-based payload delivery instead of stdin
    var args = commandData.args.slice(); // Copy array
    // Replace placeholder with the actual file path
    for (var i = 0; i < args.length; i++) {
        if (args[i] === "@PAYLOAD_PATH_PLACEHOLDER") {
            args[i] = "@" + tempPayloadPath;
            break;
        }
    }
    
    openaiProcess.buffer = "";
    openaiProcess.command = args;
    openaiProcess.running = true;
  }

  IpcHandler {
    target: "plugin:enhanced-assistant"

    function toggle() {
      if (pluginApi) {
        pluginApi.withCurrentScreen(function (screen) {
          pluginApi.togglePanel(screen);
        });
      }
    }

    function open() {
      if (pluginApi) {
        pluginApi.withCurrentScreen(function (screen) {
          pluginApi.openPanel(screen);
        });
      }
    }

    function close() {
      if (pluginApi) {
        pluginApi.withCurrentScreen(function (screen) {
          pluginApi.closePanel(screen);
        });
      }
    }

    function send(message: string) {
      if (message && message.trim() !== "") {
        root.sendMessage(message);
      }
    }

    function clear() {
      root.clearMessages();
    }

    function setModel(modelName: string) {
      if (pluginApi && modelName) {
        if (!pluginApi.pluginSettings.ai) pluginApi.pluginSettings.ai = {};
        pluginApi.pluginSettings.ai.model = modelName;
        pluginApi.saveSettings();
      }
    }
  }
}
