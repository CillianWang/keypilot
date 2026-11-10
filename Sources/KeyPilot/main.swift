import AppKit
import ApplicationServices
import KeyPilotCore

final class AppDelegate:NSObject,NSApplicationDelegate,NSMenuDelegate {
    private var statusItem:NSStatusItem!
    private let settings=Settings.shared
    private lazy var controller=NavigationController(preferences:settings.values)
    private let hotkeys=Hotkeys()
    private var tokens:[NSObjectProtocol]=[]
    private var hotkeyOK=false
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        statusItem.button?.image=Brand.image(size:18,template:true)
        let menu=NSMenu(); menu.delegate=self
        for (title,action,key) in [("启用 KeyPilot",#selector(toggle),""),("设置…",#selector(showSettings),","),("重新连接",#selector(reconnect),""),("退出 KeyPilot",#selector(quit),"q")] {
            let item=NSMenuItem(title:title,action:action,keyEquivalent:key); item.target=self; menu.addItem(item)
        }
        statusItem.menu=menu
        settings.changed={ [weak self] values in
            guard let self else { return }
            self.controller.configure(values)
            if values.enabled && !self.hotkeyOK { self.connect() }
            if !values.enabled { self.hotkeys.disconnect(); self.hotkeyOK=false; self.settings.status="已停用"; self.writeReady() }
            self.statusItem.button?.appearsDisabled = !values.enabled
        }
        settings.reconnect={ [weak self] in self?.connect() }
        hotkeys.triggered={ [weak self] toggle in self?.controller.hotkey(toggle:toggle) }
        let workspace=NSWorkspace.shared.notificationCenter
        tokens.append(workspace.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main) { [weak self] note in
            if let app=note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { self?.controller.foregroundChanged(pid:app.processIdentifier) }
        })
        for name in [NSWorkspace.willSleepNotification,NSWorkspace.sessionDidResignActiveNotification,NSWorkspace.activeSpaceDidChangeNotification] {
            tokens.append(workspace.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in self?.controller.interrupted() })
        }
        tokens.append(NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main) { [weak self] _ in self?.controller.interrupted(resetScreens:true) })
        DistributedNotificationCenter.default().addObserver(self,selector:#selector(locked),name:NSNotification.Name("com.apple.screenIsLocked"),object:nil)
        connect()
        if CommandLine.arguments.contains("--show-settings") { settings.show() }
    }
    private func connect() {
        controller.interrupted(); settings.trusted=AXIsProcessTrusted()
        guard settings.values.enabled else { hotkeys.disconnect(); hotkeyOK=false; settings.status="已停用"; writeReady(); return }
        if let error=hotkeys.connect() { hotkeyOK=false; settings.status=error }
        else { hotkeyOK=true; settings.status=settings.trusted ? "热键已就绪：⇧⌘Space / ⇧⌘J":"热键已注册；等待辅助功能授权" }
        if settings.trusted { controller.reconnectCapture() }
        if let front=NSWorkspace.shared.frontmostApplication { controller.foregroundChanged(pid:front.processIdentifier) }
        writeReady()
    }
    private func writeReady() { settings.hotkeysReady=hotkeyOK; Diagnostics.shared.ready(trusted:settings.trusted,enabled:settings.values.enabled,hotkeys:hotkeyOK,glassStyle:settings.values.glassStyle.rawValue,foldRowActions:settings.values.foldRowActions) }
    func menuNeedsUpdate(_ menu:NSMenu) { menu.items.first?.state=settings.values.enabled ? .on:.off; settings.trusted=AXIsProcessTrusted(); writeReady() }
    @objc private func locked() { controller.interrupted() }
    @objc private func toggle() { settings.values.enabled.toggle() }
    @objc private func showSettings() { settings.show() }
    @objc private func reconnect() { connect() }
    @objc private func quit() { controller.interrupted(); DispatchQueue.main.asyncAfter(deadline:.now()+0.1) { NSApp.terminate(nil) } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool) -> Bool { settings.show(); return true }
    func applicationWillTerminate(_ notification:Notification) { controller.shutdown() }
}

func printJSON(_ value:[String:Any]) {
    if let data=try? JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]),let text=String(data:data,encoding:.utf8) { print(text) }
}

