import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Windows-Start-Menu-style launcher anchored to the dock.
Item {
  id: root

  property var appLibrary: null
  property var dock: null

  property bool opened: false
  property bool showAllAppsList: false
  property bool dragging: false
  property var dragEntry: null
  property point dragPoint
  property var uninstallEntry: null
  property var menuEntry: null
  property point menuPoint
  property string filterText: ""
  property int selectedIndex: 0
  property var apps: []
  property var pinnedApps: []

  readonly property string dockPosition: root.dock ? root.dock.position : "bottom"
  readonly property int dockReserve: Style.space(76)
  readonly property int iconSize: Math.round(36 * Style.fontScale)
  readonly property int cellGutter: Style.spacing.xs
  readonly property int cellPadding: Style.spacing.sm
  readonly property int labelHeight: Math.ceil(labelMetrics.height) * 2
  readonly property int cellWidth: Math.round(iconSize * 2.45)
  readonly property int cellHeight: cellPadding * 2 + iconSize + Style.spacing.xs + labelHeight
  readonly property int maxColumns: 6
  readonly property int borderWidth: Math.max(1, Style.space(1))
  readonly property int contentMargin: Style.spacing.lg
  readonly property int inset: contentMargin + borderWidth
  readonly property int searchHeight: Math.max(Style.space(38), Style.font.body + Style.spacing.controlPaddingY * 2)
  readonly property int footerHeight: Style.space(44)
  readonly property int screenMargin: Style.space(16)

  readonly property int cardWidth: Math.min(panel.width - screenMargin * 2, maxColumns * cellWidth + inset * 2)
  readonly property int columns: Math.max(1, Math.floor((cardWidth - inset * 2) / cellWidth))
  readonly property int gridWidth: columns * cellWidth
  readonly property int cardHeight: Math.min(panel.height - dockReserve - screenMargin * 2, Style.space(620))

  readonly property bool searching: filterText.trim().length > 0
  readonly property var activeList: searching ? apps : (showAllAppsList ? apps : (pinnedApps.length > 0 ? pinnedApps : apps))

  function open() {
    root.selectedIndex = 0
    root.showAllAppsList = false
    if (root.appLibrary) root.appLibrary.refreshIcons()
    root.filterText = ""
    searchInput.text = ""
    root.rebuild()
    root.opened = true
    Qt.callLater(function() {
      searchInput.forceActiveFocus()
    })
  }

  function close() {
    if (root.dragging && root.dock) root.dock.endExternalDrag()
    root.opened = false
    root.uninstallEntry = null
    root.dragging = false
    root.dragEntry = null
    root.menuEntry = null
  }

  function dragTo(entry, point) {
    if (!root.dragging) {
      root.menuEntry = null
      root.dragEntry = entry
      root.dragging = true
    }
    root.dragPoint = point
    if (root.dock) root.dock.moveExternalDrag(panel.screen, point.x, point.y)
  }

  function dropDrag() {
    var entry = root.dragEntry
    if (entry && root.dock) root.dock.dropExternalDrag(panel.screen, root.dragPoint.x, root.dragPoint.y, String(entry.id || ""))
    root.close()
  }

  function requestUninstall(entry) {
    if (!entry) return
    root.menuEntry = null
    uninstallConfirm.selectedIndex = 1
    root.uninstallEntry = entry
  }

  function cancelUninstall() {
    root.uninstallEntry = null
    Qt.callLater(function() { searchInput.forceActiveFocus() })
  }

  function confirmUninstall() {
    var entry = root.uninstallEntry
    root.uninstallEntry = null
    root.close()
    if (entry && root.appLibrary) root.appLibrary.remove(entry.id, root.appLibrary.entryName(entry))
  }

  function openMenu(entry, point) {
    root.menuEntry = entry
    root.menuPoint = point
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function rebuild() {
    root.appsStale = false
    var rows = root.appLibrary ? root.appLibrary.sortedEntries(root.filterText) : []
    root.apps = rows.map(function(row) { return row.entry })

    var pinned = []
    var keys = root.dock ? root.dock.pinnedKeys : []
    for (var i = 0; i < keys.length; i++) {
      var entry = DesktopEntries.byId(keys[i])
      if (entry && !entry.noDisplay) pinned.push(entry)
    }
    root.pinnedApps = pinned

    var len = root.activeList.length
    root.selectedIndex = len > 0 ? Math.max(0, Math.min(root.selectedIndex, len - 1)) : 0
    if (searchList.contentY > 0) searchList.positionViewAtBeginning()
    if (allAppsListView.contentY > 0) allAppsListView.positionViewAtBeginning()
  }

  function setFilter(text) {
    root.filterText = text
    if (searchInput.text !== text) searchInput.text = text
    root.selectedIndex = 0
    root.rebuild()
  }

  function select(delta) {
    var len = root.activeList.length
    if (len === 0) return
    root.selectedIndex = Math.max(0, Math.min(len - 1, root.selectedIndex + delta))
    if (root.searching) searchList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    else if (root.showAllAppsList) allAppsListView.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function launch(index) {
    var entry = root.activeList[index]
    if (!entry || !root.appLibrary) return
    root.close()
    if (root.dock) root.dock.launchEntry(entry)
    else root.appLibrary.launch(entry.id, root.appLibrary.entryName(entry))
  }

  function launchEntry(entry) {
    if (!entry || !root.appLibrary) return
    root.close()
    if (root.dock) root.dock.launchEntry(entry)
    else root.appLibrary.launch(entry.id, root.appLibrary.entryName(entry))
  }

  FontMetrics {
    id: labelMetrics
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.caption
  }

  property bool appsStale: false

  Connections {
    target: root.appLibrary
    function onAppsChanged() {
      if (root.opened) root.rebuild()
      else root.appsStale = true
    }
  }

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "omarchy-dock-apps"

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: {
        if (root.menuEntry) root.menuEntry = null
        else root.close()
      }
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      x: root.dockPosition === "left" ? root.dockReserve
        : root.dockPosition === "right" ? Math.max(root.screenMargin, panel.width - width - root.dockReserve)
        : Math.round((panel.width - width) / 2)
      y: root.dockPosition === "top" ? root.dockReserve
        : root.dockPosition === "bottom" ? Math.max(root.screenMargin, panel.height - height - root.dockReserve)
        : Math.round((panel.height - height) / 2)
      radius: Math.max(Style.cornerRadius, Style.space(10))
      color: Commons.Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, root.borderWidth)
      padding: 0
      opacity: root.dragging ? 0 : 1
      clip: true

      Behavior on opacity {
        id: cardFade
        NumberAnimation { duration: Style.duration(cardFade.targetValue > 0 ? 140 : 90); easing.type: Easing.OutCubic }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.menuEntry = null
      }

      ConfirmDialog {
        id: uninstallConfirm

        anchors.fill: parent
        opened: !!root.uninstallEntry
        z: 10
        message: Commons.I18n.t("common.uninstallConfirm").arg(root.uninstallEntry && root.appLibrary ? root.appLibrary.entryName(root.uninstallEntry) : "")
        confirmText: Commons.I18n.t("common.uninstall")
        background: Commons.Color.menu.background
        foreground: Commons.Color.menu.text
        scrim: Commons.Color.menu.scrim
        selectedBackground: Commons.Color.menu.selectedBackground
        selectedText: Commons.Color.menu.selectedText
        fontFamily: Style.font.menuFamily
        cornerRadius: Style.cornerRadius
        onCanceled: root.cancelUninstall()
        onConfirmed: root.confirmUninstall()
      }

      // Main Start Menu vertical layout: Search -> Body -> Footer
      Item {
        id: mainLayout
        anchors.fill: parent
        anchors.margins: root.borderWidth

        // Top search bar
        Rectangle {
          id: searchBox
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.topMargin: root.contentMargin
          anchors.leftMargin: root.contentMargin
          anchors.rightMargin: root.contentMargin
          height: root.searchHeight
          radius: height / 2
          color: Util.alpha(Commons.Color.menu.text, 0.07)
          border.width: 1
          border.color: searchInput.activeFocus ? Commons.Color.accent : Util.alpha(Commons.Color.menu.text, 0.14)

          // Magnifying glass glyph drawn cleanly
          Item {
            id: searchIcon
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(16)
            height: Style.space(16)

            Rectangle {
              x: 1
              y: 1
              width: Style.space(10)
              height: Style.space(10)
              radius: width / 2
              color: "transparent"
              border.width: Math.max(1, Style.space(1.5))
              border.color: Commons.Color.menu.text
              opacity: 0.7
            }

            Rectangle {
              x: Style.space(9)
              y: Style.space(10)
              width: Style.space(6)
              height: Math.max(1, Style.space(1.5))
              radius: 1
              rotation: 45
              color: Commons.Color.menu.text
              opacity: 0.7
            }
          }

          TextInput {
            id: searchInput
            anchors.left: searchIcon.right
            anchors.leftMargin: Style.spacing.sm
            anchors.right: clearBtn.visible ? clearBtn.left : parent.right
            anchors.rightMargin: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            color: Commons.Color.menu.text
            selectionColor: Commons.Color.menu.selectedBackground
            selectedTextColor: Commons.Color.menu.selectedText
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
            clip: true
            focus: true

            onTextChanged: {
              if (root.filterText !== text) root.setFilter(text)
            }

            Keys.onPressed: function(event) {
              if (root.uninstallEntry) {
                if (uninstallConfirm.handleKey(event)) event.accepted = true
                return
              }
              if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ShiftModifier)) {
                root.requestUninstall(root.activeList[root.selectedIndex])
                event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                if (root.menuEntry) root.menuEntry = null
                else if (root.filterText) root.setFilter("")
                else if (root.showAllAppsList) { root.showAllAppsList = false; root.selectedIndex = 0 }
                else root.close()
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.launch(root.selectedIndex)
                event.accepted = true
              } else if (event.key === Qt.Key_Up) {
                root.select((root.searching || root.showAllAppsList) ? -1 : -root.columns)
                event.accepted = true
              } else if (event.key === Qt.Key_Down) {
                root.select((root.searching || root.showAllAppsList) ? 1 : root.columns)
                event.accepted = true
              } else if (!root.searching && !root.showAllAppsList && Util.readingKey(event) === Qt.Key_Left) {
                root.select(-1)
                event.accepted = true
              } else if (!root.searching && !root.showAllAppsList && Util.readingKey(event) === Qt.Key_Right) {
                root.select(1)
                event.accepted = true
              }
            }

            Text {
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter
              visible: !searchInput.text
              textFormat: Text.PlainText
              text: "Type here to search apps"
              color: Commons.Color.menu.text
              opacity: 0.5
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
          }

          Rectangle {
            id: clearBtn
            visible: root.filterText.length > 0
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(22)
            height: Style.space(22)
            radius: width / 2
            color: clearMouse.containsMouse ? Style.hoverFill : "transparent"

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "×"
              color: Commons.Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: clearMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.setFilter("")
                searchInput.forceActiveFocus()
              }
            }
          }
        }

        // Body area between search bar and footer
        Item {
          id: bodyArea
          anchors.top: searchBox.bottom
          anchors.topMargin: Style.spacing.md
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: root.contentMargin
          anchors.rightMargin: root.contentMargin
          anchors.bottom: footerDivider.top
          anchors.bottomMargin: Style.spacing.sm

          // 1) SEARCH RESULTS VIEW (Windows Start Menu style)
          Item {
            anchors.fill: parent
            visible: root.searching

            ListView {
              id: searchList
              anchors.fill: parent
              model: root.searching ? root.apps : []
              clip: true
              spacing: Style.spacing.xxs
              boundsBehavior: Flickable.StopAtBounds

              delegate: Rectangle {
                id: resultRow

                required property int index
                required property var modelData
                readonly property bool isBest: index === 0
                readonly property bool selected: index === root.selectedIndex
                readonly property string appName: root.appLibrary ? root.appLibrary.entryName(modelData) : ""
                readonly property string appSub: root.appLibrary ? root.appLibrary.entrySubtext(modelData) : ""

                width: searchList.width
                height: isBest ? Style.space(60) : Style.space(44)
                radius: Style.cornerRadius
                color: selected ? Commons.Color.menu.selectedBackground
                  : (rowHover.containsMouse ? Style.hoverFill : (isBest ? Util.alpha(Commons.Color.menu.text, 0.04) : "transparent"))

                Image {
                  id: rowIcon
                  anchors.left: parent.left
                  anchors.leftMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  width: resultRow.isBest ? Style.space(36) : Style.space(26)
                  height: width
                  sourceSize: Qt.size(72, 72)
                  source: root.appLibrary ? root.appLibrary.iconSource(resultRow.modelData.icon) : ""
                  fillMode: Image.PreserveAspectFit
                  asynchronous: false
                  smooth: true
                  mipmap: true
                }

                Column {
                  anchors.left: rowIcon.right
                  anchors.leftMargin: Style.spacing.md
                  anchors.right: bestBadge.visible ? bestBadge.left : parent.right
                  anchors.rightMargin: Style.spacing.sm
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 1

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: resultRow.appName
                    color: resultRow.selected ? Commons.Color.menu.selectedText : Commons.Color.menu.text
                    font.family: Style.font.menuFamily
                    font.pixelSize: resultRow.isBest ? Style.font.heading : Style.font.body
                    font.weight: resultRow.isBest ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    visible: resultRow.appSub.length > 0
                    textFormat: Text.PlainText
                    text: resultRow.appSub
                    color: resultRow.selected ? Commons.Color.menu.selectedText : Commons.Color.menu.text
                    opacity: resultRow.selected ? 0.85 : 0.6
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Rectangle {
                  id: bestBadge
                  visible: resultRow.isBest
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  radius: Style.cornerRadius
                  color: resultRow.selected ? Util.alpha(Commons.Color.menu.selectedText, 0.16) : Util.alpha(Commons.Color.menu.text, 0.08)
                  width: bestBadgeText.implicitWidth + Style.spacing.sm * 2
                  height: bestBadgeText.implicitHeight + Style.spacing.xxs * 2

                  Text {
                    id: bestBadgeText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "Best match"
                    color: resultRow.selected ? Commons.Color.menu.selectedText : Commons.Color.menu.text
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                MouseArea {
                  id: rowHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  onContainsMouseChanged: if (containsMouse && !root.dragging) root.selectedIndex = resultRow.index
                  onClicked: function(event) {
                    if (event.button === Qt.RightButton) {
                      root.openMenu(resultRow.modelData, resultRow.mapToItem(panel.contentItem, event.x, event.y))
                      return
                    }
                    root.menuEntry = null
                    root.launchEntry(resultRow.modelData)
                  }
                }
              }
            }

            Text {
              anchors.centerIn: parent
              visible: root.apps.length === 0
              textFormat: Text.PlainText
              text: Commons.I18n.t("dock.noAppsMatch").arg(root.filterText)
              color: Commons.Color.menu.text
              opacity: 0.7
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.title
            }
          }

          // 2) DEFAULT START MENU VIEW (Pinned grid + All apps toggle)
          Item {
            anchors.fill: parent
            visible: !root.searching

            // Section header ("Pinned" + "All apps >" OR "All apps" + "< Back")
            Item {
              id: sectionHeader
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              height: Style.space(30)

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.xs
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: (root.showAllAppsList || root.pinnedApps.length === 0) ? "All apps" : "Pinned"
                color: Commons.Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                font.weight: Font.DemiBold
              }

              Rectangle {
                visible: root.pinnedApps.length > 0
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(26)
                width: toggleBtnText.implicitWidth + Style.spacing.md * 2
                radius: Style.cornerRadius
                color: toggleBtnMouse.containsMouse ? Style.hoverFill : Util.alpha(Commons.Color.menu.text, 0.06)
                border.width: 1
                border.color: Util.alpha(Commons.Color.menu.text, 0.1)

                Text {
                  id: toggleBtnText
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: root.showAllAppsList ? "‹  Back" : "All apps  ›"
                  color: Commons.Color.menu.text
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  id: toggleBtnMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.showAllAppsList = !root.showAllAppsList
                    root.selectedIndex = 0
                    searchInput.forceActiveFocus()
                  }
                }
              }
            }

            // Pinned 6-column grid (when not in All apps list)
            GridView {
              id: pinnedGrid
              visible: !root.showAllAppsList && root.pinnedApps.length > 0
              anchors.top: sectionHeader.bottom
              anchors.topMargin: Style.spacing.sm
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              model: visible ? root.pinnedApps : []
              clip: true
              cellWidth: root.cellWidth
              cellHeight: root.cellHeight
              boundsBehavior: Flickable.StopAtBounds

              delegate: Item {
                id: cell

                required property int index
                required property var modelData
                readonly property bool selected: index === root.selectedIndex
                property point pressPoint
                property bool moved: false

                width: root.cellWidth
                height: root.cellHeight

                Rectangle {
                  anchors.fill: parent
                  anchors.margins: Style.spacing.xxs
                  radius: Style.cornerRadius
                  color: cell.selected ? Commons.Color.menu.selectedBackground : (cellMouse.containsMouse ? Style.hoverFill : "transparent")
                }

                Image {
                  id: icon
                  anchors.horizontalCenter: parent.horizontalCenter
                  y: root.cellPadding
                  width: root.iconSize
                  height: root.iconSize
                  sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
                  source: root.appLibrary ? root.appLibrary.iconSource(cell.modelData.icon) : ""
                  fillMode: Image.PreserveAspectFit
                  asynchronous: false
                  smooth: true
                  mipmap: true
                }

                Text {
                  id: label
                  anchors.top: icon.bottom
                  anchors.topMargin: Style.spacing.xs
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: parent.width - (root.cellGutter + Style.spacing.xs) * 2
                  textFormat: Text.PlainText
                  text: root.appLibrary ? root.appLibrary.entryName(cell.modelData) : ""
                  color: cell.selected ? Commons.Color.menu.selectedText : Commons.Color.menu.text
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.caption
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignTop
                  wrapMode: Text.Wrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                }

                MouseArea {
                  id: cellMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  preventStealing: true
                  onContainsMouseChanged: if (containsMouse && !root.dragging) root.selectedIndex = cell.index
                  onPressed: function(event) {
                    cell.moved = false
                    cell.pressPoint = Qt.point(event.x, event.y)
                  }
                  onPositionChanged: function(event) {
                    if (!(pressedButtons & Qt.LeftButton)) return
                    if (!cell.moved && Math.hypot(event.x - cell.pressPoint.x, event.y - cell.pressPoint.y) > Style.space(4)) cell.moved = true
                    if (cell.moved) root.dragTo(cell.modelData, cell.mapToItem(panel.contentItem, event.x, event.y))
                  }
                  onReleased: function(event) {
                    if (root.dragging && event.button === Qt.LeftButton) root.dropDrag()
                  }
                  onCanceled: if (root.dragging) root.close()
                  onClicked: function(event) {
                    if (cell.moved) return
                    if (event.button === Qt.RightButton) {
                      root.openMenu(cell.modelData, cell.mapToItem(panel.contentItem, event.x, event.y))
                      return
                    }
                    root.menuEntry = null
                    root.launchEntry(cell.modelData)
                  }
                }
              }
            }

            // Alphabetical All apps list (Windows 11 style)
            ListView {
              id: allAppsListView
              visible: root.showAllAppsList || root.pinnedApps.length === 0
              anchors.top: sectionHeader.bottom
              anchors.topMargin: Style.spacing.sm
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              model: visible ? root.apps : []
              clip: true
              spacing: 2
              boundsBehavior: Flickable.StopAtBounds

              delegate: Rectangle {
                id: appRow

                required property int index
                required property var modelData
                readonly property bool selected: index === root.selectedIndex
                property point pressPoint
                property bool moved: false

                width: allAppsListView.width
                height: Style.space(40)
                radius: Style.cornerRadius
                color: selected ? Commons.Color.menu.selectedBackground : (appRowMouse.containsMouse ? Style.hoverFill : "transparent")

                Image {
                  id: appRowIcon
                  anchors.left: parent.left
                  anchors.leftMargin: Style.spacing.sm
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(24)
                  height: Style.space(24)
                  sourceSize: Qt.size(48, 48)
                  source: root.appLibrary ? root.appLibrary.iconSource(appRow.modelData.icon) : ""
                  fillMode: Image.PreserveAspectFit
                  asynchronous: false
                  smooth: true
                  mipmap: true
                }

                Text {
                  anchors.left: appRowIcon.right
                  anchors.leftMargin: Style.spacing.md
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.sm
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: root.appLibrary ? root.appLibrary.entryName(appRow.modelData) : ""
                  color: appRow.selected ? Commons.Color.menu.selectedText : Commons.Color.menu.text
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                MouseArea {
                  id: appRowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  preventStealing: true
                  onContainsMouseChanged: if (containsMouse && !root.dragging) root.selectedIndex = appRow.index
                  onPressed: function(event) {
                    appRow.moved = false
                    appRow.pressPoint = Qt.point(event.x, event.y)
                  }
                  onPositionChanged: function(event) {
                    if (!(pressedButtons & Qt.LeftButton)) return
                    if (!appRow.moved && Math.hypot(event.x - appRow.pressPoint.x, event.y - appRow.pressPoint.y) > Style.space(4)) appRow.moved = true
                    if (appRow.moved) root.dragTo(appRow.modelData, appRow.mapToItem(panel.contentItem, event.x, event.y))
                  }
                  onReleased: function(event) {
                    if (root.dragging && event.button === Qt.LeftButton) root.dropDrag()
                  }
                  onCanceled: if (root.dragging) root.close()
                  onClicked: function(event) {
                    if (appRow.moved) return
                    if (event.button === Qt.RightButton) {
                      root.openMenu(appRow.modelData, appRow.mapToItem(panel.contentItem, event.x, event.y))
                      return
                    }
                    root.menuEntry = null
                    root.launchEntry(appRow.modelData)
                  }
                }
              }
            }
          }
        }

        // Bottom Windows-Start-Menu footer bar
        Rectangle {
          id: footerDivider
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: footerBar.top
          height: 1
          color: Util.alpha(Commons.Color.menu.text, 0.1)
        }

        Rectangle {
          id: footerBar
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: root.footerHeight
          color: Util.alpha(Commons.Color.menu.text, 0.03)

          Row {
            anchors.left: parent.left
            anchors.leftMargin: root.contentMargin
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.sm

            Rectangle {
              width: Style.space(26)
              height: Style.space(26)
              radius: width / 2
              color: Util.alpha(Commons.Color.accent, 0.22)
              border.width: 1
              border.color: Util.alpha(Commons.Color.accent, 0.5)

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: (Quickshell.env("USER") || "U").charAt(0).toUpperCase()
                color: Commons.Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                font.weight: Font.DemiBold
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: Quickshell.env("USER") || "user"
              color: Commons.Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }
          }

          Row {
            anchors.right: parent.right
            anchors.rightMargin: root.contentMargin
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xs

            FooterButton {
              label: "Lock"
              onTriggered: {
                root.close()
                Util.execDetached("omarchy system lock")
              }
            }

            FooterButton {
              label: "Restart"
              onTriggered: {
                root.close()
                Util.execDetached("omarchy system reboot")
              }
            }

            FooterButton {
              label: "Power off"
              onTriggered: {
                root.close()
                Util.execDetached("omarchy system shutdown")
              }
            }
          }
        }
      }
    }

    // The dragged app's icon, under the pointer.
    Image {
      visible: root.dragging && !!root.dragEntry
      x: root.dragPoint.x - width / 2
      y: root.dragPoint.y - height / 2
      width: root.iconSize
      height: root.iconSize
      sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
      source: root.dragEntry && root.appLibrary ? root.appLibrary.iconSource(root.dragEntry.icon) : ""
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true
    }

    // Right-click on an app: open it, or keep it in the dock or take it out.
    BorderSurface {
      id: menu

      readonly property var entry: root.menuEntry
      readonly property bool pinned: !!entry && !!root.dock && root.dock.isPinned(String(entry.id || ""))

      visible: !!entry && !root.dragging
      width: Math.max(Style.space(160), menuColumn.implicitWidth) + padding * 2
      height: menuColumn.implicitHeight + padding * 2
      x: LayoutMirroring.enabled
        ? Math.max(Style.gapsOut, root.menuPoint.x - width)
        : Math.min(root.menuPoint.x, panel.width - width - Style.gapsOut)
      y: Math.min(root.menuPoint.y, panel.height - height - Style.gapsOut)
      radius: Style.cornerRadius
      color: Commons.Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)
      padding: Style.spacing.sm

      Column {
        id: menuColumn
        x: menu.contentLeftInset
        y: menu.contentTopInset
        width: menu.width - menu.contentLeftInset - menu.contentRightInset

        MenuRow {
          text: Commons.I18n.t("dock.open")
          onTriggered: {
            var entry = menu.entry
            root.close()
            if (entry && root.dock) root.dock.launchEntry(entry)
            else if (entry && root.appLibrary) root.appLibrary.launch(entry.id, root.appLibrary.entryName(entry))
          }
        }

        MenuRow {
          visible: !!root.dock
          text: menu.pinned ? Commons.I18n.t("dock.removeFromDock") : Commons.I18n.t("dock.keepInDock")
          onTriggered: {
            if (root.dock && menu.entry) root.dock.setPinned(String(menu.entry.id || ""), !menu.pinned)
            root.menuEntry = null
          }
        }

        MenuRow {
          text: Commons.I18n.t("dock.uninstall")
          onTriggered: root.requestUninstall(menu.entry)
        }
      }
    }
  }

  component FooterButton: Rectangle {
    id: fbtn

    property string label: ""
    signal triggered()

    width: fbtnText.implicitWidth + Style.spacing.sm * 2
    height: Style.space(26)
    radius: Style.cornerRadius
    color: fbtnMouse.containsMouse ? Style.hoverFill : "transparent"

    Text {
      id: fbtnText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: fbtn.label
      color: Commons.Color.menu.text
      opacity: fbtnMouse.containsMouse ? 1 : 0.78
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: fbtnMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: fbtn.triggered()
    }
  }

  component MenuRow: Rectangle {
    id: row

    property string text: ""
    signal triggered()

    width: parent ? parent.width : 0
    height: visible ? Style.spacing.popupRowHeight : 0
    radius: Style.cornerRadius
    color: rowMouse.containsMouse ? Style.hoverFill : "transparent"

    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.controlPaddingX
      textFormat: Text.PlainText
      text: row.text
      color: Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: row.triggered()
    }
  }
}
