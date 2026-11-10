import AppKit
import Carbon
import KeyPilotCore

let postedEventMarker:Int64=0x4B50494C4F54

final class Hotkeys {
    var triggered:((Bool)->Void)?
    private var references:[EventHotKeyRef]=[]
    private var handler:EventHandlerRef?
    func connect() -> String? {
        disconnect()
        var spec=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        let context=Unmanaged.passUnretained(self).toOpaque()
        let result=InstallEventHandler(GetApplicationEventTarget(),{ _,event,context in
            guard let event,let context else { return OSStatus(eventNotHandledErr) }
            var identifier=EventHotKeyID()
            GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&identifier)
            Unmanaged<Hotkeys>.fromOpaque(context).takeUnretainedValue().triggered?(identifier.id == 1)
            return noErr
        },1,&spec,context,&handler)
        guard result == noErr else { return "无法安装热键监听（\(result)）" }
        for (id,key) in [(UInt32(1),UInt32(kVK_Space)),(UInt32(2),UInt32(kVK_ANSI_J))] {
            var ref:EventHotKeyRef?
            let error=RegisterEventHotKey(key,UInt32(cmdKey|shiftKey),EventHotKeyID(signature:0x4B504C54,id:id),GetApplicationEventTarget(),0,&ref)
            guard error == noErr, let ref else { disconnect(); return "⇧⌘\(id == 1 ? "Space":"J") 注册失败，可能与其他应用冲突（\(error)）" }
            references.append(ref)
        }
        return nil
    }
    func disconnect() { references.forEach{UnregisterEventHotKey($0)}; references=[]; if let handler { RemoveEventHandler(handler) }; handler=nil }
    deinit { disconnect() }
}

/// Reusable event tap on a private run loop. The callback never queries AX or performs layout.
final class InputCapture {
    var handle:((CGEventType,CGEvent)->Bool)?
    var disabled:((Bool,Bool)->Void)?
    private var port:CFMachPort?
    private var source:CFRunLoopSource?
    private var loop:CFRunLoop?
    private var thread:Thread?
    private let lock=NSLock()
    private(set) var available=false
    func prepare() -> Bool {
        lock.lock(); let exists=port != nil; lock.unlock()
        if exists { return true }
        let ready=DispatchSemaphore(value:0)
        let worker=Thread { [weak self] in
            guard let self else { ready.signal(); return }
            let mask:[CGEventType]=[.keyDown,.keyUp,.flagsChanged,.leftMouseDown,.rightMouseDown,.otherMouseDown]
            let bits=mask.reduce(CGEventMask(0)){$0 | (CGEventMask(1)<<$1.rawValue)}
            let tap=CGEvent.tapCreate(tap:.cgSessionEventTap,place:.headInsertEventTap,options:.defaultTap,eventsOfInterest:bits,callback:{ _,type,event,context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let capture=Unmanaged<InputCapture>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    capture.disabled?(type == .tapDisabledByTimeout,capture.enabled)
                    return Unmanaged.passUnretained(event)
                }
                if event.getIntegerValueField(.eventSourceUserData) == postedEventMarker { return Unmanaged.passUnretained(event) }
                return capture.handle?(type,event) == true ? nil:Unmanaged.passUnretained(event)
            },userInfo:Unmanaged.passUnretained(self).toOpaque())
            guard let tap else { ready.signal(); return }
            let source=CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0)
            let runloop=CFRunLoopGetCurrent()
            self.lock.lock(); self.port=tap; self.source=source; self.loop=runloop; self.available=true; self.lock.unlock()
            CGEvent.tapEnable(tap:tap,enable:false)
            CFRunLoopAddSource(runloop,source,.commonModes); ready.signal(); CFRunLoopRun()
            CFMachPortInvalidate(tap)
        }
        worker.name="Keylian input"; worker.qualityOfService = .userInteractive; thread=worker; worker.start()
        _=ready.wait(timeout:.now()+1)
        return available
    }
    var enabled:Bool { lock.lock(); defer{lock.unlock()}; return port.map{CGEvent.tapIsEnabled(tap:$0)} ?? false }
    func enable(_ value:Bool) {
        lock.lock(); defer{lock.unlock()}
        if let port, CGEvent.tapIsEnabled(tap:port) != value { CGEvent.tapEnable(tap:port,enable:value) }
    }
    static func modifiers(_ flags:CGEventFlags) -> Modifiers {
        var result:Modifiers=[]
        if flags.contains(.maskShift) { result.insert(.shift) }; if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskAlternate) { result.insert(.option) }; if flags.contains(.maskControl) { result.insert(.control) }
        return result
    }
}

