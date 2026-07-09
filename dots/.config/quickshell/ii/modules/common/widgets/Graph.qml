import QtQuick
import qs.modules.common
import qs.modules.common.functions

/*
 * Simple one value line graph
 */
Canvas {
    id: root

    enum Alignment { Left, Right }

    required property list<real> values
    property int points: values.length
    property color color: Appearance.colors.colPrimary
    property real fillOpacity: 0.5
    property var alignment: Graph.Alignment.Left

    onValuesChanged: root.requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        if (!root.values || root.values.length < 2)
            return

        var n = root.points
        var dx = width / (n - 1)
        var offset = (root.alignment === Graph.Alignment.Right) ? root.values.length - n : 0

        // Values < 0 mark gaps (no data); collect runs of valid points once,
        // then draw the line and the baseline fill from the same segments
        var segments = []
        var seg = null
        for (var i = 0; i < n; ++i) {
            var valueIndex = offset + i
            var v = (valueIndex >= 0 && valueIndex < root.values.length) ? root.values[valueIndex] : -1
            if (v < 0) {
                seg = null
                continue
            }
            if (!seg) {
                seg = []
                segments.push(seg)
            }
            seg.push({ x: i * dx, y: height - v * height }) // values already 0-1
        }

        ctx.strokeStyle = root.color
        ctx.fillStyle = ColorUtils.transparentize(root.color, 1 - root.fillOpacity)
        ctx.lineWidth = 2

        ctx.beginPath()
        for (const s of segments) {
            ctx.moveTo(s[0].x, s[0].y)
            for (var j = 1; j < s.length; ++j)
                ctx.lineTo(s[j].x, s[j].y)
        }
        ctx.stroke()

        ctx.beginPath()
        for (const s of segments) {
            ctx.moveTo(s[0].x, height)
            for (const p of s)
                ctx.lineTo(p.x, p.y)
            ctx.lineTo(s[s.length - 1].x, height)
        }
        ctx.fill()
    }
}
