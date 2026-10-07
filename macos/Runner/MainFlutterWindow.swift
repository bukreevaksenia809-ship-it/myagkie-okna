import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    let preferredSize = NSSize(width: 1440, height: 920)
    if let screen = self.screen ?? NSScreen.main {
      let visible = screen.visibleFrame
      let width = min(preferredSize.width, visible.width - 40)
      let height = min(preferredSize.height, visible.height - 40)
      let origin = NSPoint(
        x: visible.midX - width / 2,
        y: visible.midY - height / 2
      )
      self.setFrame(
        NSRect(origin: origin, size: NSSize(width: width, height: height)),
        display: true
      )
    } else {
      self.setFrame(
        NSRect(origin: self.frame.origin, size: preferredSize),
        display: true
      )
    }

    self.minSize = NSSize(width: 1100, height: 720)
    self.title = "Мягкие окна"

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