/// Confined to the control queue. Timer ticks never wait on AX, layout or the main thread.
final class InputPoster {
    private let source=CGEventSource(stateID:.privateState)
    private var original:CGPoint?
    private var parked:CGPoint?
    private var postedHover=false
    private var timer:DispatchSourceTimer?
    private var direction=0
    private var speed=900.0
    private var lastTime=0.0
    private var fraction=0.0
    private var intervals:[Double]=[]
    private let queue:DispatchQueue
    private let emit:(CGEvent)->Void
    private let pointer:()->CGPoint?
    private let warp:(CGPoint)->Void
    var tick:(()->Void)?
    init(queue:DispatchQueue,emit:@escaping(CGEvent)->Void = {$0.post(tap:.cghidEventTap)},pointer:@escaping()->CGPoint? = {CGEvent(source:nil)?.location},warp:@escaping(CGPoint)->Void = {_=CGWarpMouseCursorPosition($0)}) {
        self.queue=queue; self.emit=emit; self.pointer=pointer; self.warp=warp
    }
    private func park(_ point:Point) {
        let current=pointer()
        if original == nil { original=current }
        else if let current, let parked, hypot(current.x-parked.x,current.y-parked.y)>4 { original=current }
        let position=CGPoint(x:point.x,y:point.y)
        warp(position); parked=position
    }
    func restorePointer() {
        defer { original=nil; parked=nil; postedHover=false }
        guard let original,let parked,let current=pointer(),hypot(current.x-parked.x,current.y-parked.y)<=4 else { return }
        warp(original)
        if postedHover { postPointerMotion(original) }
    }
    func scroll(direction:Int,speed:Double,point:Point,intentAt:Double) {
        guard direction != 0 else { stop(); return }
        self.direction=direction; self.speed=speed
        if timer != nil { return }
        park(point); fraction=0; intervals=[]; lastTime=ProcessInfo.processInfo.systemUptime
        postScroll(Double(direction)*speed/120)
        let timer=DispatchSource.makeTimerSource(queue:queue)
        timer.schedule(deadline:.now() + .milliseconds(8),repeating:.milliseconds(8),leeway:.milliseconds(1))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now=ProcessInfo.processInfo.systemUptime, delta=now-self.lastTime; self.lastTime=now
            if self.intervals.count < 10000 { self.intervals.append(delta*1000) }
            // A suspended process must not replay an accumulated scroll burst.
            self.postScroll(Double(self.direction)*self.speed*min(0.05,delta)); self.tick?()
        }
        self.timer=timer; timer.resume()
        Diagnostics.shared.record("scroll_started",["speed":speed,"input_callback_to_first_post_ms":max(0,(ProcessInfo.processInfo.systemUptime-intentAt)*1000)])
    }
    private func postScroll(_ delta:Double) {
        fraction += delta
        let amount=Int32(fraction.rounded(.towardZero)); fraction -= Double(amount)
        guard amount != 0, let event=CGEvent(scrollWheelEvent2Source:source,units:.pixel,wheelCount:1,wheel1:-amount,wheel2:0,wheel3:0) else { return }
        if let parked { event.location=parked }
        event.flags=[]; event.setIntegerValueField(.eventSourceUserData,value:postedEventMarker)
        emit(event)
    }
    func jump(top:Bool,point:Point) { park(point); postScroll(top ? -100_000:100_000) }
    func hover(point:Point) {
        park(point); postPointerMotion(CGPoint(x:point.x,y:point.y)); postedHover=true
        Diagnostics.shared.record("row_hover_posted")
    }
    private func postPointerMotion(_ point:CGPoint) {
        if let event=CGEvent(mouseEventSource:source,mouseType:.mouseMoved,mouseCursorPosition:point,mouseButton:.left) {
            event.flags=[]; event.setIntegerValueField(.eventSourceUserData,value:postedEventMarker); emit(event)
        }
    }
    func click(point:Point,kind:ClickKind) {
        park(point)
        let button:CGMouseButton=kind == .right ? .right:.left
        let down:CGEventType=kind == .right ? .rightMouseDown:.leftMouseDown, up:CGEventType=kind == .right ? .rightMouseUp:.leftMouseUp
        for type in [down,up] {
            if let event=CGEvent(mouseEventSource:source,mouseType:type,mouseCursorPosition:CGPoint(x:point.x,y:point.y),mouseButton:button) {
                event.flags=kind == .command ? .maskCommand:[]; event.setIntegerValueField(.mouseEventClickState,value:1)
                event.setIntegerValueField(.eventSourceUserData,value:postedEventMarker); emit(event)
            }
        }
        Diagnostics.shared.record("click_posted",["kind":kind.rawValue])
    }
    func stop() {
        let running=timer != nil; timer?.cancel(); timer=nil; direction=0; fraction=0
        if running && !intervals.isEmpty {
            let values=intervals.sorted()
            Diagnostics.shared.record("scroll_ticks",["count":values.count,"p50_ms":values[values.count/2],"p95_ms":values[min(values.count-1,Int(Double(values.count)*0.95))],"max_ms":values.last!])
        }
        intervals=[]
    }
}
