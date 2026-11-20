// Capturas del dashboard con el motor de Safari (WKWebView), sin almacenamiento persistente.
// uso: snap <url> <outdir> <ancho> <alto> <prep.js|-> nombre=selector [nombre=selector …]
import Cocoa
import WebKit

let a = CommandLine.arguments
let url = URL(string: a[1])!, outDir = a[2], W = CGFloat(Double(a[3])!), H = CGFloat(Double(a[4])!)
let prep = a[5] == "-" ? "" : (try? String(contentsOfFile: a[5], encoding: .utf8)) ?? ""
var shots = a.dropFirst(6).map { s -> (String, String) in let p = s.split(separator: "=", maxSplits: 1).map(String.init); return (p[0], p[1]) }

final class Snap: NSObject, WKNavigationDelegate {
    var win: NSWindow!, web: WKWebView!
    func start() {
        let cfg = WKWebViewConfiguration(); cfg.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: W, height: H), configuration: cfg)
        web.navigationDelegate = self
        win = NSWindow(contentRect: NSRect(x: 40, y: 40, width: W, height: H), styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = web; win.alphaValue = 0.01; win.ignoresMouseEvents = true; win.orderBack(nil)
        web.load(URLRequest(url: url))
    }
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.next() }
    }
    func next() {
        guard !shots.isEmpty else { exit(0) }
        let (name, sel) = shots.removeFirst()
        let js = """
        (function(){ \(prep)
          const el=document.querySelector(\(String(reflecting: sel))); if(!el) return null;
          document.documentElement.style.scrollBehavior='auto';
          const r0=el.getBoundingClientRect(); window.scrollTo({top:Math.max(0,scrollY+r0.top-90),behavior:'instant'});
          document.querySelectorAll('.rv').forEach(u=>u.classList.add('in','settled'));
          try{ window.__playRace&&window.__playRace(); }catch(e){}
          document.getAnimations().forEach(x=>{ try{ x.finish(); }catch(e){} });
          document.querySelectorAll('#race path.draw').forEach(p=>{ p.style.strokeDasharray='none'; });
          const r=el.getBoundingClientRect(); return [r.left,r.top,r.width,r.height]; })()
        """
        web.evaluateJavaScript(js) { v, err in
            guard let r = v as? [Double] else { FileHandle.standardError.write("sin \(name): \(String(describing: err))\n".data(using: .utf8)!); self.next(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                let c = WKSnapshotConfiguration()
                let pad = 10.0
                c.rect = NSRect(x: max(0, r[0] - pad), y: max(0, r[1] - pad), width: min(Double(W), r[2] + 2 * pad), height: min(Double(H), r[3] + 2 * pad))
                self.web.takeSnapshot(with: c) { img, _ in
                    if let t = img?.tiffRepresentation, let rep = NSBitmapImageRep(data: t), let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: outDir + "/" + name + ".png")); print("ok \(name) \(rep.pixelsWide)x\(rep.pixelsHigh)")
                    }
                    self.next()
                }
            }
        }
    }
}
let app = NSApplication.shared; app.setActivationPolicy(.accessory)
let s = Snap(); s.start()
DispatchQueue.main.asyncAfter(deadline: .now() + 90) { exit(2) }
app.run()
