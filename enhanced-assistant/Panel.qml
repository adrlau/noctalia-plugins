import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
  id: root
  
  property var pluginApi: null

  // SmartPanel properties
  readonly property var geometryPlaceholder: panelContainer
  readonly property string _panelPosition: (pluginApi?.pluginSettings?.panelPosition ?? pluginApi?.manifest?.metadata?.panel?.defaultPosition ?? "right")
  readonly property bool _detached: pluginApi?.pluginSettings?.panelDetached ?? pluginApi?.manifest?.metadata?.panel?.detached ?? true
  readonly property string _attachmentStyle: pluginApi?.pluginSettings?.attachmentStyle || "connected"
  readonly property bool _isFloatingAttached: !_detached && _attachmentStyle === "floating"

  readonly property bool allowAttach: !_detached
  readonly property bool panelAnchorRight: !_detached ? _panelPosition === "right" : (_panelPosition === "right")
  readonly property bool panelAnchorLeft: !_detached ? _panelPosition === "left" : (_panelPosition === "left")
  readonly property bool panelAnchorHorizontalCenter: (_detached && _panelPosition === "center") || (_isFloatingAttached && (_panelPosition === "top" || _panelPosition === "bottom"))
  readonly property bool panelAnchorVerticalCenter: _detached || (_isFloatingAttached && (_panelPosition === "left" || _panelPosition === "right"))
  readonly property bool panelAnchorTop: !_detached && _panelPosition === "top"
  readonly property bool panelAnchorBottom: !_detached && _panelPosition === "bottom"

  property int _panelWidth: pluginApi?.pluginSettings?.panelWidth ?? 520
  property real _panelHeightRatio: pluginApi?.pluginSettings?.panelHeightRatio ?? pluginApi?.manifest?.metadata?.panel?.defaultHeightRatio ?? 0.85
  property real contentPreferredWidth: _panelWidth
  property real contentPreferredHeight: screen ? (screen.height * _panelHeightRatio) : 620 * Style.uiScaleRatio
  property real uiScale: pluginApi?.pluginSettings?.scale ?? 1

  anchors.fill: parent

  readonly property var mainInstance: pluginApi?.mainInstance

  onVisibleChanged: {
    if (visible) {
      Qt.callLater(function () {
        if (aiChatViewRef && aiChatViewRef.focusInput) {
          aiChatViewRef.focusInput();
        }
      });
    }
  }

  Rectangle {
    id: panelContainer
    width: contentPreferredWidth
    height: contentPreferredHeight
    color: "transparent"
    anchors.horizontalCenter: (_detached && _panelPosition === "center" && parent) ? parent.horizontalCenter : undefined
    anchors.verticalCenter: (_detached && _panelPosition === "center" && parent) ? parent.verticalCenter : undefined
    y: (_detached && (_panelPosition === "left" || _panelPosition === "right")) ? (root.height - contentPreferredHeight) / 2 : 0

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginM
      spacing: Style.marginM

      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: Color.mSurfaceVariant
        radius: Style.radiusL
        clip: true

        Item {
          anchors.fill: parent
          property real s: root.uiScale

          Item {
            id: scaledContent
            width: parent.width / (parent.s || 1)
            height: parent.height / (parent.s || 1)
            scale: parent.s || 1
            anchors.centerIn: parent
            transformOrigin: Item.Center

            AiChatView {
              id: aiChatViewRef
              anchors.fill: parent
              anchors.margins: Style.marginM
              pluginApi: root.pluginApi
              mainInstance: root.mainInstance
            }
          }
        }
      }
    }
  }
}
