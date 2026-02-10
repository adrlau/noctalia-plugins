import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI
import "Constants.js" as Constants

Item {
  id: root
  
  property var pluginApi: null
  property var mainInstance: null

  // State from main instance
  readonly property var messages: mainInstance?.messages || []
  readonly property bool isGenerating: mainInstance?.isGenerating || false
  readonly property string currentResponse: mainInstance?.currentResponse || ""
  readonly property string errorMessage: mainInstance?.errorMessage || ""
  property string initialInputText: mainInstance?.chatInputText || ""
  property int initialCursorPosition: mainInstance?.chatInputCursorPosition || 0

    readonly property string model: mainInstance?.model || ""

  property string enlargedImage: ""
  readonly property var pendingToolCall: mainInstance?.pendingToolCall || null

  DropArea {
    anchors.fill: parent
    z: 1
    onDropped: function(drop) {
      if (drop.hasUrls) {
        for (var i = 0; i < drop.urls.length; i++) {
          var url = drop.urls[i].toString();
          if (url.toLowerCase().endsWith(".png") || url.toLowerCase().endsWith(".jpg") || url.toLowerCase().endsWith(".jpeg") || url.toLowerCase().endsWith(".webp")) {
            if (mainInstance) mainInstance.processImageFile(url);
          }
        }
      }
    }
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.marginM

    // Header with model info
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      NIcon {
        icon: "brand-openai"
        color: Color.mPrimary
        pointSize: Style.fontSizeM
        applyUiScale: false
      }

      NText {
        text: model
        color: Color.mOnSurface
        pointSize: Style.fontSizeS
        applyUiScale: false
        font.weight: Font.Medium
        Layout.fillWidth: true
        elide: Text.ElideRight
      }

      NIcon {
        icon: "loader-2"
        visible: isGenerating
        color: Color.mPrimary
        pointSize: Style.fontSizeS
        applyUiScale: false

        RotationAnimation on rotation {
          from: 0
          to: 360
          duration: 1000
          loops: Animation.Infinite
          running: isGenerating
        }
      }

      NText {
        id: clearHistoryText
        text: pluginApi?.tr("chat.clearHistory") || "Clear history"
        property bool enabledClear: messages.length > 0 && !isGenerating
        property bool hovered: false
        color: clearHistoryText.enabledClear ? (clearHistoryText.hovered ? Color.mOnSurface : Color.mOnSurfaceVariant) : Color.mOnSurfaceVariant
        pointSize: Style.fontSizeXS
        applyUiScale: false
        font.weight: clearHistoryText.hovered ? Font.Medium : Font.Normal
        verticalAlignment: Text.AlignVCenter
        opacity: clearHistoryText.enabledClear ? 1.0 : 0.5
        Layout.alignment: Qt.AlignRight

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          enabled: clearHistoryText.enabledClear
          onEntered: clearHistoryText.hovered = true
          onExited: clearHistoryText.hovered = false
          onClicked: {
            if (mainInstance)
              mainInstance.clearMessages();
          }
        }
      }
    }

    // Dependency Warning
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: depRow.implicitHeight + Style.marginS * 2
      color: (typeof Color !== 'undefined' && Color.mWarning) ? Qt.alpha(Color.mWarning, 0.2) : Qt.alpha("#FFA500", 0.2)
      radius: Style.radiusS
      visible: mainInstance && !mainInstance.hasDependencies

      RowLayout {
        id: depRow
        anchors.fill: parent
        anchors.margins: Style.marginS
        spacing: Style.marginS

        NIcon {
          icon: "alert-circle"
          color: (typeof Color !== 'undefined' && Color.mWarning) ? Color.mWarning : "#FFA500"
          pointSize: Style.fontSizeM
        }

        NText {
          Layout.fillWidth: true
          text: mainInstance?.dependencyError || ""
          color: (typeof Color !== 'undefined' && Color.mWarning) ? Color.mWarning : "#FFA500"
          pointSize: Style.fontSizeS
          wrapMode: Text.Wrap
        }
      }
    }

    // Messages list container
    Rectangle {
      Layout.fillWidth: true
      Layout.fillHeight: true
      color: Color.mSurface
      radius: Style.radiusM
      clip: true

      // Empty state
      Item {
        anchors.fill: parent
        visible: messages.length === 0 && !isGenerating

        ColumnLayout {
          anchors.centerIn: parent
          spacing: Style.marginM

          NIcon {
            Layout.alignment: Qt.AlignHCenter
            icon: "sparkles"
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeXXL * 2
            applyUiScale: false
          }

          NText {
            Layout.alignment: Qt.AlignHCenter
            text: pluginApi?.tr("chat.emptyTitle") || "Start a conversation"
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeM
            applyUiScale: false
            font.weight: Font.Medium
          }

          NText {
            Layout.alignment: Qt.AlignHCenter
            text: pluginApi?.tr("chat.emptyHint") || "Type a message below to begin"
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeS
            applyUiScale: false
          }
        }
      }

      Flickable {
        id: chatFlickable
        anchors.fill: parent
        anchors.margins: Style.marginS
        contentWidth: width
        contentHeight: messageColumn.height
        clip: true
        visible: messages.length > 0 || isGenerating
        boundsBehavior: Flickable.StopAtBounds

        property real wheelScrollMultiplier: 4.0

        WheelHandler {
          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
          onWheel: event => {
            const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 8;
            const newY = chatFlickable.contentY - (delta * chatFlickable.wheelScrollMultiplier);
            chatFlickable.contentY = Math.max(0, Math.min(newY, chatFlickable.contentHeight - chatFlickable.height));
            chatFlickable.autoScrollEnabled = chatFlickable.isNearBottom;
            event.accepted = true;
          }
        }

        property bool autoScrollEnabled: true
        readonly property bool isNearBottom: {
          if (contentHeight <= height)
            return true;
          return contentY >= contentHeight - height - 30;
        }

        function scrollToBottom() {
          if (contentHeight > height) {
            contentY = contentHeight - height;
          }
        }

        onContentHeightChanged: {
          if (autoScrollEnabled && contentHeight > height) {
            scrollToBottom();
          }
        }

        onMovementEnded: {
          autoScrollEnabled = isNearBottom;
        }

        onFlickEnded: {
          autoScrollEnabled = isNearBottom;
        }

        Column {
          id: messageColumn
          width: chatFlickable.width
          spacing: Style.marginM

          Repeater {
            id: messageRepeater
            model: messages

            MessageBubble {
              width: messageColumn.width
              message: modelData
              pluginApi: root.pluginApi

              onRegenerateRequested: {
                if (mainInstance && !isGenerating) {
                  mainInstance.regenerateLastResponse();
                }
              }
              onEditRequested: function (id, newText) {
                if (mainInstance && !isGenerating) {
                  mainInstance.editMessage(id, newText);
                }
              }
              onCopyRequested: function (text) {
                Quickshell.clipboardText = text;
                ToastService.showNotice(pluginApi?.tr("toast.copied") || "Copied to clipboard");
              }
              onImageClicked: function (source) {
                root.enlargedImage = source;
              }
            }
          }

          MessageBubble {
            id: streamingBubble
            width: messageColumn.width
            visible: isGenerating && currentResponse.trim() !== ""
            pluginApi: root.pluginApi
            message: ({
                "id": "streaming",
                "role": "assistant",
                "content": currentResponse,
                "isStreaming": true
              })
            onImageClicked: function (source) {
              root.enlargedImage = source;
            }
          }
        }
      }

      Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Style.marginM
        width: 32
        height: 32
        radius: width / 2
        color: Color.mPrimary
        visible: !chatFlickable.autoScrollEnabled && messages.length > 0
        opacity: scrollButtonMouse.containsMouse ? 1.0 : 0.8

        Behavior on opacity {
          NumberAnimation {
            duration: Style.animationFast
          }
        }

        NIcon {
          anchors.centerIn: parent
          icon: "chevron-down"
          color: Color.mOnPrimary
          pointSize: Style.fontSizeM
          applyUiScale: false
        }

        MouseArea {
          id: scrollButtonMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            chatFlickable.autoScrollEnabled = true;
            chatFlickable.scrollToBottom();
          }
        }
      }
    }

    // Error message
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: errorRow.implicitHeight + Style.marginS * 2
      color: Qt.alpha(Color.mError, 0.2)
      radius: Style.radiusS
      visible: errorMessage !== ""

      RowLayout {
        id: errorRow
        anchors.fill: parent
        anchors.margins: Style.marginS
        spacing: Style.marginS

        NIcon {
          icon: "alert-triangle"
          color: Color.mError
          pointSize: Style.fontSizeM
        }

        TextEdit {
          Layout.fillWidth: true
          text: errorMessage
          color: Color.mError
          font.pointSize: Math.max(1, Style.fontSizeS * Settings.data.ui.fontDefaultScale * Style.uiScaleRatio)
          font.family: Settings.data.ui.fontDefault
          wrapMode: TextEdit.Wrap
          readOnly: true
          selectByMouse: true
          textFormat: Text.PlainText
        }
      }
    }

    // Tool Confirmation
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: toolConfirmRow.implicitHeight + Style.marginS * 2
      color: Color.mSurfaceVariant
      radius: Style.radiusM
      visible: root.pendingToolCall !== null

      RowLayout {
        id: toolConfirmRow
        anchors.fill: parent
        anchors.margins: Style.marginS
        spacing: Style.marginM

        NIcon {
          icon: "settings-automation"
          color: Color.mPrimary
          pointSize: Style.fontSizeL
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2
          NText {
            text: "AI wants to execute a command:"
            pointSize: Style.fontSizeS
            font.weight: Font.Bold
          }
          NText {
            text: root.pendingToolCall ? (root.pendingToolCall.name + "(" + root.pendingToolCall.args + ")") : ""
            pointSize: Style.fontSizeXS
            color: Color.mOnSurfaceVariant
            Layout.fillWidth: true
            elide: Text.ElideRight
          }
        }

        Row {
          spacing: Style.marginS
          NButton {
            text: "Allow"
            backgroundColor: Color.mPrimary
            textColor: Color.mOnPrimary
            onClicked: mainInstance.confirmToolExecution(true)
          }
          NButton {
            text: "Deny"
            backgroundColor: Color.mSurface
            textColor: Color.mOnSurface
            onClicked: mainInstance.confirmToolExecution(false)
          }
        }
      }
    }

    // Input area
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      // Pending images preview
      RowLayout {
        Layout.fillWidth: true
        visible: mainInstance?.pendingImages?.length > 0
        spacing: Style.marginS

        Repeater {
          model: mainInstance?.pendingImages || []
          Rectangle {
            width: 60
            height: 60
            radius: Style.radiusS
            clip: true
            color: Color.mSurfaceVariant

            Image {
              anchors.fill: parent
              source: modelData.path
              fillMode: Image.PreserveAspectCrop
            }

            // Click to enlarge
            MouseArea {
              anchors.fill: parent
              onClicked: root.enlargedImage = modelData.path
            }

            // Remove button
            Rectangle {
              id: removeBtn
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 4
              width: 22
              height: 22
              radius: 11
              color: removeBtnMouse.containsMouse ? Color.mError : Qt.alpha(Color.mError, 0.8)
              border.width: 1
              border.color: "white"
              
              NIcon {
                anchors.centerIn: parent
                icon: "x"
                color: "white"
                pointSize: 12
              }

              MouseArea {
                id: removeBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: mainInstance.removePendingImage(index)
              }
            }
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: inputLayout.implicitHeight + Style.marginS * 2
        color: Color.mSurface
        radius: Style.radiusM

        RowLayout {
          id: inputLayout
          anchors.fill: parent
          anchors.margins: Style.marginS
          spacing: Style.marginS

          ScrollView {
            Layout.fillWidth: true
            Layout.maximumHeight: 100

            TextArea {
              id: inputField
              text: initialInputText
              placeholderText: pluginApi?.tr("chat.placeholder") || "Type a message..."
              placeholderTextColor: Color.mOnSurfaceVariant
              color: Color.mOnSurface
              font.pointSize: Style.fontSizeM
              wrapMode: TextArea.Wrap
              background: null
              selectByMouse: true
              enabled: !isGenerating

              onCursorPositionChanged: {
                if (mainInstance) {
                  if (mainInstance.chatInputCursorPosition !== cursorPosition) {
                    mainInstance.chatInputCursorPosition = cursorPosition;
                    mainInstance.saveState();
                  }
                }
              }

              onTextChanged: {
                if (mainInstance) {
                  if (mainInstance.chatInputText !== text) {
                    mainInstance.chatInputText = text;
                    mainInstance.saveState();
                  }
                }
              }

              Keys.onReturnPressed: function (event) {
                if (event.modifiers & Qt.ShiftModifier) {
                  inputField.insert(inputField.cursorPosition, "\n");
                } else {
                  sendMessage();
                }
                event.accepted = true;
              }

              Keys.onPressed: function (event) {
                if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                  if (mainInstance) mainInstance.tryPasteImage();
                  // Don't accept event if we want default text paste to also work
                  // but usually we want to check if it's an image first.
                  // wl-paste --list-types can be used.
                }
              }
            }
          }

          NIconButton {
            id: screenshotButton
            icon: "camera"
            colorFg: Color.mOnSurfaceVariant
            tooltipText: "Take screenshot and paste"
            onClicked: {
              if (mainInstance) mainInstance.takeScreenshotAndPaste();
            }
          }

          NIconButton {
            id: sendButton
            icon: isGenerating ? "player-stop" : "send"
            colorFg: isGenerating ? Color.mError : ((inputField.text.trim() !== "" || (mainInstance?.pendingImages?.length > 0)) ? Color.mPrimary : Color.mOnSurfaceVariant)
            enabled: isGenerating || inputField.text.trim() !== "" || (mainInstance?.pendingImages?.length > 0)
            tooltipText: isGenerating ? (pluginApi?.tr("chat.stop") || "Stop generation") : (pluginApi?.tr("chat.send") || "Send")
            onClicked: {
              if (isGenerating) {
                if (mainInstance)
                  mainInstance.stopGeneration();
              } else {
                sendMessage();
              }
            }
          }
        }
      }
    }
  }

  // Lightbox for enlarged images
  Rectangle {
    id: lightbox
    anchors.fill: parent
    color: "#CC000000" // Semi-transparent black
    visible: root.enlargedImage !== ""
    z: 100 // High z-order to cover everything

    property real zoomLevel: 1.0

    onVisibleChanged: {
      if (!visible) zoomLevel = 1.0;
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.enlargedImage = ""
      onWheel: (wheel) => {
        if (wheel.angleDelta.y > 0) {
          lightbox.zoomLevel = Math.min(5.0, lightbox.zoomLevel + 0.1);
        } else {
          lightbox.zoomLevel = Math.max(1.0, lightbox.zoomLevel - 0.1);
        }
      }
    }

    Flickable {
      anchors.fill: parent
      contentWidth: zoomArea.width
      contentHeight: zoomArea.height
      boundsBehavior: Flickable.StopAtBounds
      clip: true

      Item {
        id: zoomArea
        width: Math.max(lightbox.width, enlargedImg.width * lightbox.zoomLevel)
        height: Math.max(lightbox.height, enlargedImg.height * lightbox.zoomLevel)

        Image {
          id: enlargedImg
          anchors.centerIn: parent
          width: Math.min(lightbox.width, implicitWidth) * lightbox.zoomLevel
          height: Math.min(lightbox.height, implicitHeight) * lightbox.zoomLevel
          source: root.enlargedImage
          fillMode: Image.PreserveAspectFit
          asynchronous: true
        }
      }
    }

    // Controls overlay
    Item {
      anchors.fill: parent
      anchors.margins: Style.marginM
      visible: lightbox.visible

      // Zoom indicator
      Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: 80
        height: 30
        radius: 15
        color: Qt.alpha(Color.mSurface, 0.8)
        border.color: Color.mOutline
        
        NText {
          anchors.centerIn: parent
          text: (lightbox.zoomLevel * 100).toFixed(0) + "%"
          color: Color.mOnSurface
          pointSize: Style.fontSizeS
        }
      }

      // Close button
      Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        width: 32
        height: 32
        radius: 16
        color: Color.mSurface
        border.color: Color.mOutline
        border.width: 1

        NIcon {
          anchors.centerIn: parent
          icon: "x"
          color: Color.mOnSurface
          pointSize: 14
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.enlargedImage = ""
        }
      }
    }

    // Keyboard shortcuts
    Keys.onEscapePressed: root.enlargedImage = ""
    Keys.onDigit0Pressed: lightbox.zoomLevel = 1.0
    focus: visible
  }

  function sendMessage() {
    var text = inputField.text.trim();
    var hasImages = mainInstance?.pendingImages?.length > 0;
    if (text === "" && !hasImages)
      return;
    if (!mainInstance)
      return;
    mainInstance.sendMessage(text);
    inputField.text = "";
    mainInstance.chatInputText = "";
    mainInstance.chatInputCursorPosition = 0;
    mainInstance.saveState();
    inputField.forceActiveFocus();
  }

  function focusInput() {
    if (typeof inputField !== 'undefined' && inputField && inputField.forceActiveFocus) {
      inputField.forceActiveFocus();
      if (initialCursorPosition > 0 && initialCursorPosition <= inputField.text.length) {
        inputField.cursorPosition = initialCursorPosition;
      }
    }
  }
}
