import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI
import "Constants.js" as Constants

ColumnLayout {
  id: root

  property var pluginApi: null

  // AI Settings - Local state
  property string editModel: pluginApi?.pluginSettings?.ai?.model || pluginApi?.manifest?.metadata?.defaultSettings?.ai?.model || "gpt-4o-mini"
  property string editApiKey: pluginApi?.pluginSettings?.ai?.apiKey || ""
  property real editTemperature: pluginApi?.pluginSettings?.ai?.temperature || 0.7
  property string editSystemPrompt: pluginApi?.pluginSettings?.ai?.systemPrompt || ""
  property bool editOpenAiLocal: pluginApi?.pluginSettings?.ai?.openaiLocal ?? false
  property string editOpenAiBaseUrl: pluginApi?.pluginSettings?.ai?.openaiBaseUrl || "https://api.openai.com/v1/chat/completions"
  property int editMaxHistoryLength: pluginApi?.pluginSettings?.maxHistoryLength || 100
  property int editMaxImageDimension: pluginApi?.pluginSettings?.ai?.maxImageDimension || 800

  // Panel Settings
  property bool editPanelDetached: pluginApi?.pluginSettings?.panelDetached ?? true
  property string editPanelPosition: pluginApi?.pluginSettings?.panelPosition || "right"
  property real editPanelHeightRatio: pluginApi?.pluginSettings?.panelHeightRatio || 0.85
  property int editPanelWidth: pluginApi?.pluginSettings?.panelWidth ?? 520
  property string editAttachmentStyle: pluginApi?.pluginSettings?.attachmentStyle || "connected"
  property real editScale: pluginApi?.pluginSettings?.scale || 1

  // Environment variable API key
  readonly property string envApiKey: Quickshell.env("NOCTALIA_EA_OPENAI_API_KEY") || ""
  readonly property bool apiKeyManagedByEnv: envApiKey !== ""

  spacing: Style.marginM

  NText {
    text: pluginApi?.tr("settings.panelSection") || "Panel Settings"
    pointSize: Style.fontSizeM
    font.weight: Font.Bold
    color: Color.mOnSurface
  }

  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.panelDetached") || "Detached Panel"
    checked: root.editPanelDetached
    onToggled: function (checked) {
      root.editPanelDetached = checked;
      if (checked) {
        if (root.editPanelPosition === "top" || root.editPanelPosition === "bottom") {
          root.editPanelPosition = "right";
        }
      } else {
        if (root.editPanelPosition === "center") {
          root.editPanelPosition = "right";
        }
      }
    }
  }

  NComboBox {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.panelPosition") || "Panel Position"
    model: root.editPanelDetached ? [
      { "key": "left", "name": "Left" },
      { "key": "center", "name": "Center" },
      { "key": "right", "name": "Right" }
    ] : [
      { "key": "left", "name": "Left" },
      { "key": "top", "name": "Top" },
      { "key": "bottom", "name": "Bottom" },
      { "key": "right", "name": "Right" }
    ]
    currentKey: root.editPanelPosition
    onSelected: function (key) { root.editPanelPosition = key; }
  }

  NComboBox {
    Layout.fillWidth: true
    visible: !root.editPanelDetached
    label: "Attachment Style"
    model: [
      { "key": "connected", "name": "Connected to Bar" },
      { "key": "floating", "name": "Floating (Drawer)" }
    ]
    currentKey: root.editAttachmentStyle
    onSelected: function (key) { root.editAttachmentStyle = key; }
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS
    NLabel { label: "Panel Height Ratio: " + (root.editPanelHeightRatio * 100).toFixed(0) + "%" }
    NSlider {
      Layout.fillWidth: true
      from: 0.3; to: 1.0; stepSize: 0.01
      value: root.editPanelHeightRatio
      onValueChanged: root.editPanelHeightRatio = value
    }
    NLabel { label: "Panel Width: " + root.editPanelWidth + "px" }
    NSlider {
      Layout.fillWidth: true
      from: 320; to: 1200; stepSize: 1
      value: root.editPanelWidth
      onValueChanged: root.editPanelWidth = value
    }
    NLabel { label: "UI Scale: " + (root.editScale * 100).toFixed(0) + "%" }
    NSlider {
      Layout.fillWidth: true
      from: 0.5; to: 2.0; stepSize: 0.01
      value: root.editScale
      onValueChanged: root.editScale = value
    }
  }

  NDivider { Layout.fillWidth: true; Layout.margins: Style.marginM }

  NText {
    text: "AI Chat Settings"
    pointSize: Style.fontSizeM
    font.weight: Font.Bold
    color: Color.mOnSurface
  }

  NToggle {
    Layout.fillWidth: true
    label: "Local"
    description: "Use a local inference server (e.g. Ollama, LM Studio)"
    checked: root.editOpenAiLocal
    onToggled: function (checked) { root.editOpenAiLocal = checked; }
  }

  NTextInput {
    Layout.fillWidth: true
    label: "Base URL"
    text: root.editOpenAiBaseUrl
    placeholderText: "https://api.openai.com/v1/chat/completions"
    onTextChanged: root.editOpenAiBaseUrl = text
  }

  NTextInput {
    Layout.fillWidth: true
    label: "Model"
    text: root.editModel
    placeholderText: "gpt-4o-mini"
    onTextChanged: root.editModel = text
  }

  NTextInput {
    Layout.fillWidth: true
    visible: !root.editOpenAiLocal
    label: "API Key"
    description: root.apiKeyManagedByEnv ? "Managed via environment variable" : ""
    placeholderText: root.apiKeyManagedByEnv ? "Set via NOCTALIA_EA_OPENAI_API_KEY" : "Enter your API key..."
    text: root.apiKeyManagedByEnv ? "" : root.editApiKey
    enabled: !root.apiKeyManagedByEnv
    inputMethodHints: Qt.ImhHiddenText
    onTextChanged: { if (!root.apiKeyManagedByEnv) root.editApiKey = text; }
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS
    NLabel { label: "Temperature: " + root.editTemperature.toFixed(1) }
    NSlider {
      Layout.fillWidth: true
      from: 0; to: 2; stepSize: 0.1
      value: root.editTemperature
      onValueChanged: root.editTemperature = value
    }
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS
    NLabel { label: "System Prompt" }
    Rectangle {
      Layout.fillWidth: true; Layout.preferredHeight: 80
      color: Color.mSurface; radius: Style.radiusS; border.color: Color.mOutline; border.width: 1
      TextArea {
        anchors.fill: parent; anchors.margins: Style.marginS
        text: root.editSystemPrompt; color: Color.mOnSurface; font.pointSize: Style.fontSizeS; wrapMode: TextArea.Wrap; background: null
        onTextChanged: root.editSystemPrompt = text
      }
    }
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS
    NLabel { label: "Max History Length: " + root.editMaxHistoryLength }
    NSlider {
      Layout.fillWidth: true
      from: 10; to: 500; stepSize: 10
      value: root.editMaxHistoryLength
      onValueChanged: root.editMaxHistoryLength = value
    }
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS
    NLabel { label: "Max Image Dimension: " + root.editMaxImageDimension + "px" }
    NSlider {
      Layout.fillWidth: true
      from: 256; to: 2048; stepSize: 64
      value: root.editMaxImageDimension
      onValueChanged: root.editMaxImageDimension = value
    }
  }

  function saveSettings() {
    if (!pluginApi) return;
    if (!pluginApi.pluginSettings.ai) pluginApi.pluginSettings.ai = {};

    pluginApi.pluginSettings.ai.model = root.editModel;
    pluginApi.pluginSettings.ai.apiKey = root.editApiKey;
    pluginApi.pluginSettings.ai.temperature = root.editTemperature;
    pluginApi.pluginSettings.ai.systemPrompt = root.editSystemPrompt;
    pluginApi.pluginSettings.ai.openaiLocal = root.editOpenAiLocal;
    pluginApi.pluginSettings.ai.openaiBaseUrl = root.editOpenAiBaseUrl;
    pluginApi.pluginSettings.maxHistoryLength = root.editMaxHistoryLength;
    pluginApi.pluginSettings.ai.maxImageDimension = root.editMaxImageDimension;

    pluginApi.pluginSettings.panelDetached = root.editPanelDetached;
    pluginApi.pluginSettings.panelPosition = root.editPanelPosition;
    pluginApi.pluginSettings.panelHeightRatio = root.editPanelHeightRatio;
    pluginApi.pluginSettings.panelWidth = root.editPanelWidth;
    pluginApi.pluginSettings.attachmentStyle = root.editAttachmentStyle;
    pluginApi.pluginSettings.scale = root.editScale;

    pluginApi.saveSettings();
  }
}
