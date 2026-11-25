// Sprint flotante — el Sprint de enfoque del Hub de Edición integrado en el Mac:
//  · un reloj en la barra de menús (tiempo que llevas / descanso) que abre un popover con pestañas
//    (Sprint · Ventana y barra · Detector · Sonidos · Atajos): terminar, cerrar escena/etapa,
//    descartar o empezar el siguiente bloque, finalizar la escena o la etapa elegidas sin bloque en
//    marcha (si al terminar no la cerraste; con fecha de fin = su última sesión), y elegir el
//    proyecto, la etapa, la escena, el tipo y el esquema del próximo bloque, como en la ventana
//    (Proyecto filtra Etapa: solo salen las etapas de ese proyecto). Elegir no lo cierra; se cierra con clic fuera o Esc;
//  · la tarjeta del sprint en una ventanita propia que se arrastra desde cualquier zona sin
//    controles, siempre encima (también sobre Premiere/Resolve en pantalla completa) o fijada
//    al escritorio como un widget.
//
// No reimplementa el sprint: la ventana carga http://localhost:4599/?mini=1 (el mismo
// index.html en modo mini) y las acciones del popover llaman a window.SprintCmd en esa página
// (aunque esté oculta). El reloj de la barra lee /api/sprint-state de server.py cada segundo,
// así refleja también lo que hagas en el dashboard.
//
// Cerrar la ventana solo la oculta: la app sigue en la barra de menús (⌘Q o "Salir" la cierra).
// Se abre al iniciar sesión (pestaña Ventana y barra). Compilar e instalar: ./build.sh
//
// Atajos globales (funcionan con cualquier app al frente, sin permiso de Accesibilidad:
// Carbon RegisterEventHotKey): ⌃⌥N inicia el sprint o, si corre, lo termina y registra;
// ⌃⌥⇧N lo descarta sin registrar; ⌃⌥⌘N muestra/oculta la ventana; ⌃⌥B alterna el tipo de
// sesión Edición ↔ Gestión (no con un bloque en marcha). Se cambian en
// la pestaña Atajos del reloj (la tecla base; ⇧ y ⌘ se añaden solos y la B sigue a los mismos ⌃⌥).
// Sonidos de cada acción (iniciar, terminar, descartar, meta, error): pestaña Sonidos.
// Siri / Atajos: hubsprint://start empieza un bloque (esquema y etapa ya elegidos),
// hubsprint://finish lo termina y registra, hubsprint://toggle alterna (como ⌃⌥N).
// Sin internet: server.py guarda cada sesión/cierre en su cola del Mac (.outbox.json) y la sube
// sola. Esta app solo la muestra (icono ☁︎↑ + número en la barra, en reposo; detalle en el popover)
// y le avisa en cuanto vuelve la red (NWPathMonitor) o despierta el Mac → POST /api/outbox/flush.
// Detector de Final Cut: si editas (Final Cut o Premiere al frente, con teclado o ratón en uso)
// sin bloque en marcha, el reloj pide iniciar y, si sigues, aparece la ventana. Pestaña Detector.
// Prueba contra otro server: HUB_BASE=http://localhost:4611 …/SprintFlotante

import Cocoa
import SwiftUI
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

/// Sonido de cada acción, elegible en la pestaña Sonidos (UserDefaults "snd.<acción>").
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
    /// Los instalados al abrir la app (la pestaña Sonidos no vuelve a leer las carpetas cada segundo).
    static let installed = available
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

// ───────────────────────── popover de la barra de menús ─────────────────────────
// Al hacer clic en el reloj se abre un popover (no un NSMenu): el logo del Hub, una barra de
// pestañas con iconos y, debajo, secciones con título y tarjetas. Elegir algo no lo cierra (se
// pueden cambiar varias cosas seguidas); se cierra al hacer clic fuera, con Esc o con «Abrir
// dashboard». Los textos y las acciones salen de App (hero / popActions / pickKinds / notices),
// así la prueba DUMP_MENU imprime lo mismo que se ve.

extension Color {
    init(hex: UInt32, _ a: Double = 1) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: a)
    }
}

/// Colores del Hub (index.html): crema sobre el material oscuro del popover y el amarillo «sun»
/// como único acento (pestaña activa, botón principal, opción elegida, progreso del bloque).
enum Pal {
    static let txt = Color(hex: 0xf0eee9), mut = Color(hex: 0xa6a6ae), dim = Color(hex: 0x878791)
    static let sun = Color(hex: 0xd9ed2f), sunHi = Color(hex: 0xe5f55e), ink = Color(hex: 0x15160a)
    static let naranja = Color(hex: 0xde6b45), violeta = Color(hex: 0x9a8fe3)
    static let card = Color.white.opacity(0.05), card2 = Color.white.opacity(0.08)
    static let card3 = Color.white.opacity(0.13), hair = Color.white.opacity(0.08)
}

final class PopModel: ObservableObject {
    @Published var tick = 0                 // App lo sube cada segundo (y tras cada cambio) con el popover abierto
    @Published var tab = PopTab.sprint
    @Published var sub: String? = nil       // lista de Proyecto / Etapa / Escena abierta al lado del popover
    weak var app: App?
    func bump() { tick &+= 1 }
}

enum PopTab: CaseIterable {
    case sprint, ventana, detector, sonidos, atajos
    var icon: String {
        switch self {
        case .sprint: return "timer"
        case .ventana: return "macwindow"
        case .detector: return "scissors"
        case .sonidos: return "speaker.wave.2"
        case .atajos: return "command"
        }
    }
    var title: String {
        switch self {
        case .sprint: return "Sprint"
        case .ventana: return "Ventana y barra"
        case .detector: return "Detector"
        case .sonidos: return "Sonidos"
        case .atajos: return "Atajos"
        }
    }
}

/// Lo que muestra la tarjeta principal de la pestaña Sprint.
struct Hero {
    var state = "", clock = "", title = "", detail = ""
    var progress: Double? = nil
    var tint = Pal.sun
    var over = false, idle = false
}

/// Un botón de acción del popover. cmd es la orden de SprintCmd o una propia (det-start, det-mute, show, flush).
struct PopAction {
    enum Kind { case primary, normal, quiet }
    let title: String, cmd: String
    var icon = "", key = "", kind = Kind.normal
}

struct Notice {
    let text: String
    var warn = false
    var action: PopAction? = nil
}

/// El logo de arriba: el mismo dibujo del icono de la barra (HubIcon), a 34 pt y nítido.
enum HubLogo {
    static let image: NSImage = {
        let img = NSImage(size: NSSize(width: 34, height: 34), flipped: false) { r in
            HubIcon.image.draw(in: r); return true
        }
        img.isTemplate = true
        return img
    }()
}

