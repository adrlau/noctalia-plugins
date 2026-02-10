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
            root.tryPasteImage();
            if (root.pendingToolCall && root.pendingToolCall.name === "take_screenshot") {
                confirmToolExecution(true);
            }
          });
        });
      }
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
    if (!root.hasDependencies) return;
    clipboardTypeChecker.running = true;
  }

  Process {
    id: clipboardTypeChecker
    command: ["wl-paste", "--list-types"]
    stdout: StdioCollector {}
    onExited: (exitCode) => {
      if (exitCode === 0) {
        var types = stdout.text;
        if (types.indexOf("image/png") !== -1 || types.indexOf("image/jpeg") !== -1) {
          processClipboardImage();
        }
      }
    }
  }

  function processClipboardImage() {
    if (imageProcessor.running) imageProcessor.terminate();
    
    var tempId = Date.now().toString();
    imageProcessor.tempId = tempId;
    
    var rawPath = cacheDir + "raw_" + tempId + ".png";
    var compressedPath = cacheDir + "comp_" + tempId + ".jpg";
    
    var cmd = `wl-paste > "${rawPath}" && ` +
              `ffmpeg -i "${rawPath}" -vf "scale='if(gt(iw,ih),min(${root.maxImageDimension},iw),-1)':'if(gt(ih,iw),min(${root.maxImageDimension},ih),-1)'" -q:v 5 "${compressedPath}" && ` +
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
    
    var cmd = `ffmpeg -i "${path}" -vf "scale='if(gt(iw,ih),min(${root.maxImageDimension},iw),-1)':'if(gt(ih,iw),min(${root.maxImageDimension},ih),-1)'" -q:v 5 "${compressedPath}" && ` +
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
        var b64 = stdout.text.trim();
        var compressedPath = cacheDir + "comp_" + tempId + ".jpg";
        
        root.pendingImages = [...root.pendingImages, {
          "path": "file://" + compressedPath,
          "base64": "data:image/jpeg;base64," + b64
        }];
      } else {
        Logger.e("EnhancedAssistant", "Image processing failed with exit code " + exitCode);
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
    Logger.d("EnhancedAssistant", "Loaded " + root.messages.length + " messages from cache");
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
    root.messages = [];
    saveState();
    Logger.i("EnhancedAssistant", "Chat history cleared");
  }

  function sendMessage(userMessage) {
    if ((!userMessage || userMessage.trim() === "") && root.pendingImages.length === 0) return;
    if (root.isGenerating) return;

    if (!openaiLocal && (!apiKey || apiKey.trim() === "")) {
      root.errorMessage = pluginApi?.tr("errors.noApiKey") || "Please configure your API key in settings";
      ToastService.showError(root.errorMessage);
      return;
    }

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
        
        if (root.currentToolCalls.length > 0) {
            // We only handle one tool call at a time for simplicity with confirmation
            var firstCall = root.currentToolCalls[0];
            root.pendingToolCall = {
                "id": firstCall.id,
                "name": firstCall.function.name,
                "args": firstCall.function.arguments
            };
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
            takeScreenshotAndPaste();
            // result is sent from postScreenshotTimer
            break;
        case "mouse_move":
            toolProcess.command = ["ydotool", "mousemove", "--", args.x.toString(), args.y.toString()];
            toolProcess.callId = call.id;
            toolProcess.running = true;
            break;
        case "mouse_click":
            var btn = "0xC0"; // Left
            if (args.button === "right") btn = "0xC1";
            if (args.button === "middle") btn = "0xC2";
            toolProcess.command = ["ydotool", "click", btn];
            toolProcess.callId = call.id;
            toolProcess.running = true;
            break;
        case "type_text":
            toolProcess.command = ["ydotool", "type", args.text];
            toolProcess.callId = call.id;
            toolProcess.running = true;
            break;
        case "spawn_application":
            toolProcess.command = ["niri", "msg", "action", "spawn", "--", args.command];
            toolProcess.callId = call.id;
            toolProcess.running = true;
            break;
        default:
            sendToolResult(call.id, "Error: Unknown tool " + call.name);
    }
  }

  Process {
    id: toolProcess
    property string callId: ""
    onExited: (exitCode) => {
        sendToolResult(callId, exitCode === 0 ? "Success" : "Failed with exit code " + exitCode);
    }
  }

  function sendToolResult(callId, result) {
    addMessage("tool", result, [], null, callId);
    root.isGenerating = true;
    sendOpenAIRequest();
  }

  function sendOpenAIRequest() {
    var history = buildConversationHistory();
    var commandData = ProviderLogic.buildOpenAICommand(openaiBaseUrl, apiKey, model, systemPrompt, history, temperature, toolDefinitions);
    
    // Write payload to temp file to avoid command line length limits
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
