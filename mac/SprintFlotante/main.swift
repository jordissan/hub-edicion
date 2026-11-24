// Sprint flotante — el Sprint de enfoque del Hub de Edición integrado en el Mac:
//  · un reloj en la barra de menús (tiempo que llevas / descanso) con un menú para terminar,
//    cerrar escena/etapa, descartar o empezar el siguiente bloque, finalizar la etapa elegida
//    sin bloque en marcha (si al terminar no la cerraste), y elegir la etapa, la
//    escena y el esquema del próximo bloque (Etapa ▸ / Escena ▸ / Tipo ▸ / Esquema ▸, como la ventana);
//  · la tarjeta del sprint en una ventanita propia que se arrastra desde cualquier zona sin
//    controles, siempre encima (también sobre Premiere/Resolve en pantalla completa) o fijada
//    al escritorio como un widget.
//
// No reimplementa el sprint: la ventana carga http://localhost:4599/?mini=1 (el mismo
// index.html en modo mini) y las acciones del menú llaman a window.SprintCmd en esa página
// (aunque esté oculta). El reloj de la barra lee /api/sprint-state de server.py cada segundo,
// así refleja también lo que hagas en el dashboard.
//
// Cerrar la ventana solo la oculta: la app sigue en la barra de menús (⌘Q o "Salir" la cierra).
// Se abre al iniciar sesión (opción del menú). Compilar e instalar: ./build.sh
//
// Atajos globales (funcionan con cualquier app al frente, sin permiso de Accesibilidad:
// Carbon RegisterEventHotKey): ⌃⌥N inicia el sprint o, si corre, lo termina y registra;
// ⌃⌥⇧N lo descarta sin registrar; ⌃⌥⌘N muestra/oculta la ventana; ⌃⌥B alterna el tipo de
// sesión Edición ↔ Gestión (no con un bloque en marcha). Se cambian en
// Opciones → Atajo de teclado (la tecla base; ⇧ y ⌘ se añaden solos y la B sigue a los mismos ⌃⌥).
// Sonidos de cada acción (iniciar, terminar, descartar, meta, error): Opciones → Sonidos.
// Siri / Atajos: hubsprint://start empieza un bloque (esquema y etapa ya elegidos),
// hubsprint://finish lo termina y registra, hubsprint://toggle alterna (como ⌃⌥N).
// Sin internet: server.py guarda cada sesión/cierre en su cola del Mac (.outbox.json) y la sube
// sola. Esta app solo la muestra (icono ☁︎↑ + número en la barra, en reposo; detalle en el menú)
// y le avisa en cuanto vuelve la red (NWPathMonitor) o despierta el Mac → POST /api/outbox/flush.
// Detector de Final Cut: si editas (Final Cut o Premiere al frente, con teclado o ratón en uso)
// sin bloque en marcha, el reloj pide iniciar y, si sigues, aparece la ventana. Opciones → Detector.
// Prueba contra otro server: HUB_BASE=http://localhost:4611 …/SprintFlotante

import Cocoa
import Carbon.HIToolbox
import WebKit
import ServiceManagement
import Network

let BASE = ProcessInfo.processInfo.environment["HUB_BASE"] ?? "http://localhost:4599"
let HUB = URL(string: BASE + "/?mini=1")!
let STATE_URL = URL(string: BASE + "/api/sprint-state")!     // sin ?from=mini: no hace de latido
let FLUSH_URL = URL(string: BASE + "/api/outbox/flush")!      // "sube ya la cola" (volvió la red / despertó)
let DASH_APP = (("~/Applications/Hub de Edición.app") as NSString).expandingTildeInPath
/// Fondo de la ventana mientras carga la página: el de la tarjeta compacta (--bg), oscuro o claro según el sistema.
let PANEL_BG = NSColor(name: nil) { a in
    a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(srgbRed: 0x05 / 255.0, green: 0x05 / 255.0, blue: 0x06 / 255.0, alpha: 1)
        : NSColor(srgbRed: 0xf0 / 255.0, green: 0xee / 255.0, blue: 0xe9 / 255.0, alpha: 1)
}
let DRAG_STRIP: CGFloat = 48      // franja superior que arrastra (= cabecera .cl en modo mini: 14 + 32 px)
let BUTTONS_W: CGFloat = 84       // salvo a la derecha, donde están volver/cerrar
let MODES = ["med": "Mediana", "pomo": "Pomodoro", "s5217": "52/17", "deep": "90", "libre": "Libre", "custom": "Propio"]
let D = UserDefaults.standard
let HUB_LOG = ProcessInfo.processInfo.environment["HUB_LOG"] != nil     // prueba: registra atajos en el log

/// Panel flotante que puede recibir teclado (minutos en "Ajustar") sin activar la app,
/// así Premiere sigue siendo la app activa mientras usas el sprint.
final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// WKWebView que deja arrastrar la ventana desde la franja superior y desde cualquier zona
/// sin controles: al mover el ratón (aunque la ventana no tenga el foco) le pregunta a la
/// página qué hay debajo (window.__hubDragAt), y en el mousedown ya lo sabe.
final class HubWebView: WKWebView {
    var dragOK = false
    var dragKnown = false        // la página contestó para este punto (sin página no hay respuesta)
    var asking = false
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if !trackingAreas.contains(where: { $0.owner === self && $0.userInfo?["hub"] != nil }) {
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self, userInfo: ["hub": true]))
        }
    }
    override func mouseMoved(with e: NSEvent) {
        super.mouseMoved(with: e)
        guard !asking else { return }
        let p = convert(e.locationInWindow, from: nil)
        let y = isFlipped ? p.y : bounds.height - p.y
        asking = true
        evaluateJavaScript("window.__hubDragAt ? window.__hubDragAt(\(Int(p.x)), \(Int(y))) : null") { [weak self] v, _ in
            self?.dragKnown = v is Bool
            self?.dragOK = (v as? Bool) ?? false
            self?.asking = false
        }
    }
    override func mouseExited(with e: NSEvent) { super.mouseExited(with: e); dragOK = false; dragKnown = false }
    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        let fromTop = isFlipped ? p.y : bounds.height - p.y
        // la franja de arriba arrastra, salvo sobre un control que la página señale (p. ej. el menú del esquema)
        let overControl = dragKnown && !dragOK
        if (fromTop < DRAG_STRIP && p.x < bounds.width - BUTTONS_W && !overControl) || dragOK {
            window?.performDrag(with: e)
            return
        }
        super.mouseDown(with: e)
    }
}

/// Lo que dice server.py del sprint (las mismas claves que guarda el index.html).
struct Sprint {
    var online = false
    var run: [String: Any]? = nil
    var brk: [String: Any]? = nil
    var pend = false
    var close: [String: Any]? = nil
    var mode = "med"
    var cycle = 1
    // cola local de server.py: lo guardado sin internet que espera subir a Notion
    var queued: [[String: Any]] = []
    var sentAt: Double = 0, sentN = 0

    init() {}
    init(_ j: [String: Any]) {
        online = true
        let d = j["data"] as? [String: Any] ?? [:]
        run = d["scSprint"] as? [String: Any]
        brk = d["scSprintBrk"] as? [String: Any]
        pend = d["scSprintPend"] is [String: Any] || !((d["scSprintPend"] as? [Any])?.isEmpty ?? true)
        let ob = j["outbox"] as? [String: Any] ?? [:]
        queued = ob["items"] as? [[String: Any]] ?? []
        if let st = ob["sent"] as? [String: Any] { sentAt = num(st["at"]); sentN = Int(num(st["n"])) }
        close = d["scSprintClose"] as? [String: Any]
        mode = (d["scSprintMode"] as? [String: Any])?["k"] as? String ?? "med"
        cycle = (d["scSprintCyc"] as? [String: Any])?["n"] as? Int ?? 1
    }
}

func num(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }
func str(_ v: Any?) -> String { v as? String ?? "" }
func clock(_ secs: Double) -> String {
    let s = Int(abs(secs).rounded(.down))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                     : String(format: "%02d:%02d", s / 60, s % 60)
}
func hhmm(_ ms: Double) -> String {
    let f = DateFormatter(); f.dateFormat = "HH:mm"
    return f.string(from: Date(timeIntervalSince1970: ms / 1000))
}
let nowMs = { Date().timeIntervalSince1970 * 1000 }

/// Atajo global: tecla (keyCode virtual) + modificadores. El de descartar es el mismo con ⇧
/// y el de mostrar/ocultar la ventana, el mismo con ⌘ (⌃⌥⌘N, libre en Final Cut y Premiere).
/// ⌃⌥N por defecto: libre en Final Cut (set JORDISSAN y el de serie), Premiere y macOS
/// (⌃⌥S y ⌃⌥T los usa Final Cut). ⌃⌥ es el prefijo de VoiceOver, solo choca si está activo.
struct HotKey: Equatable {
    var code: Int, mods: NSEvent.ModifierFlags, char: String
    static let presets: [HotKey] = [("N", kVK_ANSI_N), ("B", kVK_ANSI_B), ("P", kVK_ANSI_P), ("J", kVK_ANSI_J), ("K", kVK_ANSI_K)]
        .map { HotKey(code: $0.1, mods: [.control, .option], char: $0.0) }
    static func == (a: HotKey, b: HotKey) -> Bool { a.code == b.code && a.mods == b.mods }