func renderFixture(to path:String,style:GlassStyle = .light) {
    _=NSApplication.shared
    let screen=OverlayManager.screenModels.first ?? Screen(id:1,frame:Rect(0,0,1200,800))
    let regions=[Region(id:1,frame:Rect(20,35,320,690)),Region(id:2,frame:Rect(355,35,780,690))]
    let canvas=OverlayCanvas(frame:NSRect(x:0,y:0,width:1180,height:770),screen:Screen(id:screen.id,frame:Rect(0,0,1180,770)))
    let targets=(0..<12).map { Target(id:ElementID(100+$0),frame:Rect(390,100+Double($0)*45,650,32),ancestors:[2],role:"AXRow") }
    var book=CodeBook(); let codes=book.publish(ids:targets.map(\.id),alive:Set(targets.map(\.id)),final:true,exhaustive:true)
    let layout=LabelLayout.layout(targets:targets,screens:[Screen(id:screen.id,frame:Rect(0,0,1180,770))],reserved:[],size:Point(35,23))
    var preferences=Preferences(); preferences.glassStyle=style
    let state=OverlayFrame(regions:regions,selected:2,regionLabels:[1:"W",2:"E"],placements:layout.first ?? [],codes:codes,buttonPrefix:"S",regionPrefix:"",selectedButton:101,mode:.navigation,endpoint:.bottom,preferences:preferences)
    canvas.update(state)
    guard let bitmap=canvas.bitmapImageRepForCachingDisplay(in:canvas.bounds) else { exit(1) }
    canvas.cacheDisplay(in:canvas.bounds,to:bitmap)
    if let data=bitmap.representation(using:.png,properties:[:]) { try? data.write(to:URL(fileURLWithPath:path)) }
    var evidence=canvas.animationEvidence(); evidence["button_font"]=13; evidence["region_font"]=20
    evidence["glass"]=canvas.glassEvidence()
    evidence["glass_style"]=style.rawValue
    let scale=Double(bitmap.pixelsWide)/canvas.bounds.width
    func alpha(_ x:Double,_ y:Double) -> Double { Double(bitmap.colorAt(x:Int(x*scale),y:Int(y*scale))?.alphaComponent ?? -1) }
    evidence["interior_pixel_alpha"]=alpha(600,650)
    if let first=layout.first?.first { evidence["button_background_pixel_alpha"]=alpha(first.rect.x+2,first.rect.center.y) }
    evidence["region_background_pixel_alpha"]=alpha(29,57)
    evidence["endpoint_pixel_alpha"]=alpha(700,723.5)
    var reduced=state; reduced.preferences.reduceMotion=true; canvas.update(reduced)
    evidence["reduced_motion"]=canvas.animationEvidence()
    reduced.preferences.reduceTransparency=true; canvas.update(reduced)
    evidence["reduced_transparency"]=canvas.glassEvidence()
    printJSON(evidence)
}

let args=CommandLine.arguments
if let index=args.firstIndex(of:"--export-brand"),args.count > index+1 {
    _=NSApplication.shared
    do { try Brand.export(to:args[index+1]) } catch { printJSON(["error":error.localizedDescription]); exit(1) }
} else if let index=args.firstIndex(of:"--render-settings"),args.count > index+1 {
    _=NSApplication.shared
    do { try SettingsRenderer.render(to:args[index+1]) } catch { printJSON(["error":error.localizedDescription]); exit(1) }
} else if args.contains("--self-check") {
    printJSON(["trusted":AXIsProcessTrusted(),"bundle_id":Bundle.main.bundleIdentifier ?? "unbundled","minimum_macos":"13.0","version":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development"])
} else if let index=args.firstIndex(of:"--render-fixture"),args.count > index+1 {
    let styleIndex=args.firstIndex(of:"--glass-style")
    let style=styleIndex.flatMap { $0+1 < args.count ? GlassStyle(rawValue:args[$0+1]):nil } ?? .light
    renderFixture(to:args[index+1],style:style)
} else if args.contains("--scan-frontmost") {
    guard AXIsProcessTrusted(),let pid=NSWorkspace.shared.frontmostApplication?.processIdentifier else { printJSON(["error":"accessibility_permission_required"]); exit(2) }
    let reader=SystemAXReader(pid:pid,registry:AXRegistry()); reader.prewarm(); reader.begin()
    guard let window=reader.currentWindow() else { printJSON(["error":"window_unavailable"]); exit(3) }
    let traversal=ScanTraversal(reader:reader,root:window.id,window:window.frame,additionalRoots:window.extras)
    var result=traversal.step()
    while !result.final { result=traversal.step() }
    printJSON(["nodes":result.count,"targets":result.targets.count,"regions":result.regions.count,"exhaustive":result.exhaustive,"ax_calls":reader.calls,"ax_ms":reader.ipcSeconds*1000,"working_ms":result.workingSeconds*1000])
} else {
    let application=NSApplication.shared
    let delegate=AppDelegate(); application.delegate=delegate; application.run()
}