struct SprintPopover: View {
    @ObservedObject var m: PopModel
    let app: App
    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: HubLogo.image).renderingMode(.template).resizable()
                .frame(width: 24, height: 24).foregroundColor(Pal.txt)
                .accessibilityLabel("Sprint de enfoque")
            TabBar(m: m)
            Group {
                switch m.tab {
                case .sprint: SprintTab(m: m, app: app)
                case .ventana: VentanaTab(m: m, app: app)
                case .detector: DetectorTab(m: m, app: app)
                case .sonidos: SonidosTab(m: m, app: app)
                case .atajos: AtajosTab(m: m, app: app)
                }
            }
            HStack(spacing: 10) {
                FooterButton(title: "Abrir dashboard", icon: "square.grid.2x2") { app.openDashboard(); app.closePopover() }
                FooterButton(title: "Salir", icon: "power") { NSApp.terminate(nil) }
            }
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 12)
        .frame(width: 320)
        .foregroundColor(Pal.txt)
        .environment(\.colorScheme, .dark)
    }
}

struct TabBar: View {
    @ObservedObject var m: PopModel
    var body: some View {
        HStack(spacing: 2) {
            ForEach(PopTab.allCases, id: \.self) { t in
                TabButton(tab: t, on: m.tab == t) { m.app?.closeSub(); m.tab = t }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Pal.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Pal.hair, lineWidth: 1))
    }
}

struct TabButton: View {
    let tab: PopTab, on: Bool, action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: tab.icon).font(.system(size: 13, weight: .regular))
                .foregroundColor(on ? Pal.sun : hover ? Pal.txt : Pal.mut)
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(on ? Pal.sun.opacity(0.16) : hover ? Pal.card2 : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hover = $0 }
        .help(tab.title).accessibilityLabel(tab.title)
    }
}

struct PopSection<C: View>: View {
    let title: String
    let content: C
    init(_ title: String, @ViewBuilder _ c: () -> C) { self.title = title; content = c() }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.7)
                .foregroundColor(Pal.dim).padding(.leading, 2)
            Card { content }
        }
    }
}

struct Card<C: View>: View {
    let content: C
    init(@ViewBuilder _ c: () -> C) { content = c() }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) { content }
            .padding(.horizontal, 10).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Pal.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Pal.hair, lineWidth: 1))
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Pal.hair).frame(height: 1) }
}

struct KeyCap: View {
    let k: String
    var body: some View {
        Text(k).font(.system(size: 11, weight: .medium)).foregroundColor(Pal.mut)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(Pal.hair, lineWidth: 1))
    }
}

struct Chip: View {
    let title: String
    var on = false
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Text(title).lineLimit(1).font(.system(size: 11.5, weight: on ? .semibold : .medium))
                .foregroundColor(on ? Pal.ink : Pal.txt)
                .padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: 23)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(on ? (hover ? Pal.sunHi : Pal.sun) : hover ? Pal.card3 : Pal.card2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hover = $0 }
    }
}

/// Fila de chips del mismo ancho.
struct ChipGrid<C: View>: View {
    let cols: Int
    let content: C
    init(_ cols: Int, @ViewBuilder _ c: () -> C) { self.cols = max(1, cols); content = c() }
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: cols), spacing: 5) { content }
    }
}

struct ActionButton: View {
    let a: PopAction
    let run: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: run) {
            HStack(spacing: 8) {
                if !a.icon.isEmpty {
                    Image(systemName: a.icon).font(.system(size: 12, weight: .semibold)).frame(width: 16)
                }
                Text(a.title).font(.system(size: 12.5, weight: a.kind == .primary ? .semibold : .medium))
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 6)
                if !a.key.isEmpty { Text(a.key).font(.system(size: 11, weight: .medium)).opacity(0.6) }
            }
            .foregroundColor(a.kind == .primary ? Pal.ink : a.kind == .quiet ? (hover ? Pal.naranja : Pal.mut) : Pal.txt)
            .padding(.horizontal, 10).frame(height: a.kind == .primary ? 30 : 25)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(bg))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hover = $0 }
    }
    var bg: Color {
        switch a.kind {
        case .primary: return hover ? Pal.sunHi : Pal.sun
        case .normal: return hover ? Pal.card3 : Pal.card2
        case .quiet: return hover ? Pal.card : Color.clear
        }
    }
}

struct FooterButton: View {
    let title: String, icon: String, action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(hover ? Pal.txt : Pal.mut)
            .frame(maxWidth: .infinity, minHeight: 26)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hover ? Pal.card2 : Pal.card))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Pal.hair, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hover = $0 }
    }
}

/// Interruptor con el acento del Hub (el de serie usa el color de acento del sistema).
struct HubSwitch: ToggleStyle {
    func makeBody(configuration c: Configuration) -> some View {
        HStack(spacing: 10) {
            c.label
            Spacer(minLength: 8)
            ZStack(alignment: c.isOn ? .trailing : .leading) {
                Capsule().fill(c.isOn ? Pal.sun : Pal.card3).frame(width: 30, height: 18)
                Circle().fill(c.isOn ? Pal.ink : Pal.txt).frame(width: 14, height: 14).padding(2)
            }
            .animation(.easeOut(duration: 0.15), value: c.isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture { c.isOn.toggle() }
    }
}

struct ToggleRow: View {
    let title: String
    var sub = "", key = ""
    let get: () -> Bool
    let set: (Bool) -> Void
    var body: some View {
        Toggle(isOn: Binding(get: get, set: set)) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 12.5))
                    if !key.isEmpty { KeyCap(k: key) }
                }
                if !sub.isEmpty {
                    Text(sub).font(.system(size: 11)).foregroundColor(Pal.dim).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(HubSwitch())
    }
}

/// El playhead del Hub recorriendo el bloque: la pista se llena hasta la meta (naranja si te pasas).
struct Playhead: View {
    let p: Double, color: Color
    var body: some View {
        GeometryReader { g in
            let x = CGFloat(max(0, min(1, p))) * g.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Pal.card3).frame(height: 4)
                Capsule().fill(color).frame(width: max(4, x), height: 4)
                PlayheadMark().fill(Pal.txt).frame(width: 10, height: 18).offset(x: min(max(x - 5, -1), g.size.width - 9))
            }
            .frame(height: 18)
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }
}

struct PlayheadMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let cx = r.midX
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + 4))
        p.addLine(to: CGPoint(x: cx + 1, y: r.minY + 7))
        p.addLine(to: CGPoint(x: cx - 1, y: r.minY + 7))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + 4))
        p.closeSubpath()
        p.addRoundedRect(in: CGRect(x: cx - 0.9, y: r.minY + 5, width: 1.8, height: r.height - 5),
                         cornerSize: CGSize(width: 0.9, height: 0.9))
        return p
    }
}

struct HeroCard: View {
    let h: Hero
    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Circle().fill(h.idle ? Pal.dim : h.over ? Pal.naranja : h.tint).frame(width: 6, height: 6)
                        Text(h.state).font(.system(size: 11, weight: .semibold)).foregroundColor(Pal.mut)
                    }
                    Text(h.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(2)
                    if !h.detail.isEmpty {
                        Text(h.detail).font(.system(size: 11)).foregroundColor(Pal.mut).lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                if !h.clock.isEmpty {
                    Text(h.clock).font(.system(size: 28, weight: .semibold).monospacedDigit())
                        .foregroundColor(h.idle ? Pal.dim : h.over ? Pal.naranja : Pal.txt)
                        .lineLimit(1).fixedSize()
                }
            }
            if let p = h.progress { Playhead(p: p, color: h.over ? Pal.naranja : h.tint) }
        }
    }
}

