// Lightweight hover tooltip — single-line text bubble that fades in below the anchor item.
// Supports an optional colored vector arrow (up/down) spliced between two text segments,
// e.g. "20W" [▲ green] "76%" — used for battery charge/discharge rate.

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell

PopupWindow {
    id: tooltip

    required property var bar
    required property var anchorItem
    required property color bgColor
    required property color borderColor
    required property color fgColor

    property bool open: false

    // Plain content (no arrow): set `text`. Segmented content: set `leftText` /
    // `rightText` plus `arrowVisible: true`.
    property alias text: leftLabel.text
    property string rightText: ""
    property bool arrowVisible: false
    property bool arrowUp: false
    property color arrowColor: fgColor

    property int cornerRadius: 4
    property int contentPadding: 9
    property int shadowMargin: 12
    property int topGap: 3
    property int animDuration: 120
    property int arrowSize: 8
    property int arrowSpacing: 2
    property int groupSpacing: 8
    property int extraSpacing: 6

    // Extra caller-supplied content (e.g. a per-core grid) stacked below the
    // text/arrow row. Empty by default — the row above stays the whole tooltip.
    default property alias content: extraArea.data

    property real _snapX: 0
    anchor.window: bar
    anchor.rect.x: _snapX
    anchor.rect.y: bar ? bar.implicitHeight : 0
    anchor.rect.width: 0
    anchor.rect.height: 0
    anchor.edges: Edges.Bottom

    implicitWidth: outerColumn.implicitWidth + contentPadding * 2 + shadowMargin * 2
    implicitHeight: outerColumn.implicitHeight + contentPadding * 2 + topGap + shadowMargin
    color: "transparent"

    property real _opacity: open ? 1.0 : 0.0
    Behavior on _opacity {
        NumberAnimation {
            duration: tooltip.animDuration
            easing.type: Easing.OutQuad
        }
    }
    visible: _opacity > 0.01

    onOpenChanged: {
        if (open && anchorItem && bar) {
            const leftInBar = anchorItem.mapToItem(bar.contentItem, 0, 0).x;
            _snapX = leftInBar + anchorItem.width / 2 - (outerColumn.implicitWidth / 2 + contentPadding + shadowMargin);
        }
    }

    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: tooltip.shadowMargin
        anchors.rightMargin: tooltip.shadowMargin
        anchors.bottomMargin: tooltip.shadowMargin
        anchors.topMargin: tooltip.topGap

        Rectangle {
            anchors.fill: parent
            radius: tooltip.cornerRadius
            color: tooltip.bgColor
            border.color: tooltip.borderColor
            border.width: 1
            opacity: tooltip._opacity

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#000000"
                shadowOpacity: 0.18
                shadowBlur: 1.0
                shadowVerticalOffset: 3
            }

            Column {
                id: outerColumn
                anchors.left: parent.left
                anchors.leftMargin: tooltip.contentPadding
                anchors.verticalCenter: parent.verticalCenter
                spacing: tooltip.extraSpacing

                Row {
                    id: contentRow
                    spacing: tooltip.groupSpacing

                    Row {
                        id: rateGroup
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: tooltip.arrowSpacing

                        Text {
                            id: leftLabel
                            anchors.verticalCenter: parent.verticalCenter
                            color: tooltip.fgColor
                            font.pixelSize: 13
                            textFormat: Text.StyledText
                        }

                        Shape {
                            id: arrow
                            anchors.verticalCenter: parent.verticalCenter
                            width: tooltip.arrowSize
                            height: tooltip.arrowSize
                            visible: tooltip.arrowVisible
                            preferredRendererType: Shape.CurveRenderer

                            ShapePath {
                                fillColor: tooltip.arrowColor
                                strokeWidth: -1
                                startX: 0
                                startY: tooltip.arrowUp ? arrow.height : 0
                                PathLine {
                                    x: arrow.width / 2
                                    y: tooltip.arrowUp ? 0 : arrow.height
                                }
                                PathLine {
                                    x: arrow.width
                                    y: tooltip.arrowUp ? arrow.height : 0
                                }
                                PathLine {
                                    x: 0
                                    y: tooltip.arrowUp ? arrow.height : 0
                                }
                            }
                        }
                    }

                    Text {
                        id: rightLabel
                        anchors.verticalCenter: parent.verticalCenter
                        text: tooltip.rightText
                        visible: tooltip.arrowVisible
                        color: tooltip.fgColor
                        font.pixelSize: 13
                        textFormat: Text.StyledText
                    }
                }

                Item {
                    id: extraArea
                    implicitWidth: childrenRect.width
                    implicitHeight: childrenRect.height
                    visible: children.length > 0
                }
            }
        }
    }
}
