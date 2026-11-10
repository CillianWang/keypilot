import AppKit
import SwiftUI
import ApplicationServices

enum GlassStyle:String,CaseIterable {
    case light,dark,tea,system
    var title:String { switch self { case .light:return "浅色通透"; case .dark:return "深色玻璃"; case .tea:return "茶色玻璃"; case .system:return "跟随系统" } }
}

struct Preferences: Equatable {
    var enabled=true
    var automaticClick=true
    var foldRowActions=true
    var speed=900.0
    var acceleration=2.5
    var fontSize=13.0
    var red=0.66,green=0.92,blue=0.81
    var animation=true
    var reduceMotion=false
    var reduceTransparency=false
    var glassStyle:GlassStyle = .light
}
final class Settings: ObservableObject {
    static let shared=Settings()
    @Published var values:Preferences { didSet { save(); changed?(values) } }
    @Published var status="正在连接…"
    @Published var trusted=false
    @Published var hotkeysReady=false
    var changed:((Preferences)->Void)?
    var reconnect:(()->Void)?
    private let defaults:UserDefaults
    private var window:NSWindow?
    init(defaults:UserDefaults = .standard,observeSystem:Bool=true) {
        self.defaults=defaults
        defaults.register(defaults:["enabled":true,"automaticClick":true,"foldRowActions":true,"speed":900.0,"acceleration":2.5,"fontSize":13.0,"red":0.66,"green":0.92,"blue":0.81,"animation":true])
        values=Preferences(enabled:defaults.bool(forKey:"enabled"),automaticClick:defaults.bool(forKey:"automaticClick"),foldRowActions:defaults.bool(forKey:"foldRowActions"),speed:min(2000,max(300,defaults.double(forKey:"speed"))),acceleration:min(5,max(1,defaults.double(forKey:"acceleration"))),fontSize:min(20,max(11,defaults.double(forKey:"fontSize"))),red:defaults.double(forKey:"red"),green:defaults.double(forKey:"green"),blue:defaults.double(forKey:"blue"),animation:defaults.bool(forKey:"animation"),reduceMotion:NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,reduceTransparency:NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,glassStyle:GlassStyle(rawValue:defaults.string(forKey:"glassStyle") ?? "") ?? .light)
        guard observeSystem else { return }
        NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object:nil,queue:.main) { [weak self] _ in
            guard let self else { return }
            var updated=self.values
            updated.reduceMotion=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            updated.reduceTransparency=NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            self.values=updated
        }
    }
    private func save() {
        for (key,value) in ["enabled":values.enabled,"automaticClick":values.automaticClick,"foldRowActions":values.foldRowActions,"speed":values.speed,"acceleration":values.acceleration,"fontSize":values.fontSize,"red":values.red,"green":values.green,"blue":values.blue,"animation":values.animation,"glassStyle":values.glassStyle.rawValue] as [String:Any] { defaults.set(value,forKey:key) }
    }
    func show() {
        if window == nil {
            let w=NSWindow(contentRect:NSRect(x:0,y:0,width:980,height:730),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
            w.title="KeyPilot 设置"; w.isReleasedWhenClosed=false
            w.titleVisibility = .hidden; w.titlebarAppearsTransparent=true
            w.backgroundColor = .windowBackgroundColor
            w.contentMinSize=NSSize(width:860,height:650)
            w.setFrameAutosaveName("KeyPilotSettings")
            w.contentView=NSHostingView(rootView:SettingsView(settings:self)); w.center(); window=w
        }
        trusted=AXIsProcessTrusted()
        NSApp.activate(ignoringOtherApps:true); window?.makeKeyAndOrderFront(nil)
    }
    func openPermission() { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
}
