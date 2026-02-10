.pragma library

// ===================================
// AI Provider Logic
// ===================================

function buildOpenAICommand(endpointUrl, apiKey, model, systemPrompt, history, temperature, tools) {
  var messages = [];

  if (systemPrompt && systemPrompt.trim() !== "") {
    messages.push({
      "role": "system",
      "content": systemPrompt
    });
  }

  // Add conversation history
  for (var i = 0; i < history.length; i++) {
    var msg = history[i];
    var formattedMsg = {
      "role": msg.role
    };

    if (msg.tool_calls) {
      formattedMsg.tool_calls = msg.tool_calls;
    }

    if (msg.tool_call_id) {
      formattedMsg.tool_call_id = msg.tool_call_id;
    }

    if (msg.images && msg.images.length > 0) {
      var content = [];
      if (msg.content && msg.content.trim() !== "") {
        content.push({
          "type": "text",
          "text": msg.content
        });
      }
      for (var j = 0; j < msg.images.length; j++) {
        content.push({
          "type": "image_url",
          "image_url": {
            "url": msg.images[j]
          }
        });
      }
      formattedMsg.content = content;
    } else if (msg.content !== undefined) {
      formattedMsg.content = msg.content;
    }

    messages.push(formattedMsg);
  }

  var payload = {
    "model": model,
    "messages": messages,
    "temperature": temperature,
    "stream": true
  };

  if (tools && tools.length > 0) {
    payload.tools = tools;
  }

  var args = ["curl", "-s", "-S", "--no-buffer", "-X", "POST", "-H", "Content-Type: application/json"];

  if (apiKey && apiKey.trim() !== "") {
    args.push("-H", "Authorization: Bearer " + apiKey);
  }

  args.push("-d", "@PAYLOAD_PATH_PLACEHOLDER");
  args.push(endpointUrl);

  return {
    "url": endpointUrl,
    "payload": JSON.stringify(payload),
    "args": args
  };
}

function parseOpenAIStream(data) {
  if (!data)
    return null;
  var line = data.trim();
  if (line === "")
    return null;

  if (line.startsWith("data: ")) {
    var jsonStr = line.substring(6).trim();
    if (jsonStr === "[DONE]")
      return {
        done: true
      };

    try {
      var json = JSON.parse(jsonStr);
      if (json.choices && json.choices[0]) {
        if (json.choices[0].delta) {
          if (json.choices[0].delta.content) {
            return {
              content: json.choices[0].delta.content
            };
          } else if (json.choices[0].delta.tool_calls) {
            return {
              tool_calls: json.choices[0].delta.tool_calls
            };
          }
        } else if (json.choices[0].message) {
            if (json.choices[0].message.content) {
                return { content: json.choices[0].message.content };
            } else if (json.choices[0].message.tool_calls) {
                return { tool_calls: json.choices[0].message.tool_calls };
            }
        }
      }
    } catch (e) {
      return {
        error: "Error parsing SSE JSON: " + e
      };
    }
  } else {
    return {
      raw: line
    };
  }
  return null;
}

// ===================================
// State Management
// ===================================

function processLoadedState(content) {
  if (!content || content.trim() === "") {
    return null; // Empty state
  }
  try {
    var cached = JSON.parse(content);
    return {
      messages: cached.messages || [],
      chatInputText: cached.chatInputText || "",
      chatInputCursorPosition: cached.chatInputCursorPosition || 0
    };
  } catch (e) {
    return {
      error: e.toString()
    };
  }
}

function prepareStateForSave(messages, maxHistory, chatInputText, chatInputCursorPosition) {
  var maxLog = maxHistory || 100;
  var toSave = messages.slice(-maxLog);

  return JSON.stringify({
    messages: toSave,
    chatInputText: chatInputText || "",
    chatInputCursorPosition: chatInputCursorPosition || 0,
    timestamp: Math.floor(Date.now() / 1000)
  }, null, 2);
}