struct SprintTab: View {
    @ObservedObject var m: PopModel
    let app: App
    var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                if app.detPrompting {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "scissors").foregroundColor(Pal.sun)
                            Text("Estás editando en \(app.detLabel) sin timer").font(.system(size: 12.5, weight: .semibold))
                        }
                        HStack(spacing: 6) {
                            Chip(title: "Iniciar sprint", on: true) { app.perform(PopAction(title: "", cmd: "det-start")) }
                            Chip(title: "Ahora no") { app.perform(PopAction(title: "", cmd: "det-mute")) }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Pal.sun.opacity(0.10)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Pal.sun.opacity(0.5), lineWidth: 1))
                }
                HeroCard(h: app.hero())
                let acts = app.popActions()
                if !acts.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(0..<acts.count, id: \.self) { i in ActionButton(a: acts[i]) { app.perform(acts[i]) } }
                    }
                }
                let kinds = app.pickKinds()
                if !kinds.isEmpty {
                    PopSection(app.sprint.brk != nil ? "Siguiente bloque" : "Próximo bloque") {
                        ForEach(0..<kinds.count, id: \.self) { i in
                            if i > 0 { Hairline() }
                            PickerRow(m: m, app: app, k: kinds[i])
                        }
                    }
                }
                let notes = app.notices()
                if !notes.isEmpty {
                    PopSection("Avisos") {
                        ForEach(0..<notes.count, id: \.self) { i in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: notes[i].warn ? "exclamationmark.triangle.fill" : "info.circle")
                                    .font(.system(size: 11)).foregroundColor(notes[i].warn ? Pal.naranja : Pal.mut)
                                    .frame(width: 14)
                                Text(notes[i].text).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
                            }
                            if let a = notes[i].action {
                                ActionButton(a: a) { app.perform(a) }
                            }
                        }
                    }
                }
            }
    }
}

/// Proyecto, Etapa y Escena abren su lista al lado del popover con solo pasar el cursor (como un submenú);
/// Tipo y Esquema se eligen con chips ahí mismo.
struct PickerRow: View {
    @ObservedObject var m: PopModel
    let app: App, k: String
    @State private var hover = false
    @State private var box = AnchorBox()
    var body: some View {
        let title = app.PICKS[k]?.title ?? k
        if k == "tipo" || k == "modo" {
            let o = app.opts(k), cur = app.curPick(k)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title).font(.system(size: 11.5)).foregroundColor(Pal.mut)
                    Spacer()
                    if k == "tipo", let hk = HotKey.load() { KeyCap(k: hk.tipoLabel).help("Cambia el tipo desde cualquier app") }
                }
                ChipGrid(k == "tipo" ? max(1, o.count) : 2) {          // el esquema en 2 columnas: «Pomodoro · 25/5» cabe entero
                    ForEach(0..<o.count, id: \.self) { i in
                        Chip(title: o[i].t, on: o[i].v == cur) { app.choose(k, o[i].v) }
                    }
                }
            }
        } else {
            let open = m.sub == k
            HStack(spacing: 8) {
                Text(title).font(.system(size: 11.5)).foregroundColor(Pal.mut).frame(width: 54, alignment: .leading)
                Text(app.pickLabel(k)).font(.system(size: 12.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .foregroundColor(open ? Pal.sun : Pal.dim)
            }
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(open ? Pal.card3 : hover ? Pal.card2 : Color.clear).padding(-4))
            .background(AnchorView(box: box))
            .contentShape(Rectangle())
            .onHover { inside in hover = inside; app.subHover(k, inside, box.view) }
            .onTapGesture { app.openSub(k, box.view) }
        }
    }
}

/// Para saber dónde está una fila en pantalla (y abrir su lista a esa altura).
final class AnchorBox { weak var view: NSView? }
struct AnchorView: NSViewRepresentable {
    let box: AnchorBox
    func makeNSView(context: Context) -> NSView { let v = NSView(); box.view = v; return v }
    func updateNSView(_ v: NSView, context: Context) { box.view = v }
}

/// La lista de Etapa o Escena en su panel al lado del popover, con sus grupos (En curso / Por
/// hacer…). Elegir no cierra nada: la marca se mueve y se puede seguir eligiendo; se cierra al
/// llevar el cursor a otra parte del popover, con un clic fuera o con Esc.
struct SubList: View {
    @ObservedObject var m: PopModel
    let app: App
    static let width: CGFloat = 270, rowH: CGFloat = 24, headH: CGFloat = 22, pad: CGFloat = 5, maxH: CGFloat = 440
    var body: some View {
        let k = m.sub ?? "", o = app.opts(k), cur = app.curPick(k), rows = app.subRows(k)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<rows.count, id: \.self) { n in
                    if rows[n].i < 0 {
                        Text(rows[n].head).font(.system(size: 10.5, weight: .semibold)).foregroundColor(Pal.dim)
                            .frame(height: SubList.headH, alignment: .bottomLeading).padding(.leading, 8)
                    } else if rows[n].i < o.count {
                        let x = o[rows[n].i]
                        OptionRow(title: x.t, on: x.v == cur) { app.choose(k, x.v) }
                    }
                }
            }
            .padding(SubList.pad)
        }
        .frame(width: SubList.width, height: app.subSize(k).height)
        .foregroundColor(Pal.txt)
        .environment(\.colorScheme, .dark)
        .onHover { app.subPanelHover($0) }
    }
}

struct OptionRow: View {
    let title: String, on: Bool, action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                    .foregroundColor(hover ? Pal.ink : Pal.sun).opacity(on ? 1 : 0).frame(width: 12)
                Text(title).font(.system(size: 12.5, weight: on ? .semibold : .regular)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .foregroundColor(hover ? Pal.ink : Pal.txt)
            .padding(.horizontal, 6).frame(height: SubList.rowH)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(hover ? Pal.sun : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hover = $0 }
    }
}

/// Panel sin bordes de la lista de Etapa / Escena: no toma el foco y acepta el primer clic.
final class SubPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}
final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
}

