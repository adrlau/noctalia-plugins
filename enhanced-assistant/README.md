# Enhanced AI Assistant Plugin for Noctalia Shell

An improved AI Chat panel plugin for Noctalia Shell with OpenAI API support.

## Features

- **OpenAI API Support**: Compatible with OpenAI, OpenRouter, Ollama, and other OpenAI-compatible endpoints.
- **Markdown & Syntax Highlighting**: Rich text formatting for AI responses.
- **KaTeX Support**: Renders mathematical formulas.
- **Conversation History**: Persistent chat history.
- **System Prompts**: Customize AI behavior.
- **Temperature Control**: Adjust response creativity.

## Installation

1. Copy the `enhanced-assistant` folder to `~/.config/noctalia/plugins/`
2. Restart Noctalia Shell
3. Enable the plugin in Settings > Plugins
4. Add the bar widget in Settings > Bar

## Configuration

### OpenAI Compatible Setup
This plugin works with any service compatible with the OpenAI Chat API.

**For Remote Services (OpenAI, OpenRouter):**
1. Enter your **Base URL** (e.g., `https://api.openai.com/v1/chat/completions`).
2. Enter your **API Key**.
3. Specify the **Model**.

**For Local Services (Ollama, LM Studio):**
1. Check "Local" (hides API Key requirement).
2. Enter your **Base URL** (e.g., `http://localhost:11434/v1/chat/completions`).
3. Ensure your local server is running.

### Environment Variables
You can set your API key via environment variable: `NOCTALIA_EA_OPENAI_API_KEY`.

## IPC Commands

Control the plugin from the command line:

```bash
# Toggle panel visibility
qs -c noctalia-shell ipc call plugin:enhanced-assistant toggle

# Open panel
qs -c noctalia-shell ipc call plugin:enhanced-assistant open

# Close panel
qs -c noctalia-shell ipc call plugin:enhanced-assistant close

# Send a message
qs -c noctalia-shell ipc call plugin:enhanced-assistant send "Hello, how are you?"

# Clear chat history
qs -c noctalia-shell ipc call plugin:enhanced-assistant clear
```

## License

MIT License