    var carbonMods: UInt32 {
        var m: UInt32 = 0
        if mods.contains(.control) { m |= UInt32(controlKey) }
        if mods.contains(.option) { m |= UInt32(optionKey) }
        if mods.contains(.command) { m |= UInt32(cmdKey) }
        if mods.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }
    func label(shift: Bool = false, cmd: Bool = false) -> String {
        (mods.contains(.control) ? "⌃" : "") + (mods.contains(.option) ? "⌥" : "") + (shift ? "⇧" : "")
            + (mods.contains(.command) || cmd ? "⌘" : "") + char.uppercased()
    }
    /// Atajo de alternar Edición ↔ Gestión: los mismos modificadores que el principal y la letra B
    /// (si la tecla base ya es la B, la N, para no pisarse).
    var tipoKey: (code: Int, char: String) { code == kVK_ANSI_B ? (kVK_ANSI_N, "N") : (kVK_ANSI_B, "B") }
    var tipoLabel: String {
        (mods.contains(.control) ? "⌃" : "") + (mods.contains(.option) ? "⌥" : "")
            + (mods.contains(.command) ? "⌘" : "") + tipoKey.char
    }
    var menuTitle: String { "\(label()) · \(label(shift: true)) descarta · \(label(cmd: true)) ventana · \(tipoLabel) tipo" }
    static func load() -> HotKey? {
        guard !D.bool(forKey: "hkOff") else { return nil }
        guard D.object(forKey: "hkCode") != nil else { return presets[0] }
        return HotKey(code: D.integer(forKey: "hkCode"),
                      mods: NSEvent.ModifierFlags(rawValue: UInt(D.integer(forKey: "hkMods"))),
                      char: D.string(forKey: "hkChar") ?? "?")
    }
    func save() {
        D.set(false, forKey: "hkOff"); D.set(code, forKey: "hkCode")
        D.set(Int(mods.rawValue), forKey: "hkMods"); D.set(char, forKey: "hkChar")
    }
}

/// Sonido de cada acción, elegible en Opciones → Sonidos (UserDefaults "snd.<acción>").
/// Valor: nombre de un sonido del sistema (/System/Library/Sounds o ~/Library/Sounds),
/// SYS = el aviso del sistema (NSSound.beep) u OFF = ninguno.
enum Sounds {
    static let SYS = "·sistema", OFF = ""
    static let actions: [(key: String, title: String, def: String)] = [
        ("start", "Iniciar", "Tink"),
        ("finish", "Terminar", "Hero"),
        ("discard", "Descartar", "Funk"),
        ("goal", "Meta y fin del descanso", "Glass"),
        ("tipo", "Cambiar Edición/Gestión", "Pop"),
        ("nudge", "Editas sin timer", "Purr"),
        ("error", "No se pudo", SYS),
    ]
    static func get(_ a: String) -> String {
        D.string(forKey: "snd." + a) ?? actions.first(where: { $0.key == a })?.def ?? OFF
    }
    static func set(_ a: String, _ v: String) { D.set(v, forKey: "snd." + a) }
    static func play(name v: String) {
        if v == SYS { NSSound.beep() } else if !v.isEmpty { NSSound(named: v)?.play() }
    }
    static func play(_ a: String) { play(name: get(a)) }
    /// Sonidos instalados (sistema + los tuyos en ~/Library/Sounds), sin repetir, por nombre.
    static var available: [String] {
        let fm = FileManager.default
        let dirs = ["/System/Library/Sounds", ("~/Library/Sounds" as NSString).expandingTildeInPath]
        let exts: Set<String> = ["aiff", "aif", "wav", "caf", "mp3", "m4a"]
        var names = Set<String>()
        for d in dirs {
            for f in (try? fm.contentsOfDirectory(atPath: d)) ?? [] where exts.contains((f as NSString).pathExtension.lowercased()) {
                names.insert((f as NSString).deletingPathExtension)
            }
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

/// Fila de menú con vista propia: al hacer clic ejecuta su acción **sin cerrar el menú** (un
/// NSMenuItem normal lo cierra siempre). La usan Etapa ▸ / Escena ▸ / Tipo ▸ / Esquema ▸ para
/// cambiar varias cosas seguidas; el menú se cierra al hacer clic fuera o con Esc.
/// El NSMenuItem conserva título, estado y acción (los lee la prueba DUMP_MENU); la vista solo
/// dibuja (resaltado, ✓, texto) y reenvía el clic.
final class StayRow: NSView {
    let text: String, header: Bool
    var on = false { didSet { if on != oldValue { needsDisplay = true } } }
    static let font = NSFont.menuFont(ofSize: 0)
    static let headerFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
    static let textX: CGFloat = 22, maxW: CGFloat = 420

    init(_ text: String, header: Bool = false) {
        self.text = text; self.header = header
        let w = ceil((text as NSString).size(withAttributes: [.font: header ? StayRow.headerFont : StayRow.font]).width)
        super.init(frame: NSRect(x: 0, y: 0, width: min(max(w + StayRow.textX + 24, 140), StayRow.maxW),
                                 height: header ? 20 : 22))
        autoresizingMask = .width                  // el menú la estira a su ancho
        setAccessibilityElement(true)
        setAccessibilityRole(header ? .staticText : .menuItem)
        setAccessibilityLabel(text)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    var highlighted: Bool { !header && enclosingMenuItem?.isHighlighted == true && enclosingMenuItem?.isEnabled == true }

    override func draw(_ r: NSRect) {
        let hl = highlighted
        if hl {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 4, yRadius: 4).fill()
        }
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: header ? StayRow.headerFont : StayRow.font, .paragraphStyle: para,
            .foregroundColor: header ? NSColor.secondaryLabelColor : hl ? NSColor.white : NSColor.labelColor]
        let h = ceil((text as NSString).size(withAttributes: attrs).height), y = (bounds.height - h) / 2
        if on { ("✓" as NSString).draw(at: NSPoint(x: 9, y: y), withAttributes: attrs) }
        let x = header ? 14 : StayRow.textX
        (text as NSString).draw(with: NSRect(x: x, y: y, width: bounds.width - x - 12, height: h),
                                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
    }

    // el menú no siempre repinta una vista al mover el resaltado: que se repinte al entrar y salir
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }
    override func mouseEntered(with e: NSEvent) { needsDisplay = true }
    override func mouseExited(with e: NSEvent) { needsDisplay = true }

    override func mouseUp(with e: NSEvent) {
        guard !header, let i = enclosingMenuItem, i.isEnabled, let a = i.action else { return }
        NSApp.sendAction(a, to: i.target, from: i)
        needsDisplay = true
    }
}

/// Vista previa: al pasar por un sonido del submenú, suena (sin elegirlo todavía).
final class SoundPreview: NSObject, NSMenuDelegate {
    var current: NSSound?
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        current?.stop(); current = nil
        guard let v = (item?.representedObject as? [String])?.last else { return }
        if v == Sounds.SYS { NSSound.beep() } else if !v.isEmpty { current = NSSound(named: v); current?.play() }
    }
    func menuDidClose(_ menu: NSMenu) { current?.stop(); current = nil }
}

// DETECTOR-INICIO · lógica pura del detector (sin AppKit: la prueba automática extrae este bloque)
struct DetConfig { var wait = 120.0, escalate = 300.0, snooze = 1200.0, idle = 180.0 }
struct DetInput {
    var now: Double, dt: Double
    var watchedFront: Bool, inputIdle: Double
    var running: Bool, atRest: Bool
}
enum DetPhase: String { case idle, nudged, escalated, muted }
enum DetEvent: Equatable { case nudge, escalate, cleared }

/// idle → (wait s editando) nudged → (escalate s más) escalated → (snooze s) idle.
/// Solo cuenta el tiempo con la app vigilada al frente y en uso; al cambiar de app se pausa, y si
/// pasan snooze s sin editar, empieza de cero. muted = «Ahora no», hasta cerrar la app vigilada.
struct Detector {
    private(set) var phase = DetPhase.idle
    private(set) var active = 0.0
    private var until = 0.0, lastActive = 0.0
    var prompting: Bool { phase == .nudged || phase == .escalated }