struct VentanaTab: View {
    @ObservedObject var m: PopModel
    let app: App
    var body: some View {
        let hk = HotKey.load(), desk = D.bool(forKey: "onDesktop")
        VStack(alignment: .leading, spacing: 8) {
            PopSection("Ventana flotante") {
                ToggleRow(title: "Mostrar la ventana",
                          key: hk.map { $0.mods.contains(.command) ? "" : $0.label(cmd: true) } ?? "",
                          get: { app.panel.isVisible },
                          set: { $0 ? app.showPanel() : app.hidePanel(); m.bump() })
                Hairline()
                ChipGrid(2) {
                    Chip(title: "Siempre encima", on: !desk) { app.setFloating(false) }
                    Chip(title: "En el escritorio", on: desk) { app.setFloating(true) }
                }
                Text(desk ? "Queda detrás de las ventanas, como un widget." : "Flota sobre todo, también sobre Final Cut en pantalla completa.")
                    .font(.system(size: 11)).foregroundColor(Pal.dim)
            }
            PopSection("Barra de menús") {
                ToggleRow(title: "Contar lo que falta", sub: "Con meta, el reloj baja hasta cero en vez de subir.",
                          get: { D.bool(forKey: "showRemaining") }, set: { _ in app.toggleRemaining(); m.bump() })
                Hairline()
                ToggleRow(title: "Abrir al iniciar sesión",
                          get: { SMAppService.mainApp.status == .enabled }, set: { _ in app.toggleLogin(); m.bump() })
            }
        }
    }
}

struct DetectorTab: View {
    @ObservedObject var m: PopModel
    let app: App
    var body: some View {
        let apps = D.stringArray(forKey: "det.apps") ?? []
        let label = { (s: Int) in s % 60 == 0 ? "\(s / 60) min" : "\(s) s" }
        VStack(alignment: .leading, spacing: 8) {
            PopSection("Detector") {
                ToggleRow(title: "Avisar si edito sin timer",
                          sub: "Con la app de edición al frente y sin bloque en marcha, el reloj te pide iniciar.",
                          get: { D.bool(forKey: "det.on") }, set: { D.set($0, forKey: "det.on"); m.bump() })
                Hairline()
                ForEach(0..<DET_APPS.count, id: \.self) { i in
                    ToggleRow(title: DET_APPS[i].name, get: { apps.contains(DET_APPS[i].key) },
                              set: { _ in app.detToggleApp(DET_APPS[i].key) })
                }
            }
            PopSection("Tiempos") {
                ForEach(0..<DET_TIMES.count, id: \.self) { i in
                    let t = DET_TIMES[i], cur = Int(D.double(forKey: t.key))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t.title).font(.system(size: 12)).foregroundColor(Pal.mut)
                        ChipGrid(t.opts.count) {
                            ForEach(0..<t.opts.count, id: \.self) { j in
                                Chip(title: label(t.opts[j]), on: t.opts[j] == cur) { app.detPickTime(t.key, t.opts[j]) }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct SonidosTab: View {
    @ObservedObject var m: PopModel
    let app: App
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PopSection("Sonidos") {
                ForEach(0..<Sounds.actions.count, id: \.self) { i in
                    let a = Sounds.actions[i]
                    if i > 0 { Hairline() }
                    HStack(spacing: 8) {
                        Text(a.title).font(.system(size: 12)).foregroundColor(Pal.mut).lineLimit(2)
                        Spacer(minLength: 4)
                        Picker("", selection: Binding(get: { Sounds.get(a.key) }, set: { app.pickSound(a.key, $0) })) {
                            Text("Ninguno").tag(Sounds.OFF)
                            Text("Aviso del sistema").tag(Sounds.SYS)
                            Divider()
                            ForEach(Sounds.installed, id: \.self) { n in
                                Text(n == a.def ? "\(n) (de serie)" : n).tag(n)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).frame(width: 140)
                        Button { Sounds.play(a.key) } label: {
                            Image(systemName: "play.fill").font(.system(size: 10)).foregroundColor(Pal.mut)
                                .frame(width: 24, height: 22)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Pal.card2))
                        }
                        .buttonStyle(.plain).help("Escuchar")
                    }
                }
            }
            ActionButton(a: PopAction(title: "Restablecer los de serie", cmd: "", icon: "arrow.counterclockwise")) {
                app.resetSounds(); m.bump()
            }
        }
    }
}

struct AtajosTab: View {
    @ObservedObject var m: PopModel
    let app: App
    var body: some View {
        let hk = HotKey.load()
        VStack(alignment: .leading, spacing: 8) {
            PopSection("Atajo de teclado") {
                ChipGrid(3) {
                    ForEach(0..<HotKey.presets.count, id: \.self) { i in
                        Chip(title: HotKey.presets[i].label(), on: hk == HotKey.presets[i]) { app.setHotKey(HotKey.presets[i]) }
                    }
                    if let hk, !HotKey.presets.contains(hk) { Chip(title: hk.label(), on: true) {} }
                    Chip(title: "Sin atajo", on: hk == nil) { app.setHotKey(nil) }
                }
                ActionButton(a: PopAction(title: "Grabar otro…", cmd: "", icon: "record.circle")) { app.recordHotKey() }
            }
            if let hk {
                PopSection("Qué hace cada uno") {
                    ForEach(0..<app.hotKeyLegend(hk).count, id: \.self) { i in
                        let l = app.hotKeyLegend(hk)[i]
                        HStack {
                            Text(l.text).font(.system(size: 12))
                            Spacer()
                            KeyCap(k: l.key)
                        }
                    }
                }
            }
        }
    }
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

/// Apps que vigila el detector (pestaña Detector). Premiere cambia de bundle id con cada versión.
let DET_APPS: [(key: String, name: String, matches: (String) -> Bool)] = [
    ("fcp", "Final Cut", { $0 == "com.apple.FinalCut" || $0 == "com.apple.FinalCutTrial" }),
    ("premiere", "Premiere", { $0.hasPrefix("com.adobe.PremierePro") }),
]
/// Tiempos elegibles en la pestaña Detector (clave, título, segundos).
let DET_TIMES: [(key: String, title: String, opts: [Int])] = [
    ("det.wait", "Primer aviso a los", [60, 120, 180, 300]),
    ("det.escalate", "Ventana tras otros", [180, 300, 600]),
    ("det.snooze", "Sin repetir durante", [600, 1200, 1800, 3600]),
    ("det.idle", "Deja de contar sin actividad a los", [60, 180, 300]),
]


/// El icono de la barra de menús: el mismo símbolo del Hub que está en el Dock (un playhead
/// recorriendo tres capas de la línea de tiempo), dibujado en un color como imagen *template*,
/// así macOS lo pinta en blanco o negro según el tema y la barra, igual que los SF Symbols.
/// Se dibuja en vectores a 18 pt, así se ve nítido en pantallas normales y Retina.
enum HubIcon {
    static let name = "hub"            // el nombre que usa render() (y la prueba sin pantalla)
    static let image: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            NSColor.black.setFill()
            // las capas: video arriba y en medio, audio abajo (como en el icono grande)
            for r in [NSRect(x: 2.0, y: 4.2, width: 8.6, height: 2.4),
                      NSRect(x: 5.0, y: 8.0, width: 11.0, height: 2.4),
                      NSRect(x: 2.0, y: 11.8, width: 10.6, height: 2.4)] {
                NSBezierPath(roundedRect: r, xRadius: 1.2, yRadius: 1.2).fill()
            }
            // hueco alrededor del playhead, para que se lea encima de las capas
            let x: CGFloat = 9.6
            ctx.setBlendMode(.clear)
            NSRect(x: x - 1.9, y: 3.4, width: 3.8, height: 14).fill()
            ctx.setBlendMode(.normal)
            // el playhead: cabeza en trapecio y la línea hacia abajo
            let head = NSBezierPath()
            head.move(to: NSPoint(x: x - 2.6, y: 0.8))
            head.line(to: NSPoint(x: x + 2.6, y: 0.8))
            head.line(to: NSPoint(x: x + 2.6, y: 2.4))
            head.line(to: NSPoint(x: x + 0.8, y: 4.2))
            head.line(to: NSPoint(x: x - 0.8, y: 4.2))
            head.line(to: NSPoint(x: x - 2.6, y: 2.4))
            head.close()
            head.lineJoinStyle = .round
            head.lineWidth = 0.6
            head.fill(); NSColor.black.setStroke(); head.stroke()
            NSBezierPath(roundedRect: NSRect(x: x - 0.8, y: 3.0, width: 1.6, height: 14.2),
                         xRadius: 0.8, yRadius: 0.8).fill()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Sprint de enfoque"
        return img
    }()
}

final class App: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate,
                 WKUIDelegate, NSPopoverDelegate {
    var panel: Panel!
    var web: HubWebView!
    var retry: Timer?
    var item: NSStatusItem!
    var sprint = Sprint()
    var dest = "", note = ""           // lo que propone la página (destino del próximo bloque, último aviso)
    var pick: [String: Any] = [:]      // listas de etapa/escena/tipo/esquema de la página (mensaje "state" de tellNative)
    var pickOverride: [String: String] = [:]   // lo recién elegido en el popover, hasta que la página mande su estado
    var polling = false
    var popover: NSPopover!
    let model = PopModel()
    var prevApp: NSRunningApplication?   // la app que estaba al frente al abrir el popover (vuelve al cerrarlo)
    var popMonitors: [Any] = []          // clic fuera del popover → se cierra (solo mientras está abierto)
    var popObserver: NSObjectProtocol?   // otra app al frente → se cierra
    var subPanel: SubPanel?              // la lista de Etapa / Escena al lado del popover
    var subClose: DispatchWorkItem?
    var subInside = false
    var chimed = ""
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
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover = NSPopover()
        // se cierra a mano (clic fuera, Esc, otra app al frente): con .transient un clic en la lista
        // de Etapa / Escena, que es otra ventana, también lo cerraría
        popover.behavior = .applicationDefined
        model.app = self
        popover.animates = true
        popover.delegate = self
        popover.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingController(rootView: SprintPopover(m: model, app: self))
        host.sizingOptions = .preferredContentSize   // el popover mide lo que su contenido (cambia con la pestaña)
        popover.contentViewController = host
        render()
        poll()
        startDetector()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.poll(); self?.detectorTick(); self?.render()
        }
        RunLoop.main.add(t, forMode: .common)     // sigue contando con el popover abierto

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

        // la primera vez se apunta para abrirse al iniciar sesión (se quita en la pestaña Ventana y barra)
        if !D.bool(forKey: "loginSetup") {
            D.set(true, forKey: "loginSetup")
            try? SMAppService.mainApp.register()
        }

        // Esc cierra el popover · ⌘W oculta la ventana · ⌘Q sale · ⌘R recarga (la app no tiene menú propio)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == UInt16(kVK_Escape), self?.popover.isShown == true { self?.closePopover(); return nil }
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

    func setFloating(_ desktop: Bool) {
        D.set(desktop, forKey: "onDesktop")
        detOpenedPanel = false
        applyLevel()
        if !panel.isVisible { showPanel() }
        model.bump()
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
    /// Nombre de la app si está vigilada (pestaña Detector); nil si no.
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

    /// Pestaña Detector: apps vigiladas y tiempos.
    func detToggleApp(_ k: String) {
        var apps = D.stringArray(forKey: "det.apps") ?? []
        if apps.contains(k) { apps.removeAll { $0 == k } } else { apps.append(k) }
        D.set(apps, forKey: "det.apps")
        model.bump()
    }

    func detPickTime(_ key: String, _ v: Int) { D.set(v, forKey: key); model.bump() }

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
        if popover?.isShown == true { model.bump() }
    }

    /// Aviso sonoro al llegar a la meta o al acabar el descanso (Sonidos → Meta), solo si acaba
    /// de pasar (no al abrir la app tarde). Suena aquí aunque la ventana esté visible: en modo
    /// mini la página ya no pone su tono.
    func chimeOnce(_ key: String, crossedAt ms: Double, when hit: Bool) {
        guard hit, chimed != key else { return }
        chimed = key
        if nowMs() - ms < 15_000 { Sounds.play("goal") }
    }

    // ───────────────────────── popover ─────────────────────────
    /// Clic en el reloj: abre o cierra el popover. Al abrir, la página oculta se pone al día con el
    /// server (si cambió algo manda "state") y la app pasa al frente para que Esc lo cierre; al
    /// cerrarlo vuelve al frente la app que estaba (Final Cut, Premiere…).
    @objc func togglePopover() {
        if popover.isShown { closePopover(); return }
        guard let b = item.button else { return }
        poll()
        web.callAsyncJavaScript("if (window.SprintCmd) window.SprintCmd('sync')", arguments: [:], in: nil, in: .page)
        let front = NSWorkspace.shared.frontmostApplication
        prevApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        model.sub = nil
        model.bump()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        b.highlight(true)
        // clic en otra app, en la ventana flotante o en otro icono de la barra → se cierra
        let downs: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: downs, handler: { [weak self] _ in self?.closePopover() }) {
            popMonitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: downs, handler: { [weak self] e in
            guard let self else { return e }
            let w = e.window
            // el propio reloj ya lo cierra con su acción (togglePopover)
            if w != self.popover.contentViewController?.view.window && w != self.subPanel && w != self.item.button?.window {
                self.closePopover()
            }
            return e
        }) { popMonitors.append(l) }
        popObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                             object: nil, queue: .main) { [weak self] _ in self?.closePopover() }
    }

