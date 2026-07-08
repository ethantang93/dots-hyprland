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

    // Values < 0 mark gaps (no data); the line and fill break around them
    function valueAt(i) {
        var valueIndex = (root.alignment === Graph.Alignment.Right) ? root.values.length - root.points + i : i
        if (valueIndex < 0 || valueIndex >= root.values.length)
            return -1
        return root.values[valueIndex] // already in 0-1 range
    }

    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        if (!root.values || root.values.length < 2)
            return

        var n = root.points
        var dx = width / (n - 1)
        ctx.strokeStyle = root.color
        ctx.fillStyle = ColorUtils.transparentize(root.color, 1 - root.fillOpacity)
        ctx.lineWidth = 2

        // Stroke pass: line segments only, broken at gaps
        ctx.beginPath()
        var penDown = false
        for (var i = 0; i < n; ++i) {
            var v = valueAt(i)
            if (v < 0) {
                penDown = false
                continue
            }
            var x = i * dx
            var y = height - v * height
            if (!penDown) {
                ctx.moveTo(x, y)
                penDown = true
            } else {
                ctx.lineTo(x, y)
            }
        }
        ctx.stroke()

        // Fill pass: same segments closed down to the baseline
        ctx.beginPath()
        var segStartX = -1
        var lastX = 0
        for (i = 0; i < n; ++i) {
            v = valueAt(i)
            if (v < 0) {
                if (segStartX >= 0) {
                    ctx.lineTo(lastX, height)
                    ctx.lineTo(segStartX, height)
                }
                segStartX = -1
                continue
            }
            x = i * dx
            y = height - v * height
            if (segStartX < 0) {
                ctx.moveTo(x, height)
                segStartX = x
            }
            ctx.lineTo(x, y)
            lastX = x
        }
        if (segStartX >= 0) {
            ctx.lineTo(lastX, height)
            ctx.lineTo(segStartX, height)
        }
        ctx.fill()
    }
}