    mutating func step(_ i: DetInput, _ c: DetConfig) -> [DetEvent] {
        if i.running {
            active = 0
            if prompting { phase = .idle; return [.cleared] }
            return []
        }
        guard i.atRest, phase != .muted else { return [] }
        if phase == .escalated {
            guard i.now >= until else { return [] }
            clear(); return [.cleared]
        }
        if i.watchedFront && i.inputIdle < c.idle {
            active += i.dt; lastActive = i.now
        } else if (active > 0 || phase == .nudged) && i.now - lastActive >= c.snooze {
            clear(); return [.cleared]
        }
        if phase == .idle && active >= c.wait { phase = .nudged; active = 0; return [.nudge] }
        if phase == .nudged && active >= c.escalate {
            phase = .escalated; active = 0; until = i.now + c.snooze
            return [.escalate]
        }
        return []
    }
    mutating func mute() { phase = .muted; active = 0 }
    mutating func clear() { phase = .idle; active = 0 }
}
// DETECTOR-FIN

/// Apps que vigila el detector (Opciones → Detector). Premiere cambia de bundle id con cada versión.
let DET_APPS: [(key: String, name: String, matches: (String) -> Bool)] = [
    ("fcp", "Final Cut", { $0 == "com.apple.FinalCut" || $0 == "com.apple.FinalCutTrial" }),
    ("premiere", "Premiere", { $0.hasPrefix("com.adobe.PremierePro") }),
]
/// Tiempos elegibles en Opciones → Detector (clave, título, segundos).
let DET_TIMES: [(key: String, title: String, opts: [Int])] = [
    ("det.wait", "Primer aviso a los", [60, 120, 180, 300]),
    ("det.escalate", "Ventana tras otros", [180, 300, 600]),
    ("det.snooze", "Sin repetir durante", [600, 1200, 1800, 3600]),
    ("det.idle", "Deja de contar sin actividad a los", [60, 180, 300]),
]


/// El icono de la barra de menús: el mismo símbolo del Hub que está en el Dock (un playhead
/// recorriendo tres capas de la línea de tiempo), reducido a un color como imagen *template*,
/// así macOS lo pinta en blanco o negro según el tema y la barra, igual que los SF Symbols.
/// Reglas de la reducción (lienzo de 18 pt, vectores):
/// - Todo cae en la retícula de 1 pt, así se ve nítido a 1x y a 2x.
/// - Un solo grosor de trazo (2 pt) para capas y playhead, como el peso regular del sistema.
/// - La jerarquía del Dock (playhead de acento, capas en grises) se pasa a opacidad: el playhead
///   al 100 % y las capas al 90/70/50 %, de arriba abajo, como el blanco y los dos grises del icono.
/// - Las capas se cortan 1 pt antes y después del playhead, para que se lea encima de ellas.
enum HubIcon {
    static let name = "hub"            // el nombre que usa render() (y la prueba sin pantalla)
    static let image: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ alpha: CGFloat) {
                NSColor(white: 0, alpha: alpha).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: 2), xRadius: 1, yRadius: 1).fill()
            }
            // las capas (el playhead pasa por x = 9…11)
            bar(2, 6, 7, 0.9)                          // video 1
            bar(5, 10, 4, 0.7); bar(11, 10, 5, 0.7)    // video 2
            bar(2, 14, 7, 0.5); bar(11, 14, 2, 0.5)    // audio
            // el playhead: cabeza en trapecio (6 pt, tres veces el trazo) y la línea hacia abajo
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 7, y: 1, width: 6, height: 2.2), xRadius: 0.5, yRadius: 0.5).fill()
            let taper = NSBezierPath()
            taper.move(to: NSPoint(x: 7, y: 3)); taper.line(to: NSPoint(x: 13, y: 3))
            taper.line(to: NSPoint(x: 11, y: 5)); taper.line(to: NSPoint(x: 9, y: 5))
            taper.close(); taper.fill()
            NSBezierPath(roundedRect: NSRect(x: 9, y: 4, width: 2, height: 13.5), xRadius: 1, yRadius: 1).fill()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Sprint de enfoque"
        return img
    }()
}