    func closePopover() { if popover.isShown { popover.performClose(nil) } }

    func popoverDidClose(_ n: Notification) {
        popMonitors.forEach(NSEvent.removeMonitor)
        popMonitors = []
        if let o = popObserver { NotificationCenter.default.removeObserver(o); popObserver = nil }
        closeSub()
        item.button?.highlight(false)
        pickOverride = [:]
        if NSApp.isActive, let p = prevApp, !p.isTerminated, !panel.isKeyWindow { p.activate() }
        prevApp = nil
    }

    // ── la lista de Etapa / Escena al lado del popover (como un submenú: se abre al pasar el cursor) ──
    /// Filas de la lista: encabezados de grupo (i = -1) y opciones (i = índice en opts).
    func subRows(_ k: String) -> [(head: String, i: Int)] {
        var r: [(head: String, i: Int)] = [], g: String? = nil
        for (i, x) in opts(k).enumerated() {
            if x.g != g { g = x.g; if !x.g.isEmpty { r.append((head: x.g, i: -1)) } }
            r.append((head: "", i: i))
        }
        return r
    }
    func subSize(_ k: String) -> NSSize {
        let h = subRows(k).reduce(SubList.pad * 2) { $0 + ($1.i < 0 ? SubList.headH : SubList.rowH) }
        return NSSize(width: SubList.width, height: min(max(h, 40), SubList.maxH))
    }

