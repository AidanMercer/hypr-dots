import QtQuick

Canvas {
    id: speaker
    width: 16
    height: 12

    property color iconColor: "#e6e6f0"
    property bool muted: false
    property real level: 1.0

    onIconColorChanged: requestPaint()
    onMutedChanged: requestPaint()
    onLevelChanged: requestPaint()
    Component.onCompleted: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.fillStyle = iconColor
        ctx.strokeStyle = iconColor
        ctx.lineWidth = 1.4
        ctx.lineCap = "round"

        ctx.beginPath()
        ctx.moveTo(0.5, 4.5)
        ctx.lineTo(3, 4.5)
        ctx.lineTo(7, 0.5)
        ctx.lineTo(7, 11.5)
        ctx.lineTo(3, 7.5)
        ctx.lineTo(0.5, 7.5)
        ctx.closePath()
        ctx.fill()

        if (muted) {
            ctx.beginPath()
            ctx.moveTo(10, 3)
            ctx.lineTo(15, 9)
            ctx.moveTo(15, 3)
            ctx.lineTo(10, 9)
            ctx.stroke()
        } else {
            const cx = 7.5, cy = 6
            const a0 = -Math.PI / 3.5, a1 = Math.PI / 3.5
            if (level > 0) {
                ctx.beginPath()
                ctx.arc(cx, cy, 3, a0, a1)
                ctx.stroke()
            }
            if (level > 0.5) {
                ctx.beginPath()
                ctx.arc(cx, cy, 5.5, a0, a1)
                ctx.stroke()
            }
        }
    }
}