final class App: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate,
                 WKUIDelegate, NSMenuDelegate {
    var panel: Panel!
    var web: HubWebView!
    var retry: Timer?
    var item: NSStatusItem!
    var sprint = Sprint()
    var dest = "", note = ""           // lo que propone la página (destino del próximo bloque, último aviso)
    var pick: [String: Any] = [:]      // listas de etapa/escena/tipo/esquema de la página (mensaje "state" de tellNative)
    var pickItems: [String: NSMenuItem] = [:]   // "Etapa: …" / "Escena: …" / "Tipo: …" / "Esquema: …" del menú abierto
    var polling = false
    var liveItem: NSMenuItem?          // la línea del menú que cuenta en vivo mientras está abierto
    var tipoToggleItem: NSMenuItem?    // «Cambiar a «…»» del menú abierto (cambia al elegir otro tipo)
    var chimed = ""
    let preview = SoundPreview()
    var hotRefs: [EventHotKeyRef] = []
    var flash: (symbol: String, until: Date, text: String)? = nil   // destello del reloj al usar el atajo (+ texto breve)
    var recorder: Any? = nil
    var symbolNow = ""                 // el icono de la barra (para la prueba sin pantalla)
    let netMonitor = NWPathMonitor()
    var netUp: Bool? = nil
    var detector = Detector()
    var detFront = ""                  // bundle id de la app al frente
    var detLabel = "Final Cut"         // la última app vigilada que estuvo al frente
    var detLastTick = Date()
    var detOpenedPanel = false         // la ventana la abrió el detector: se oculta al iniciar el bloque
    var detAsking = false              // diálogo de «¿Terminar el bloque?» abierto
    var poweringOff = false            // apagando o cerrando sesión: sin diálogos
    #if DUMP_MENU
    var detFakeIdle: Double? = nil     // prueba: segundos sin teclado ni ratón simulados
    #endif
    let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 3
        return URLSession(configuration: c)
    }()

    // ───────────────────────── arranque ─────────────────────────
    func applicationDidFinishLaunching(_ n: Notification) {
        D.register(defaults: ["panelVisible": true, "onDesktop": false, "showRemaining": false,
                              "det.on": true, "det.apps": DET_APPS.map { $0.key },
                              "det.wait": 120, "det.escalate": 300, "det.snooze": 1200, "det.idle": 180])

        panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 450),
                      styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                      backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(b)?.isHidden = true
        }
        panel.title = "Sprint flotante"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 240, height: 170)
        panel.backgroundColor = PANEL_BG
        panel.isReleasedWhenClosed = false
        if !panel.setFrameUsingName("SprintFlotante"), let s = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: s.maxX - 340 - 24, y: s.maxY - 450 - 24))   // arriba a la derecha
        }
        panel.setFrameAutosaveName("SprintFlotante")
        applyLevel()

        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "hub")
        cfg.mediaTypesRequiringUserActionForPlayback = []     // el aviso sonoro del fin de bloque
        web = HubWebView(frame: panel.contentView!.bounds, configuration: cfg)
        web.autoresizingMask = [.width, .height]
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = self
        web.uiDelegate = self
        panel.contentView = web
        setShownScript(D.bool(forKey: "panelVisible"))
        web.load(URLRequest(url: HUB))
        if D.bool(forKey: "panelVisible") { panel.orderFrontRegardless() }

        // reloj de la barra de menús
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageLeading
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        render()
        poll()
        startDetector()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.poll(); self?.detectorTick(); self?.render()
        }
        RunLoop.main.add(t, forMode: .common)     // sigue contando con el menú abierto

        installHotKeyHandler()
        registerHotKeys()

        // sin internet server.py guarda en su cola; al volver la red (o despertar el Mac) que suba ya,
        // sin esperar a su reintento (cada 30-120 s)
        netMonitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            DispatchQueue.main.async {
                guard let self else { return }
                let was = self.netUp
                self.netUp = up
                if up && was == false { self.flushOutbox(after: 2) }
            }
        }
        netMonitor.start(queue: DispatchQueue(label: "hub.red"))
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in self?.flushOutbox(after: 8) }

        // la primera vez se apunta para abrirse al iniciar sesión (se quita desde el menú)
        if !D.bool(forKey: "loginSetup") {
            D.set(true, forKey: "loginSetup")
            try? SMAppService.mainApp.register()
        }

        // ⌘W oculta la ventana · ⌘Q sale · ⌘R recarga (la app no tiene menú propio)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard e.modifierFlags.contains(.command), let k = e.charactersIgnoringModifiers else { return e }
            if k == "w" { self?.hidePanel(); return nil }
            if k == "q" { NSApp.terminate(nil); return nil }
            if k == "r" { self?.web.load(URLRequest(url: HUB)); return nil }
            return e
        }

        #if DUMP_MENU
        dumpMenuTest()
        #endif
        let early = earlyURLs; earlyURLs = []
        if !early.isEmpty { application(NSApp, open: early) }
    }

    // hubsprint://open (botón de la tarjeta del dashboard) → muestra la ventana.
    // hubsprint://start · finish · toggle (Atajos / Siri) → la orden, sin traer la ventana;
    // si la URL abre la app en frío, reintenta mientras carga la página (~15 s).
    // En frío macOS entrega la URL ANTES de applicationDidFinishLaunching (aún no hay ventana
    // ni página): se guarda y se atiende al final del arranque.
    var earlyURLs: [URL] = []
    func application(_ app: NSApplication, open urls: [URL]) {
        if web == nil { earlyURLs += urls; return }
        for u in urls {
            switch u.host?.lowercased() {
            case "start", "finish", "toggle": run(u.host!.lowercased(), tries: 30)
            default: showPanel()
            }
        }
    }

    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showPanel(); return true
    }

    // ───────────────────────── ventana ─────────────────────────
    @objc func showPanel() {
        panel.orderFrontRegardless()
        setShown(true)
    }

    @objc func hidePanel() {
        panel.orderOut(nil)
        setShown(false)
        if detOpenedPanel { detOpenedPanel = false; applyLevel() }
    }

    @objc func togglePanel() { panel.isVisible ? hidePanel() : showPanel() }

    /// La página necesita saber si se ve: oculta no hace de latido (el dashboard vuelve a sonar)
    /// ni suena ella. Se fija en la página viva y para las recargas.
    func setShown(_ on: Bool) {
        D.set(on, forKey: "panelVisible")
        setShownScript(on)
        web.evaluateJavaScript("window.__hubShown=\(on); window.SprintCmd&&window.SprintCmd('sync');"
                               + (on ? " window.__hubFit&&window.__hubFit();" : ""))
    }

    /// La ventana mide lo que la tarjeta: la página manda su alto (mensaje "height") y aquí se fija,
    /// conservando el borde de arriba. Solo el ancho queda libre para el usuario.
    func fitHeight(_ h: CGFloat) {
        guard h > 60, h < 2000, let web else { return }
        let fh = (max(120, h) + panel.frame.height - web.bounds.height).rounded()
        panel.minSize = NSSize(width: 240, height: fh)
        panel.maxSize = NSSize(width: 4000, height: fh)
        guard abs(panel.frame.height - fh) >= 1 else { return }
        var f = panel.frame
        f.origin.y = f.maxY - fh
        f.size.height = fh
        panel.setFrame(f, display: true, animate: false)
        if HUB_LOG { NSLog("SprintFlotante alto de la tarjeta %.0f → ventana %.0f×%.0f", h, f.width, f.height) }
    }

    func setShownScript(_ on: Bool) {
        let uc = web?.configuration.userContentController
        uc?.removeAllUserScripts()
        uc?.addUserScript(WKUserScript(source: "window.__hubShown=\(on);", injectionTime: .atDocumentStart,
                                       forMainFrameOnly: true))
    }

    func applyLevel() {
        if D.bool(forKey: "onDesktop") && !detOpenedPanel {     // el aviso del detector siempre va encima
            // como un widget: justo encima de los iconos del escritorio, detrás de las ventanas
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        } else {
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
    }

    @objc func setFloating(_ s: NSMenuItem) {
        D.set(s.tag == 1, forKey: "onDesktop")
        detOpenedPanel = false
        applyLevel()
        if !panel.isVisible { showPanel() }
    }

    @objc func openDashboard() {
        if FileManager.default.fileExists(atPath: DASH_APP) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: DASH_APP), configuration: .init())
        } else {
            NSWorkspace.shared.open(URL(string: BASE + "/")!)
        }
    }

    // ───────────────────────── cola sin internet ─────────────────────────
    /// Le pide a server.py que suba su cola ya (si no hay nada, no hace nada).
    func flushOutbox(after secs: Double = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + secs) { [weak self] in
            guard let self else { return }
            var req = URLRequest(url: FLUSH_URL)
            req.httpMethod = "POST"
            self.session.dataTask(with: req) { _, _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.poll() }
            }.resume()
        }
    }
    @objc func flushNow() { flushOutbox() }

    /// "2 sesiones (52 min) y 1 cierre" de lo que espera en la cola.
    func queuedText() -> String {
        let q = sprint.queued
        let ses = q.filter { str($0["kind"]) == "session" }, nc = q.count - ses.count
        let mins = ses.reduce(0) { $0 + Int(num($1["mins"])) }
        var parts: [String] = []
        if !ses.isEmpty { parts.append("\(ses.count) \(ses.count == 1 ? "sesión" : "sesiones") (\(mins) min)") }
        if nc > 0 { parts.append("\(nc) \(nc == 1 ? "cierre" : "cierres")") }
        return parts.joined(separator: " y ")
    }

    // ───────────────────────── detector de Final Cut ─────────────────────────
    /// Nombre de la app si está vigilada (Opciones → Detector); nil si no.
    func detName(_ bundle: String?) -> String? {
        guard let bundle, !bundle.isEmpty else { return nil }
        #if DUMP_MENU
        if bundle == ProcessInfo.processInfo.environment["HUB_DET_BUNDLE"] { return "Final Cut" }
        #endif
        let on = D.stringArray(forKey: "det.apps") ?? []
        return DET_APPS.first { on.contains($0.key) && $0.matches(bundle) }?.name
    }

    var detConfig: DetConfig {
        DetConfig(wait: D.double(forKey: "det.wait"), escalate: D.double(forKey: "det.escalate"),
                  snooze: D.double(forKey: "det.snooze"), idle: D.double(forKey: "det.idle"))
    }

    /// Segundos desde el último uso de teclado o ratón (no pide permisos de Accesibilidad).
    func detInputIdle() -> Double {
        #if DUMP_MENU
        if let f = detFakeIdle { return f }
        #endif
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    func startDetector() {
        detFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            self?.detFront = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier ?? ""
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            self?.detAppClosed(n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
        nc.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { [weak self] _ in
            self?.poweringOff = true
        }
    }

    /// Cada segundo: con un bloque en marcha apaga el aviso; en reposo cuenta y avisa.
    func detectorTick() {
        let now = Date(), dt = max(0, min(now.timeIntervalSince(detLastTick), 5))     // el Mac dormido no cuenta
        detLastTick = now
        if sprint.run != nil && detOpenedPanel { hidePanel() }
        guard D.bool(forKey: "det.on") else {
            if detector.phase != .idle { detector.clear() }
            if detOpenedPanel { hidePanel() }
            return
        }
        let name = detName(detFront)
        if let name { detLabel = name }
        // un descanso ya vencido sigue guardado hasta empezar otro bloque: cuenta como reposo
        let onBreak = sprint.brk.map { num($0["secs"]) - (nowMs() - num($0["start"])) / 1000 > 0 } ?? false
        let input = DetInput(now: now.timeIntervalSince1970, dt: dt, watchedFront: name != nil, inputIdle: detInputIdle(),
                             running: sprint.run != nil, atRest: sprint.online && !onBreak && sprint.close == nil)
        for e in detector.step(input, detConfig) {
            if HUB_LOG { NSLog("SprintFlotante detector %@ → %@", String(describing: e), detector.phase.rawValue) }
            switch e {
            case .nudge:
                Sounds.play("nudge")
                send("tipo:Edición") { _ in }
            case .escalate:
                if !panel.isVisible { detOpenedPanel = true; applyLevel(); showPanel() }    // sin robar el foco
            case .cleared: break
            }
        }
    }

    @objc func detStart() { run("start") }

    /// «Ahora no»: calla hasta que cierres la app vigilada.
    @objc func detMute() {
        detector.mute()
        if detOpenedPanel { hidePanel() }
        render()
    }

    /// Se cerró una app: si era la última vigilada, el aviso se apaga y, con un bloque corriendo, pregunta.
    func detAppClosed(_ a: NSRunningApplication?) {
        guard let name = detName(a?.bundleIdentifier) else { return }
        let others = NSWorkspace.shared.runningApplications.contains {
            $0 != a && !$0.isTerminated && detName($0.bundleIdentifier) != nil
        }
        guard !others else { return }
        detector.clear()
        if detOpenedPanel { hidePanel() }
        render()
        guard D.bool(forKey: "det.on"), !poweringOff, !detAsking, let r = sprint.run else { return }
        let mins = max(1, Int((nowMs() - num(r["start"])) / 60_000))
        DispatchQueue.main.async { [weak self] in self?.detAskFinish(name, mins: mins) }
    }

    func detAskFinish(_ name: String, mins: Int) {
        detAsking = true
        defer { detAsking = false }
        let text = "Llevas \(mins) min. ¿Terminar el bloque?"
        #if DUMP_MENU
        let finish = ProcessInfo.processInfo.environment["HUB_DET_ANSWER"] == "terminar"
        print("diálogo: \(text) → \(finish ? "Terminar" : "Seguir")"); fflush(stdout)
        #else
        let al = NSAlert()
        al.messageText = text
        al.informativeText = "Cerraste \(name) y el bloque sigue corriendo."
        al.addButton(withTitle: "Terminar")
        al.addButton(withTitle: "Seguir")
        NSApp.activate(ignoringOtherApps: true)
        let finish = al.runModal() == .alertFirstButtonReturn
        NSApp.deactivate()
        #endif
        if finish && sprint.run != nil { run("finish") }
    }

    /// Opciones → Detector: interruptor, apps vigiladas y tiempos.
    func detectorMenu() -> NSMenu {
        let m = NSMenu()
        let on = NSMenuItem(title: "Avisar si edito sin timer", action: #selector(detToggle), keyEquivalent: "")
        on.target = self; on.state = D.bool(forKey: "det.on") ? .on : .off
        m.addItem(on)
        m.addItem(.separator())
        let apps = D.stringArray(forKey: "det.apps") ?? []
        for a in DET_APPS {
            let i = NSMenuItem(title: a.name, action: #selector(detToggleApp(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = a.key; i.state = apps.contains(a.key) ? .on : .off
            m.addItem(i)
        }
        m.addItem(.separator())
        let label = { (s: Int) in s % 60 == 0 ? "\(s / 60) min" : "\(s) s" }
        for t in DET_TIMES {
            let cur = Int(D.double(forKey: t.key)), sub = NSMenu()
            for v in t.opts {
                let i = NSMenuItem(title: label(v), action: #selector(detPickTime(_:)), keyEquivalent: "")
                i.target = self; i.representedObject = [t.key, String(v)]; i.state = v == cur ? .on : .off
                sub.addItem(i)
            }
            let i = NSMenuItem(title: "\(t.title): \(label(cur))", action: nil, keyEquivalent: "")
            i.submenu = sub
            m.addItem(i)
        }
        return m
    }

    @objc func detToggle() { D.set(!D.bool(forKey: "det.on"), forKey: "det.on") }

    @objc func detToggleApp(_ s: NSMenuItem) {
        guard let k = s.representedObject as? String else { return }
        var apps = D.stringArray(forKey: "det.apps") ?? []
        if apps.contains(k) { apps.removeAll { $0 == k } } else { apps.append(k) }
        D.set(apps, forKey: "det.apps")
    }

    @objc func detPickTime(_ s: NSMenuItem) {
        guard let kv = s.representedObject as? [String], kv.count == 2, let v = Int(kv[1]) else { return }
        D.set(v, forKey: kv[0])
    }

    // ───────────────────────── estado del sprint ─────────────────────────
    func poll() {
        guard !polling else { return }
        polling = true
        var req = URLRequest(url: STATE_URL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        session.dataTask(with: req) { [weak self] data, _, _ in
            let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                guard let self else { return }
                self.polling = false
                self.sprint = j.map(Sprint.init) ?? Sprint()
                self.render()
            }
        }.resume()
    }

    /// Título de la barra: lo que llevas (o lo que falta, si lo eliges) · descanso · reposo.
    func render() {
        guard let b = item?.button else { return }
        let s = sprint, now = nowMs()
        var symbol = HubIcon.name, title = ""     // el símbolo del Hub (como el del Dock)
        if !s.online {
            symbol = HubIcon.name
        } else if let r = s.run {
            let el = (now - num(r["start"])) / 1000, target = num(r["target"]), left = target - el
            if target > 0 && left <= 0 { symbol = "flag.checkered" }
            title = target > 0 && D.bool(forKey: "showRemaining") ? (left < 0 ? "+" : "") + clock(left) : clock(el)
            chimeOnce("r" + str(r["id"]), crossedAt: num(r["start"]) + target * 1000, when: target > 0 && left <= 0)
        } else if detector.prompting && !s.pend && s.close?["err"] == nil {
            symbol = "play.circle"                   // editas sin timer: el reloj pide iniciar
            title = "¿Iniciar?"
        } else if let k = s.brk {
            let left = num(k["secs"]) - (now - num(k["start"])) / 1000
            symbol = "cup.and.saucer"
            title = left > 0 ? clock(left) : "Listo"
            chimeOnce("b" + String(num(k["start"])), crossedAt: num(k["start"]) + num(k["secs"]) * 1000, when: left <= 0)
        } else if s.pend || (s.close?["err"] != nil) {
            symbol = "exclamationmark.triangle"
        } else if !s.queued.isEmpty {
            symbol = "icloud.and.arrow.up"           // guardado en el Mac, esperando internet
            title = "\(s.queued.count)"
        }
        if let f = flash { if f.until > Date() { symbol = f.symbol; if !f.text.isEmpty { title = f.text } } else { flash = nil } }
        let img = symbol == HubIcon.name ? HubIcon.image
            : NSImage(systemSymbolName: symbol, accessibilityDescription: "Sprint de enfoque")
        img?.isTemplate = true
        b.image = img
        symbolNow = symbol
        b.title = title.isEmpty ? "" : " " + title
        b.appearsDisabled = !s.online
        liveItem?.title = liveLine()
    }

    /// Aviso sonoro al llegar a la meta o al acabar el descanso (Sonidos → Meta), solo si acaba
    /// de pasar (no al abrir la app tarde). Suena aquí aunque la ventana esté visible: en modo
    /// mini la página ya no pone su tono.
    func chimeOnce(_ key: String, crossedAt ms: Double, when hit: Bool) {
        guard hit, chimed != key else { return }
        chimed = key
        if nowMs() - ms < 15_000 { Sounds.play("goal") }
    }

    func liveLine() -> String {
        let s = sprint, now = nowMs()
        if let r = s.run {
            let el = (now - num(r["start"])) / 1000, target = num(r["target"])
            if target <= 0 { return "Llevas " + clock(el) }
            let left = target - el
            return left > 0 ? "Llevas \(clock(el)) · faltan \(clock(left))" : "Llevas \(clock(el)) · +\(clock(left)) de tiempo extra"
        }
        if let k = s.brk {
            let left = num(k["secs"]) - (now - num(k["start"])) / 1000
            return left > 0 ? "Faltan " + clock(left) : "Descanso terminado"
        }
        return ""
    }

    // ───────────────────────── menú ─────────────────────────
    func menuNeedsUpdate(_ menu: NSMenu) {
        if let k = menu.identifier?.rawValue, PICKS[k] != nil { fillPick(menu, k); return }
        poll()
        // la página oculta no se pone al día sola: que lea el server (si cambió algo, manda "state")
        web.callAsyncJavaScript("if (window.SprintCmd) window.SprintCmd('sync')", arguments: [:], in: nil, in: .page)
        menu.removeAllItems()
        liveItem = nil; pickItems = [:]; tipoToggleItem = nil
        let s = sprint
        func info(_ t: String, bold: Bool = false) {
            let i = NSMenuItem(title: t, action: nil, keyEquivalent: "")
            i.isEnabled = false
            if bold {
                i.attributedTitle = NSAttributedString(string: t, attributes: [
                    .font: NSFont.menuFont(ofSize: 0).withWeight(.semibold), .foregroundColor: NSColor.labelColor])
            }
            menu.addItem(i)
        }
        let hk = HotKey.load()
        func act(_ t: String, _ sel: Selector, _ cmd: String? = nil, key: String = "") {
            let i = NSMenuItem(title: t, action: sel, keyEquivalent: key)
            i.target = self
            i.representedObject = cmd
            // muestra el atajo global junto a la acción que dispara
            if let hk, cmd == "finish" || cmd == "start" || cmd == "discard" {
                i.keyEquivalent = hk.char.lowercased()
                i.keyEquivalentModifierMask = cmd == "discard" ? hk.mods.union(.shift) : hk.mods
            }
            menu.addItem(i)
        }
        // cerrar la etapa elegida sin bloque en marcha (por si al terminar no elegiste «…y cerrar la etapa»):
        // la página lo ofrece (pick["fin"]) solo si la etapa existe en Notion y no hay otro cierre en espera
        func finStage() {
            var fin = str(pick["fin"])
            guard !fin.isEmpty, s.close == nil else { return }
            if fin.count > 48 { fin = String(fin.prefix(47)) + "…" }
            act("Finalizar la etapa «\(fin)»", #selector(command(_:)), "close-etapa")
        }
        func live() {
            let i = NSMenuItem(title: liveLine(), action: nil, keyEquivalent: "")
            i.isEnabled = false
            menu.addItem(i)
            liveItem = i
        }

        if s.online && s.run == nil && detector.prompting {
            act("\(detLabel) sin timer — Iniciar", #selector(detStart))
            act("Ahora no", #selector(detMute))
            menu.addItem(.separator())
        }

        if !s.online {
            info("Hub local sin conexión", bold: true)
            info(BASE.replacingOccurrences(of: "http://", with: "") + " · reintentando…")
        } else if let r = s.run {
            let etapa = str(r["etapa"]), escena = str(r["escenaNm"])
            info(r["db"] is String ? [etapa, escena].filter { !$0.isEmpty }.joined(separator: " · ")
                                   : "Sin etapa en Notion (no se registrará)", bold: true)
            var sub = [str(r["tipo"]), str(r["wed"]), "desde " + hhmm(num(r["start"]))].filter { !$0.isEmpty }
            if num(r["target"]) > 0 { sub.append("meta \(Int(num(r["target"]) / 60)) min") }
            info(sub.joined(separator: " · "))
            live()
            menu.addItem(.separator())
            act("Terminar", #selector(command(_:)), "finish")
            if r["db"] is String {
                if r["escena"] is String { act("Terminar y cerrar «\(escena)»", #selector(command(_:)), "finish-escena") }
                if r["stageId"] is String { act("Terminar y cerrar la etapa «\(etapa)»", #selector(command(_:)), "finish-etapa") }
            }
            act("Descartar sin registrar", #selector(command(_:)), "discard")
        } else if let k = s.brk {
            info(k["long"] as? Bool == true ? "Descanso largo" : "Descanso", bold: true)
            live()
            pickers(menu, ["etapa", "escena", "tipo"])      // el esquema no se cambia en el descanso (como en la ventana)
            menu.addItem(.separator())
            act("Empezar bloque \(s.cycle)" + (dest.isEmpty ? "" : " · " + dest), #selector(command(_:)), "start")
            act("Terminar ciclo", #selector(command(_:)), "endcycle")
            finStage()
        } else {
            info("Sprint de enfoque", bold: true)
            // el destino y el esquema se ven en sus submenús; si la página aún no los mandó, en texto
            let cm = can("modo")
            if !can("etapa") { info((dest.isEmpty ? "Sin etapa elegida" : dest) + (cm ? "" : " · " + (MODES[s.mode] ?? s.mode))) }
            pickers(menu, ["etapa", "escena", "tipo", "modo"])
            menu.addItem(.separator())
            act(s.cycle > 1 ? "Empezar bloque \(s.cycle)" : "Iniciar sprint", #selector(command(_:)), "start")
            finStage()
        }

        // avisos: cierre en Notion con margen para deshacer · registro pendiente · último resultado
        if s.online {
            var extra: [() -> Void] = []
            if let c = s.close {
                let label = str(c["label"])
                if c["err"] != nil {
                    extra.append { info("⚠︎ No se pudo cerrar «\(label)» en Notion") }
                    extra.append { act("Abrir la ventana para reintentar", #selector(self.showPanel)) }
                } else if num(c["due"]) > nowMs() {
                    extra.append { act("Deshacer el cierre de «\(label)»", #selector(self.command(_:)), "undo") }
                }
            }
            if s.pend {
                extra.append { info("⚠︎ Hay una sesión sin registrar") }
                extra.append { act("Abrir la ventana para reintentar", #selector(self.showPanel)) }
            }
            // cola sin internet: qué espera y cuándo se subió lo último
            if !s.queued.isEmpty {
                let perm = s.queued.filter { $0["perm"] as? Bool == true }
                extra.append { info("Guardado en el Mac: " + self.queuedText()) }
                extra.append { info("Se sube solo a Notion al volver internet") }
                if let p = perm.first {
                    let e = str(p["err"])
                    extra.append { info("⚠︎ Notion rechazó \(perm.count == 1 ? "uno" : "\(perm.count)"): "
                                        + (e.count > 50 ? String(e.prefix(49)) + "…" : e)) }
                }
                extra.append { act("Subir ahora", #selector(self.flushNow)) }
            } else if s.sentAt > 0 && nowMs() - s.sentAt < 12 * 3600 * 1000 {
                extra.append { info("✓ Subido a Notion a las \(hhmm(s.sentAt)) (\(s.sentN) \(s.sentN == 1 ? "envío guardado" : "envíos guardados") sin internet)") }
            }
            if s.run == nil && !note.isEmpty && s.close == nil {
                extra.append { info(self.note.count > 70 ? String(self.note.prefix(69)) + "…" : self.note) }
            }
            if !extra.isEmpty { menu.addItem(.separator()); extra.forEach { $0() } }
        }

        menu.addItem(.separator())
        act(panel.isVisible ? "Ocultar ventana flotante" : "Mostrar ventana flotante", #selector(togglePanel))
        if let hk, !hk.mods.contains(.command), let w = menu.items.last {
            w.keyEquivalent = hk.char.lowercased(); w.keyEquivalentModifierMask = hk.mods.union(.command)
        }
        act("Abrir dashboard", #selector(openDashboard))
        menu.addItem(.separator())

        let opts = NSMenu()
        for (tag, t) in [(0, "Siempre encima"), (1, "En el escritorio, detrás de las ventanas")] {
            let i = NSMenuItem(title: t, action: #selector(setFloating(_:)), keyEquivalent: "")
            i.target = self; i.tag = tag
            i.state = D.bool(forKey: "onDesktop") == (tag == 1) ? .on : .off
            opts.addItem(i)
        }
        opts.addItem(.separator())
        let keys = NSMenu()
        for p in HotKey.presets {
            let i = NSMenuItem(title: p.menuTitle, action: #selector(pickHotKey(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = p.char; i.state = hk == p ? .on : .off
            keys.addItem(i)
        }
        if let hk, !HotKey.presets.contains(hk) {
            let i = NSMenuItem(title: hk.menuTitle, action: nil, keyEquivalent: "")
            i.state = .on; keys.addItem(i)
        }
        let rec = NSMenuItem(title: "Grabar otro…", action: #selector(recordHotKey), keyEquivalent: "")
        rec.target = self; keys.addItem(rec)
        keys.addItem(.separator())
        let off = NSMenuItem(title: "Sin atajo", action: #selector(pickHotKey(_:)), keyEquivalent: "")
        off.target = self; off.state = hk == nil ? .on : .off; keys.addItem(off)
        let k = NSMenuItem(title: "Atajo de teclado", action: nil, keyEquivalent: "")
        k.submenu = keys
        opts.addItem(k)
        let snd = NSMenuItem(title: "Sonidos", action: nil, keyEquivalent: "")
        snd.submenu = soundsMenu()
        opts.addItem(snd)
        let det = NSMenuItem(title: "Detector", action: nil, keyEquivalent: "")
        det.submenu = detectorMenu()
        opts.addItem(det)
        opts.addItem(.separator())
        let rem = NSMenuItem(title: "En la barra, contar lo que falta", action: #selector(toggleRemaining), keyEquivalent: "")
        rem.target = self; rem.state = D.bool(forKey: "showRemaining") ? .on : .off
        opts.addItem(rem)
        let login = NSMenuItem(title: "Abrir al iniciar sesión", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self; login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        opts.addItem(login)
        let o = NSMenuItem(title: "Opciones", action: nil, keyEquivalent: "")
        o.submenu = opts
        menu.addItem(o)
        let q = NSMenuItem(title: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(q)
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu.identifier == nil else { return }      // al cerrar un submenú Etapa/Escena el principal sigue abierto
        liveItem = nil; pickItems = [:]; tipoToggleItem = nil
    }

    // ───────────────────────── Etapa ▸ / Escena ▸ / Tipo ▸ / Esquema ▸ ─────────────────────────
    /// Las listas vienen de la propia página (las mismas que ve la ventana, con sus grupos
    /// En curso / Por hacer…) y elegir una opción es tocar esa lista o ese botón: se guarda y
    /// se sincroniza con el dashboard. Como en la ventana, con un bloque en marcha no se cambian
    /// (con etapa y escena se registra la sesión en Notion) y el esquema solo en reposo.
    /// Elegir una opción no cierra el menú (filas StayRow): se pueden cambiar varias cosas seguidas
    /// y el menú se cierra al hacer clic fuera o con Esc.
    typealias Opt = (v: String, t: String, g: String)
    /// tipo → (lista, "¿se puede?" que manda la página, título)
    let PICKS: [String: (list: String, flag: String, title: String)] = [
        "etapa": ("etapas", "pick", "Etapa"), "escena": ("escenas", "pick", "Escena"),
        "tipo": ("tipos", "pick", "Tipo"), "modo": ("modos", "pickModo", "Esquema")]
    func opts(_ k: String) -> [Opt] {
        (pick[PICKS[k]?.list ?? ""] as? [[String: Any]] ?? []).map { (str($0["v"]), str($0["t"]), str($0["g"])) }
    }
    func can(_ k: String) -> Bool {
        guard let p = PICKS[k], sprint.run == nil, pick[p.flag] as? Bool == true, !opts(k).isEmpty else { return false }
        return k != "modo" || sprint.brk == nil
    }

    func pickTitle(_ k: String) -> String {
        let cur = str(pick[k])
        var t = cur.isEmpty && k == "escena" ? "ninguna" : opts(k).first(where: { $0.v == cur })?.t ?? "—"
        if t.count > 48 { t = String(t.prefix(47)) + "…" }
        return (PICKS[k]?.title ?? k) + ": " + t
    }

    func pickers(_ menu: NSMenu, _ kinds: [String]) {
        for k in kinds where can(k) && (k == "modo" || can("etapa")) {
            let i = NSMenuItem(title: pickTitle(k), action: nil, keyEquivalent: "")
            let sub = NSMenu(); sub.identifier = NSUserInterfaceItemIdentifier(k)
            sub.delegate = self; sub.autoenablesItems = false
            i.submenu = sub
            menu.addItem(i)
            pickItems[k] = i
            // Tipo ▸ lleva a su lado el alternador con su atajo global (⌃⌥B)
            if k == "tipo", let hk = HotKey.load() {
                let t = NSMenuItem(title: tipoToggleTitle(), action: #selector(toggleTipo), keyEquivalent: hk.tipoKey.char.lowercased())
                t.target = self; t.keyEquivalentModifierMask = hk.mods
                menu.addItem(t)
                tipoToggleItem = t
            }
        }
    }

    /// Rellena el submenú al abrirlo (con lo último que mandó la página): grupos con su
    /// encabezado y la opción actual con ✓.
    func fillPick(_ m: NSMenu, _ k: String) {
        m.removeAllItems()
        let cur = str(pick[k])
        var group: String? = nil
        for o in opts(k) {
            if o.g != group {
                if group != nil || !m.items.isEmpty { m.addItem(.separator()) }
                group = o.g
                if !o.g.isEmpty {
                    let h = NSMenuItem(title: o.g, action: nil, keyEquivalent: "")
                    h.isEnabled = false; h.view = StayRow(o.g, header: true)
                    m.addItem(h)
                }
            }
            // fila con vista propia: elegirla no cierra el menú (se cierra al hacer clic fuera)
            let i = NSMenuItem(title: o.t, action: #selector(command(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = "\(k):\(o.v)"
            i.view = StayRow(o.t)
            m.addItem(i)
        }
        markPick(m, k)
    }

    /// Pone el ✓ del submenú abierto en la opción actual (tras elegir, o cuando la página
    /// manda su estado) sin rehacer las filas.
    func markPick(_ m: NSMenu, _ k: String, _ v: String? = nil) {
        let cur = "\(k):" + (v ?? str(pick[k]))
        for i in m.items where i.action != nil {
            let on = i.representedObject as? String == cur
            i.state = on ? .on : .off
            (i.view as? StayRow)?.on = on
        }
    }

    /// Título del alternador de tipo: «Cambiar a «<el siguiente>»».
    func tipoToggleTitle() -> String {
        let o = opts("tipo"), cur = str(pick["tipo"])
        let next = o.isEmpty ? "el otro tipo" : o[((o.firstIndex(where: { $0.v == cur }) ?? -1) + 1) % o.count].t
        return "Cambiar a «\(next)»"
    }

    @objc func toggleRemaining() { D.set(!D.bool(forKey: "showRemaining"), forKey: "showRemaining"); render() }

    @objc func toggleLogin() {
        let s = SMAppService.mainApp
        if s.status == .enabled { try? s.unregister() } else { try? s.register() }
    }

    /// Acciones del sprint: las ejecuta la propia página (aunque la ventana esté oculta),
    /// que primero se pone al día con el server.
    @objc func command(_ sender: NSMenuItem) {
        guard let cmd = sender.representedObject as? String else { return }
        // elegir en Etapa ▸ / Escena ▸ / …: el menú sigue abierto, así que el ✓ se mueve ya
        // (y vuelve a su sitio si la página no lo acepta)
        let k = String(cmd.prefix(while: { $0 != ":" })), m = sender.menu
        let isPick = PICKS[k] != nil && cmd.contains(":")
        if isPick, let m { markPick(m, k, String(cmd.dropFirst(k.count + 1))) }
        send(cmd) { [weak self] r in
            if r != "ok" {
                Sounds.play("error")     // la página no estaba lista o el estado ya cambió
                if isPick, let m { self?.markPick(m, k) }
            }
            self?.poll()
        }
    }

    func send(_ cmd: String, done: @escaping (String) -> Void) {
        web.callAsyncJavaScript("return window.SprintCmd ? await window.SprintCmd(c) : 'not-ready'",
                                arguments: ["c": cmd], in: nil, in: .page) { [weak self] res in
            var r = "error"
            if case .success(let v) = res { r = v as? String ?? "error" }
            if r == "ok" || r.hasPrefix("ok:") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.poll() }
            }
            done(r)
        }
    }

    // ───────────────────────── atajos globales ─────────────────────────
    /// Carbon RegisterEventHotKey: global y sin permiso de Accesibilidad.
    /// id 1 = alternar, 2 = descartar (+⇧), 3 = mostrar/ocultar la ventana (+⌘), 4 = Edición ↔ Gestión (letra B).
    func installHotKeyHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, ev, ctx in
            var id = EventHotKeyID()
            GetEventParameter(ev, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let me = Unmanaged<App>.fromOpaque(ctx!).takeUnretainedValue()
            DispatchQueue.main.async { me.hotKey(Int(id.id)) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    @discardableResult
    func registerHotKeys() -> Bool {
        hotRefs.forEach { UnregisterEventHotKey($0) }
        hotRefs = []
        guard let hk = HotKey.load() else { return true }
        var ok = true
        var keys: [(Int, Int, UInt32)] = [(1, hk.code, 0), (2, hk.code, UInt32(shiftKey)), (4, hk.tipoKey.code, 0)]
        if !hk.mods.contains(.command) { keys.append((3, hk.code, UInt32(cmdKey))) }      // atajos viejos con ⌘: sin ventana
        for (n, code, extra) in keys {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x53505254), id: UInt32(n))     // 'SPRT'
            let st = RegisterEventHotKey(UInt32(code), hk.carbonMods | extra, id,
                                         GetApplicationEventTarget(), 0, &ref)
            if HUB_LOG { NSLog("SprintFlotante registra atajo id %d tecla %d → %d", n, code, Int(st)) }
            if st == noErr, let ref { hotRefs.append(ref) } else { ok = false }
        }
        return ok
    }

    /// Alternar: intenta terminar (registra en Notion); si no hay bloque en marcha, empieza uno
    /// (también desde el descanso). La página se pone al día con el server antes de cada orden.
    func hotKey(_ id: Int) {
        if HUB_LOG { NSLog("SprintFlotante hotkey %d", id) }
        if id == 3 { togglePanel(); return }      // sin activar la app: Final Cut sigue al frente
        if id == 4 { toggleTipo(); return }
        run(id == 2 ? "discard" : "toggle")
    }

    /// Orden con aviso (destello + sonido). "toggle" termina si corre y, si no, empieza; "start"
    /// solo empieza y "finish" solo termina (pitido si no toca). tries > 0: reintenta cada 0,5 s
    /// mientras la página no esté lista (app recién abierta por una URL).
    func run(_ c: String, tries: Int = 0) {
        let retry: (String) -> Bool = { [weak self] r in
            guard tries > 0, ["not-ready", "error", "busy"].contains(r) else { return false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.run(c, tries: tries - 1) }
            return true
        }
        if c == "discard" {
            send("discard") { [weak self] r in
                if !retry(r) { self?.feedback(r == "ok" ? "xmark.circle" : nil, sound: "discard") } }
            return
        }
        let start = { [weak self] in
            self?.send("start") { r in
                if !retry(r) { self?.feedback(r == "ok" ? "play.circle" : nil, sound: "start") } }
        }
        if c == "start" { start(); return }
        send("finish") { [weak self] r in
            if retry(r) { return }
            if r == "ok" { self?.feedback("checkmark.circle", sound: "finish"); return }
            if c == "toggle" && r == "no-run" { start(); return }
            self?.feedback(nil)
        }
    }

    /// Destello breve del reloj (otro icono 1,5 s) + el sonido de la acción (Opciones → Sonidos);
    /// nil = no se pudo (sonido "No se pudo").
    func feedback(_ symbol: String?, sound: String = "") {
        if HUB_LOG { NSLog("SprintFlotante feedback %@ sound %@", symbol ?? "fail", Sounds.get(symbol == nil ? "error" : sound)) }
        guard let symbol else { Sounds.play("error"); poll(); return }
        Sounds.play(sound)
        flash = (symbol, Date().addingTimeInterval(1.5), "")
        render()
    }

    /// ⌃⌥B: alterna Edición ↔ Gestión (como elegirlo en Tipo ▸ o en la ventana; la página lo guarda
    /// y lo sincroniza). Con un bloque en marcha no hace nada (ese bloque conserva su tipo): suena
    /// "No se pudo". Aviso discreto: el reloj muestra 2 s el tipo que quedó (con su icono) y suena
    /// el sonido "Cambiar Edición/Gestión": una vez = Edición, dos veces = Gestión.
    @objc func toggleTipo() {
        send("tipo-toggle") { [weak self] r in
            if HUB_LOG { NSLog("SprintFlotante tipo-toggle → %@", r) }
            guard let self, r.hasPrefix("ok:") else { self?.feedback(nil); return }
            let t = String(r.dropFirst(3)), gestion = t != "Edición"
            Sounds.play("tipo")
            if gestion { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { Sounds.play("tipo") } }
            self.flash = (gestion ? "folder" : "scissors", Date().addingTimeInterval(2), t)
            self.render()
        }
    }

    /// Opciones → Sonidos: un submenú por acción con "Ninguno", el aviso del sistema y los
    /// sonidos instalados; al pasar por uno suena, al elegirlo se guarda (y vuelve a sonar).
    func soundsMenu() -> NSMenu {
        let m = NSMenu(), names = Sounds.available
        for a in Sounds.actions {
            let cur = Sounds.get(a.key)
            let sub = NSMenu(); sub.delegate = preview
            let add = { (title: String, v: String) in
                let i = NSMenuItem(title: title + (v == a.def ? "  (de serie)" : ""), action: #selector(self.pickSound(_:)), keyEquivalent: "")
                i.target = self; i.representedObject = [a.key, v]; i.state = cur == v ? .on : .off
                sub.addItem(i)
            }
            add("Ninguno", Sounds.OFF)
            add("Aviso del sistema", Sounds.SYS)
            sub.addItem(.separator())
            names.forEach { add($0, $0) }
            let shown = cur == Sounds.OFF ? "Ninguno" : cur == Sounds.SYS ? "Aviso del sistema" : cur
            let i = NSMenuItem(title: "\(a.title): \(shown)", action: nil, keyEquivalent: "")
            i.submenu = sub
            m.addItem(i)
        }
        m.addItem(.separator())
        let r = NSMenuItem(title: "Restablecer los de serie", action: #selector(resetSounds), keyEquivalent: "")
        r.target = self; m.addItem(r)
        return m
    }

    @objc func pickSound(_ s: NSMenuItem) {
        guard let kv = s.representedObject as? [String], kv.count == 2 else { return }
        Sounds.set(kv[0], kv[1])
        Sounds.play(name: kv[1])
    }

    @objc func resetSounds() { Sounds.actions.forEach { D.removeObject(forKey: "snd." + $0.key) } }

    @objc func pickHotKey(_ s: NSMenuItem) {
        if let c = s.representedObject as? String, let p = HotKey.presets.first(where: { $0.char == c }) {
            p.save()
        } else {
            D.set(true, forKey: "hkOff")
        }
        if !registerHotKeys() { hotKeyTaken() }
    }

    func hotKeyTaken() {
        let a = NSAlert()
        a.messageText = "Ese atajo ya lo usa otra app"
        a.informativeText = "Elige otro en Opciones → Atajo de teclado."
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    /// Graba un atajo nuevo: con ⌃ y/o ⌥, sin ⇧ ni ⌘ (⇧ descarta, ⌘ muestra/oculta la ventana).
    @objc func recordHotKey() {
        let a = NSAlert()
        a.messageText = "Pulsa el nuevo atajo"
        a.informativeText = "Con ⌃ y/o ⌥ y una tecla, sin ⇧ ni ⌘ (con ⇧ descartará el bloque y con ⌘ mostrará u ocultará la ventana).\nEsc cancela."
        a.addButton(withTitle: "Cancelar")
        NSApp.activate(ignoringOtherApps: true)
        hotRefs.forEach { UnregisterEventHotKey($0) }; hotRefs = []       // que no se dispare mientras graba
        var picked: HotKey?
        recorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == UInt16(kVK_Escape) { NSApp.abortModal(); return nil }
            let m = e.modifierFlags.intersection([.control, .option, .command, .shift])
            guard !m.intersection([.control, .option]).isEmpty, m.isDisjoint(with: [.shift, .command]),
                  let ch = e.charactersIgnoringModifiers, !ch.isEmpty else { NSSound.beep(); return nil }
            picked = HotKey(code: Int(e.keyCode), mods: m, char: ch)
            NSApp.stopModal()
            return nil
        }
        a.runModal()
        if let r = recorder { NSEvent.removeMonitor(r); recorder = nil }
        picked?.save()
        if !registerHotKeys() { hotKeyTaken() }
    }

    // ───────────────────────── mensajes de la página ─────────────────────────
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        if let d = m.body as? [String: Any], d["k"] as? String == "height", let h = d["h"] as? NSNumber {
            fitHeight(CGFloat(h.doubleValue)); return
        }
        if let d = m.body as? [String: Any], d["k"] as? String == "state" {
            dest = str(d["dest"]); note = str(d["note"]); pick = d
            for (k, i) in pickItems {                               // menú abierto
                i.title = pickTitle(k)
                if let sub = i.submenu { markPick(sub, k) }
            }
            tipoToggleItem?.title = tipoToggleTitle()
            return
        }
        switch m.body as? String {
        case "dashboard": openDashboard(); hidePanel()
        case "close": hidePanel()
        default: break
        }
    }

    // enlaces externos (p. ej. "Ver" la sesión en Notion) → navegador
    func webView(_ w: WKWebView, createWebViewWith c: WKWebViewConfiguration, for a: WKNavigationAction,
                 windowFeatures f: WKWindowFeatures) -> WKWebView? {
        if let u = a.request.url { NSWorkspace.shared.open(u) }
        return nil
    }

    func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction,
                 decisionHandler h: @escaping (WKNavigationActionPolicy) -> Void) {
        if let u = a.request.url, a.navigationType == .linkActivated, u.host != "localhost" {
            NSWorkspace.shared.open(u); h(.cancel); return
        }
        h(.allow)
    }

    // server.py caído: aviso y reintento cada 5 s
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { offline() }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { offline() }
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
        if w.url?.host == "localhost" { retry?.invalidate(); retry = nil }
        // prueba: HUB_SNAPSHOT=/ruta.png → guarda una captura del contenido 2 s después de cargar
        if let out = ProcessInfo.processInfo.environment["HUB_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                w.takeSnapshot(with: nil) { img, _ in
                    if let t = img?.tiffRepresentation, let r = NSBitmapImageRep(data: t),
                       let png = r.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: out))
                    }
                }
            }
        }
    }

    func offline() {
        web.loadHTMLString("""
        <html><head><meta name="color-scheme" content="dark light"><style>
        body{margin:0;height:100vh;display:grid;place-items:center;background:#050506;color:#f0eee9;
          font:600 13px -apple-system,system-ui;text-align:center;padding:24px;box-sizing:border-box}
        b{display:block;font:700 11px ui-monospace,monospace;letter-spacing:.12em;margin-bottom:8px;color:#d9ed2f}
        span{opacity:.6;font-weight:500}
        @media (prefers-color-scheme:light){ body{background:#f0eee9;color:#1a1b15} b{color:#4f620c} }
        </style></head><body>
        <div><b>SPRINT DE ENFOQUE</b>Sin conexión con el Hub local<br><span>localhost:4599 · reintentando…</span></div>
        </body></html>
        """, baseURL: nil)
        guard retry == nil else { return }
        retry = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.web.load(URLRequest(url: HUB))
        }
    }
}

#if DUMP_MENU
/// Prueba sin tocar la pantalla (solo build de prueba: swiftc -D DUMP_MENU): a los 6 s arma el
/// menú del reloj con sus submenús y lo imprime; HUB_PICK="modo:pomo,etapa:<db>,…" ejecuta cada
/// orden por el mismo camino que el menú (send → SprintCmd) y vuelve a imprimirlo.
extension App {
    func dumpMenu(_ tag: String) {
        let m = item.menu!
        menuNeedsUpdate(m)
        print("== \(tag) · barra: \(symbolNow) «\(item.button?.title ?? "")» · detector: \(detector.phase.rawValue) · ventana: \(panel.isVisible)")
        for i in m.items {
            print(i.isSeparatorItem ? "---" : i.title + (i.submenu != nil ? " ▸" : "")
                  + (i.keyEquivalent.isEmpty ? "" : "   [\(i.keyEquivalentModifierMask.contains(.control) ? "⌃" : "")\(i.keyEquivalentModifierMask.contains(.option) ? "⌥" : "")\(i.keyEquivalentModifierMask.contains(.shift) ? "⇧" : "")\(i.keyEquivalentModifierMask.contains(.command) ? "⌘" : "")\(i.keyEquivalent.uppercased())]"))
            if let sub = i.submenu, let k = sub.identifier?.rawValue {
                fillPick(sub, k)
                for j in sub.items { print("    " + (j.isSeparatorItem ? "---" : (j.state == .on ? "✓ " : "  ") + j.title)) }
            }
        }
        if tag == "final" {
            print("Opciones → Detector:")
            for i in detectorMenu().items where !i.isSeparatorItem { print("    " + (i.state == .on ? "✓ " : "  ") + i.title) }
        }
        fflush(stdout)
    }
    func dumpMenuTest() {
        panel.alphaValue = 0              // la prueba no enseña la ventana en pantalla
        var picks = (ProcessInfo.processInfo.environment["HUB_PICK"] ?? "").split(separator: ",").map(String.init)
        func next() {
            dumpMenu(picks.isEmpty ? "final" : "antes de \(picks[0])")
            guard !picks.isEmpty else { NSApp.terminate(nil); return }
            let c = picks.removeFirst()
            if c.hasPrefix("wait:") {         // espera N s (p. ej. a que la cola se suba sola)
                DispatchQueue.main.asyncAfter(deadline: .now() + (Double(c.dropFirst(5)) ?? 1)) { next() }
                return
            }
            // detector: det-front:<bundle> simula esa app al frente · det-quit:<bundle> que se cierra ·
            // det-idle:<s> segundos sin teclado ni ratón · det-mute = «Ahora no» (por las notificaciones reales)
            if c.hasPrefix("det-front:") || c.hasPrefix("det-quit:") {
                let b = String(c.drop(while: { $0 != ":" }).dropFirst())
                if let a = NSRunningApplication.runningApplications(withBundleIdentifier: b).first {
                    let n: NSNotification.Name = c.hasPrefix("det-front:") ? NSWorkspace.didActivateApplicationNotification
                                                                            : NSWorkspace.didTerminateApplicationNotification
                    NSWorkspace.shared.notificationCenter.post(name: n, object: NSWorkspace.shared,
                                                               userInfo: [NSWorkspace.applicationUserInfoKey: a])
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { next() }
                return
            }
            if c.hasPrefix("det-idle:") { detFakeIdle = Double(c.dropFirst(9)); next(); return }
            if c == "det-mute" { detMute(); next(); return }
            if c == "red" {                   // como si NWPathMonitor viera volver la red
                netUp = false; flushOutbox()
                print("red → POST /api/outbox/flush"); fflush(stdout)
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { next() }
                return
            }
            if c.hasPrefix("hotkey:") {      // como si llegara el atajo global (mismo camino que Carbon → hotKey(id))
                hotKey(Int(c.dropFirst(7)) ?? 0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    print("atajo \(c) → título de la barra: «\(self.item.button?.title ?? "")»"); fflush(stdout)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { next() }
                }
                return
            }
            send(c) { r in
                print("orden \(c) → \(r)"); fflush(stdout)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { next() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { next() }
    }
}
#endif

extension NSFont {
    func withWeight(_ w: NSFont.Weight) -> NSFont {
        NSFont.systemFont(ofSize: pointSize, weight: w)
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