    func subHover(_ k: String, _ inside: Bool, _ anchor: NSView?) {
        if inside { openSub(k, anchor) } else { closeSubSoon() }
    }
    func subPanelHover(_ inside: Bool) {
        subInside = inside
        if inside { subClose?.cancel(); subClose = nil } else { closeSubSoon() }
    }

    /// Abre (o cambia) la lista a la izquierda del popover, con su primera fila a la altura de la
    /// fila de Etapa / Escena; si no cabe a la izquierda, a la derecha.
    func openSub(_ k: String, _ anchor: NSView?) {
        subClose?.cancel(); subClose = nil
        guard let anchor, let win = anchor.window, let pw = popover.contentViewController?.view.window else { return }
        let p = subPanel ?? makeSubPanel()
        subPanel = p
        if model.sub != k { model.sub = k }
        let row = win.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let size = subSize(k), pf = pw.frame
        let scr = (pw.screen ?? NSScreen.main)?.visibleFrame ?? pf
        var x = pf.minX - size.width + 4
        if x < scr.minX + 4 { x = pf.maxX - 4 }
        let y = max(scr.minY + 4, min(row.maxY + 2 + SubList.pad - size.height, scr.maxY - size.height - 4))
        p.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        if p.parent == nil { pw.addChildWindow(p, ordered: .above) }
        p.orderFront(nil)
    }

