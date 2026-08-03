import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Brand-teal launch background so the window doesn't flash white before
    // Flutter's first frame (desktop has no native splash-screen mechanism).
    self.backgroundColor = NSColor(
      srgbRed: 13 / 255, green: 98 / 255, blue: 115 / 255, alpha: 1)

    super.awakeFromNib()
  }
}
