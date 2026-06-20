import CoreGraphics
import Darwin

let isLeftButtonDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
exit(isLeftButtonDown ? 0 : 1)