    /// Se cierra un momento después de salir de la fila (da tiempo a llevar el cursor a la lista).
    func closeSubSoon() {
        subClose?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self, !self.subInside else { return }
            self.closeSub()
        }
        subClose = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }

    func closeSub() {
        subClose?.cancel(); subClose = nil; subInside = false
        if let p = subPanel { p.parent?.removeChildWindow(p); p.orderOut(nil) }
        if model.sub != nil { model.sub = nil }
    }

    func makeSubPanel() -> SubPanel {
        let p = SubPanel(contentRect: NSRect(x: 0, y: 0, width: SubList.width, height: 200),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.appearance = NSAppearance(named: .darkAqua)
        let fx = NSVisualEffectView(frame: p.contentRect(forFrameRect: p.frame))
        fx.material = .popover
        fx.state = .active
        fx.blendingMode = .behindWindow
        let r: CGFloat = 10
        let mask = NSImage(size: NSSize(width: 2 * r + 1, height: 2 * r + 1), flipped: false) { rect in
            NSColor.black.set(); NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill(); return true
        }
        mask.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        mask.resizingMode = .stretch
        fx.maskImage = mask
        let host = FirstMouseHost(rootView: SubList(m: model, app: self))
        host.frame = fx.bounds
        host.autoresizingMask = [.width, .height]
        fx.addSubview(host)
        p.contentView = fx
        return p
    }

    var detPrompting: Bool { sprint.online && sprint.run == nil && detector.prompting }

    /// La tarjeta principal: en marcha (reloj, etapa, playhead hacia la meta), descanso o reposo.
    func hero() -> Hero {
        let s = sprint, now = nowMs()
        var h = Hero()
        if !s.online {
            h.state = "Sin conexión"; h.idle = true
            h.title = "Hub local sin conexión"
            h.detail = BASE.replacingOccurrences(of: "http://", with: "") + " · reintentando…"
            return h
        }
        if let r = s.run {
            let el = (now - num(r["start"])) / 1000, target = num(r["target"]), left = target - el
            let etapa = str(r["etapa"]), escena = str(r["escenaNm"])
            h.state = "En curso"
            h.clock = target > 0 && D.bool(forKey: "showRemaining") ? (left < 0 ? "+" : "") + clock(left) : clock(el)
            h.title = r["db"] is String ? (etapa.isEmpty ? "Sin etapa" : etapa) : "Sin etapa en Notion (no se registrará)"
            var sub = [escena, str(r["tipo"]), str(r["wed"]), "desde " + hhmm(num(r["start"]))].filter { !$0.isEmpty }
            if target > 0 {
                sub.append("meta \(Int(target / 60)) min")
                h.progress = el / target
                h.over = left < 0
                if left < 0 { h.state = "Tiempo extra" }
            }
            h.detail = sub.joined(separator: " · ")
            return h
        }
        if let k = s.brk {
            let secs = num(k["secs"]), left = secs - (now - num(k["start"])) / 1000
            h.state = k["long"] as? Bool == true ? "Descanso largo" : "Descanso"
            h.clock = left > 0 ? clock(left) : "Listo"
            h.progress = secs > 0 ? 1 - max(0, left) / secs : nil
            h.tint = Pal.violeta
            h.title = "Luego, bloque \(s.cycle)"
            h.detail = dest
            return h
        }
        h.idle = true
        h.state = detector.prompting ? "Editas sin timer" : s.cycle > 1 ? "Entre bloques" : "Listo para empezar"
        h.clock = "00:00"
        h.title = dest.isEmpty ? "Sin etapa elegida" : dest
        h.detail = (MODES[s.mode] ?? s.mode) + (s.cycle > 1 ? " · bloque \(s.cycle)" : "")
        return h
    }

    /// Botones de la pestaña Sprint según el estado (los atajos globales, a su lado).
    func popActions() -> [PopAction] {
        let s = sprint, hk = HotKey.load()
        guard s.online else { return [] }
        var a: [PopAction] = []
        // cerrar la escena / la etapa elegidas sin bloque en marcha (por si al terminar no elegiste «…y cerrar»):
        // la página lo ofrece (pick["finE"] / pick["fin"]) solo si existen en Notion y no hay otro cierre en
        // espera. La fecha de fin que se registra es la de la última sesión de esa escena/etapa, no la del clic.
        func finStage() {
            guard s.close == nil else { return }
            func cut(_ t: String) -> String { t.count > 40 ? String(t.prefix(39)) + "…" : t }
            let finE = str(pick["finE"]), fin = str(pick["fin"])
            if !finE.isEmpty {
                a.append(PopAction(title: "Finalizar la escena «\(cut(finE))»", cmd: "close-escena", icon: "checkmark.circle"))
            }
            if !fin.isEmpty {
                a.append(PopAction(title: "Finalizar la etapa «\(cut(fin))»", cmd: "close-etapa", icon: "checkmark.seal"))
            }
        }
        if let r = s.run {
            a.append(PopAction(title: "Terminar", cmd: "finish", icon: "stop.fill", key: hk?.label() ?? "", kind: .primary))
            if r["db"] is String {
                if r["escena"] is String {
                    a.append(PopAction(title: "Terminar y cerrar «\(str(r["escenaNm"]))»", cmd: "finish-escena", icon: "checkmark.circle"))
                }
                if r["stageId"] is String {
                    a.append(PopAction(title: "Terminar y cerrar la etapa «\(str(r["etapa"]))»", cmd: "finish-etapa", icon: "checkmark.seal"))
                }
            }
            a.append(PopAction(title: "Descartar sin registrar", cmd: "discard", icon: "trash",
                               key: hk?.label(shift: true) ?? "", kind: .quiet))
        } else if s.brk != nil {
            a.append(PopAction(title: "Empezar bloque \(s.cycle)", cmd: "start", icon: "play.fill", key: hk?.label() ?? "", kind: .primary))
            a.append(PopAction(title: "Terminar ciclo", cmd: "endcycle", icon: "flag.checkered"))
            finStage()
        } else {
            a.append(PopAction(title: s.cycle > 1 ? "Empezar bloque \(s.cycle)" : "Iniciar sprint", cmd: "start",
                               icon: "play.fill", key: hk?.label() ?? "", kind: .primary))
            finStage()
        }
        return a
    }

    /// Avisos: cierre en Notion con margen para deshacer · registro pendiente · cola sin internet · último resultado.
    func notices() -> [Notice] {
        let s = sprint
        guard s.online else { return [] }
        var n: [Notice] = []
        let reopen = PopAction(title: "Abrir la ventana para reintentar", cmd: "show", icon: "macwindow")
        if let c = s.close {
            let label = str(c["label"])
            if c["err"] != nil {
                n.append(Notice(text: "No se pudo cerrar «\(label)» en Notion", warn: true, action: reopen))
            } else if num(c["due"]) > nowMs() {
                n.append(Notice(text: "Se cerrará «\(label)» en Notion en unos segundos",
                                action: PopAction(title: "Deshacer el cierre", cmd: "undo", icon: "arrow.uturn.backward")))
            }
        }
        if s.pend { n.append(Notice(text: "Hay una sesión sin registrar", warn: true, action: reopen)) }
        if !s.queued.isEmpty {
            let perm = s.queued.filter { $0["perm"] as? Bool == true }
            var t = "Guardado en el Mac: \(queuedText()). Se sube solo a Notion al volver internet."
            if !perm.isEmpty {
                let e = str(perm[0]["err"])
                t += " Notion rechazó \(perm.count == 1 ? "uno" : "\(perm.count)"): " + (e.count > 60 ? String(e.prefix(59)) + "…" : e)
            }
            n.append(Notice(text: t, warn: !perm.isEmpty, action: PopAction(title: "Subir ahora", cmd: "flush", icon: "icloud.and.arrow.up")))
        } else if s.sentAt > 0 && nowMs() - s.sentAt < 12 * 3600 * 1000 {
            n.append(Notice(text: "Subido a Notion a las \(hhmm(s.sentAt)) (\(s.sentN) \(s.sentN == 1 ? "envío guardado" : "envíos guardados") sin internet)"))
        }
        if s.run == nil && !note.isEmpty && s.close == nil {
            n.append(Notice(text: note.count > 90 ? String(note.prefix(89)) + "…" : note))
        }
        return n
    }

    /// Ejecuta un botón del popover. El popover sigue abierto: la tarjeta muestra el resultado.
    func perform(_ a: PopAction) {
        switch a.cmd {
        case "det-start": detStart()
        case "det-mute": detMute()
        case "show": showPanel()
        case "flush": flushNow()
        case "": break
        default:
            send(a.cmd) { [weak self] r in
                if r != "ok" { Sounds.play("error") }    // la página no estaba lista o el estado ya cambió
                self?.poll()
            }
        }
        model.bump()
    }

    // ───────────────────────── Etapa / Escena / Tipo / Esquema ─────────────────────────
    /// Las listas vienen de la propia página (las mismas que ve la ventana, con sus grupos
    /// En curso / Por hacer…) y elegir una opción es tocar esa lista o ese botón: se guarda y
    /// se sincroniza con el dashboard. Como en la ventana, con un bloque en marcha no se cambian
    /// (con etapa y escena se registra la sesión en Notion) y el esquema solo en reposo.
    /// Elegir no cierra el popover: se pueden cambiar varias cosas seguidas.
    typealias Opt = (v: String, t: String, g: String)
    /// tipo → (lista, "¿se puede?" que manda la página, título)
    var PICKS: [String: (list: String, flag: String, title: String)] {
        ["proyecto": ("etapas", "pick", "Proyecto"),
         "etapa": ("etapas", "pick", "Etapa"), "escena": ("escenas", "pick", "Escena"),
         "tipo": ("tipos", "pick", "Tipo"), "modo": ("modos", "pickModo", "Esquema")]
    }
    func opts(_ k: String) -> [Opt] {
        if k == "proyecto" { return projects() }
        if k == "etapa", byProject {      // solo las etapas del proyecto elegido, sin repetir su nombre
            let p = curProject()
            return etapasAll().filter { $0.p == p }.map { ($0.v, $0.s.isEmpty ? $0.t : $0.s, $0.g) }
        }
        return (pick[PICKS[k]?.list ?? ""] as? [[String: Any]] ?? []).map { (str($0["v"]), str($0["t"]), str($0["g"])) }
    }

    /// Proyecto ▸ (boda o proyecto freelance): la página manda en cada etapa su proyecto (p) y su
    /// nombre corto (s). Los proyectos salen en el orden de sus etapas (los que tienen una en curso
    /// primero, el último trabajado arriba) y con el grupo de su primera etapa. El proyecto elegido
    /// es el de la etapa elegida; elegir otro elige su primera etapa (la última trabajada si hay
    /// una en curso, si no la siguiente por empezar). Con un solo proyecto la fila no sale.
    typealias Etp = (v: String, t: String, g: String, p: String, s: String)
    func etapasAll() -> [Etp] {
        (pick["etapas"] as? [[String: Any]] ?? []).map { (str($0["v"]), str($0["t"]), str($0["g"]), str($0["p"]), str($0["s"])) }
    }
    /// La página es de antes (sus etapas no traen proyecto): lista única, como antes.
    var byProject: Bool { let e = etapasAll(); return !e.isEmpty && e.allSatisfy { !$0.p.isEmpty } }
    func projects() -> [Opt] {
        guard byProject else { return [] }
        var seen = Set<String>(), r: [Opt] = []
        for x in etapasAll() where seen.insert(x.p).inserted { r.append((x.p, x.p, x.g)) }
        return r
    }
    func curProject() -> String {
        let e = etapasAll(), cur = curPick("etapa")
        return e.first(where: { $0.v == cur })?.p ?? e.first?.p ?? ""
    }
    func can(_ k: String) -> Bool {
        guard let p = PICKS[k], sprint.run == nil, pick[p.flag] as? Bool == true, !opts(k).isEmpty else { return false }
        if k == "proyecto" { return opts(k).count > 1 }
        return k != "modo" || sprint.brk == nil
    }
    /// Qué se puede elegir ahora (el esquema no se cambia en el descanso, como en la ventana).
    func pickKinds() -> [String] {
        guard sprint.online, sprint.run == nil else { return [] }
        let ks = sprint.brk != nil ? ["proyecto", "etapa", "escena", "tipo"] : ["proyecto", "etapa", "escena", "tipo", "modo"]
        return ks.filter { can($0) && ($0 == "modo" || can("etapa")) }
    }
    func curPick(_ k: String) -> String { k == "proyecto" ? curProject() : pickOverride[k] ?? str(pick[k]) }
    func pickLabel(_ k: String) -> String {
        let cur = curPick(k)
        return cur.isEmpty && k == "escena" ? "Ninguna" : opts(k).first(where: { $0.v == cur })?.t ?? "—"
    }

    /// Elegir en Etapa / Escena / Tipo / Esquema: la marca se mueve ya y vuelve a su sitio si la
    /// página no lo acepta.
    func choose(_ k: String, _ v: String) {
        if k == "proyecto" {           // cambiar de proyecto = elegir su primera etapa (la página no sabe de proyectos)
            guard v != curProject(), let first = etapasAll().first(where: { $0.p == v }) else { return }
            choose("etapa", first.v)
            return
        }
        pickOverride[k] = v
        model.bump()
        send("\(k):\(v)") { [weak self] r in
            if r != "ok" { Sounds.play("error"); self?.pickOverride[k] = nil; self?.model.bump() }
            self?.poll()
        }
    }

    func toggleRemaining() { D.set(!D.bool(forKey: "showRemaining"), forKey: "showRemaining"); render() }

    func toggleLogin() {
        let s = SMAppService.mainApp
        if s.status == .enabled { try? s.unregister() } else { try? s.register() }
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

    /// Destello breve del reloj (otro icono 1,5 s) + el sonido de la acción (pestaña Sonidos);
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

    /// Pestaña Sonidos: elegir guarda y suena.
    func pickSound(_ action: String, _ v: String) {
        Sounds.set(action, v)
        Sounds.play(name: v)
        model.bump()
    }

    func resetSounds() { Sounds.actions.forEach { D.removeObject(forKey: "snd." + $0.key) } }

    /// Pestaña Atajos: uno de los de serie o ninguno (nil).
    func setHotKey(_ p: HotKey?) {
        if let p { p.save() } else { D.set(true, forKey: "hkOff") }
        if !registerHotKeys() { hotKeyTaken() }
        model.bump()
    }

    /// La lista «Qué hace cada uno» de la pestaña Atajos.
    func hotKeyLegend(_ hk: HotKey) -> [(key: String, text: String)] {
        var l = [(key: hk.label(), text: "Iniciar, o terminar y registrar"),
                 (key: hk.label(shift: true), text: "Descartar sin registrar")]
        if !hk.mods.contains(.command) { l.append((key: hk.label(cmd: true), text: "Mostrar u ocultar la ventana")) }
        l.append((key: hk.tipoLabel, text: "Cambiar Edición ↔ Gestión"))
        return l
    }

    func hotKeyTaken() {
        closePopover()
        let a = NSAlert()
        a.messageText = "Ese atajo ya lo usa otra app"
        a.informativeText = "Elige otro en la pestaña Atajos del reloj."
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    /// Graba un atajo nuevo: con ⌃ y/o ⌥, sin ⇧ ni ⌘ (⇧ descarta, ⌘ muestra/oculta la ventana).
    func recordHotKey() {
        closePopover()
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
            pickOverride = [:]                                      // manda lo que quedó de verdad
            model.bump()
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
/// contenido del popover (con las listas) y lo imprime; HUB_PICK="modo:pomo,etapa:<db>,…" ejecuta cada
/// orden por el mismo camino que el popover (send → SprintCmd) y vuelve a imprimirlo.
extension App {
    /// Imprime lo que mostraría el popover (pestaña Sprint, con las listas de Etapa / Escena / Tipo /
    /// Esquema y la opción actual con ✓); con HUB_SNAPSHOT_POPOVER=/ruta.png guarda además una
    /// captura del popover tal como se dibuja.
    func dumpMenu(_ tag: String) {
        let h = hero()
        print("== \(tag) · barra: \(symbolNow) «\(item.button?.title ?? "")» · detector: \(detector.phase.rawValue) · ventana: \(panel.isVisible)")
        if detPrompting { print("aviso: editas en \(detLabel) sin timer — Iniciar sprint | Ahora no") }
        print("[\(h.state)] \(h.clock) \(h.title)" + (h.detail.isEmpty ? "" : " · " + h.detail))
        for a in popActions() { print("  (\(a.title))" + (a.key.isEmpty ? "" : "   [\(a.key)]")) }
        for k in pickKinds() {
            print("\(PICKS[k]?.title ?? k): \(pickLabel(k)) ▸")
            var g: String? = nil
            for o in opts(k) {
                if o.g != g { g = o.g; if !o.g.isEmpty { print("    -- \(o.g)") } }
                print("    " + (o.v == curPick(k) ? "✓ " : "  ") + o.t)
            }
        }
        for n in notices() { print((n.warn ? "⚠︎ " : "· ") + n.text + (n.action.map { "   (\($0.title))" } ?? "")) }
        if tag == "final" {
            let apps = D.stringArray(forKey: "det.apps") ?? []
            print("Detector: \(D.bool(forKey: "det.on") ? "✓" : "✗") · " + DET_APPS.map { (apps.contains($0.key) ? "✓ " : "✗ ") + $0.name }.joined(separator: " · ")
                  + " · " + DET_TIMES.map { "\($0.title) \(Int(D.double(forKey: $0.key))) s" }.joined(separator: " · "))
            if let out = ProcessInfo.processInfo.environment["HUB_SNAPSHOT_POPOVER"] { snapshotPopover(out) }
        }
        fflush(stdout)
    }
    /// Dibuja el popover fuera de pantalla y lo guarda como PNG (prueba visual sin tocar nada).
    func snapshotPopover(_ out: String) {
        let host = NSHostingView(rootView: SprintPopover(m: model, app: self)
            .background(Color(hex: 0x2a2a2e)))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
        print("captura del popover → \(out)")
        // y la lista de Etapa como se ve al pasar el cursor
        model.sub = "etapa"
        let sub = NSHostingView(rootView: SubList(m: model, app: self).background(Color(hex: 0x2a2a2e)))
        sub.appearance = NSAppearance(named: .darkAqua)
        sub.frame = NSRect(origin: .zero, size: subSize("etapa"))
        sub.layoutSubtreeIfNeeded()
        let out2 = (out as NSString).deletingPathExtension + "-etapa.png"
        if let r2 = sub.bitmapImageRepForCachingDisplay(in: sub.bounds) {
            sub.cacheDisplay(in: sub.bounds, to: r2)
            try? r2.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out2))
            print("captura de la lista de Etapa → \(out2)")
        }
        model.sub = nil
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
            if c.hasPrefix("proyecto:") {    // como elegir en Proyecto ▸ (choose → etapa:<db> → SprintCmd)
                choose("proyecto", String(c.dropFirst(9)))
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { next() }
                return
            }
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

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
