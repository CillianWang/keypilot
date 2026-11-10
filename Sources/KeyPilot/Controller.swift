import AppKit
import ApplicationServices
import KeyPilotCore

final class NavigationController {
    let queue=DispatchQueue(label:"dev.pingy.keypilot.control",qos:.userInteractive)
    private let axQueue=DispatchQueue(label:"dev.pingy.keypilot.ax",qos:.userInitiated)
    private let layoutQueue=DispatchQueue(label:"dev.pingy.keypilot.layout",qos:.userInitiated)
    private let overlay=OverlayManager()
    private let capture=InputCapture()
    private lazy var poster=InputPoster(queue:queue)
    private var machine=NavigationMachine()
    private var preferences:Preferences
    private var session:UInt64=0
    private var scanNumber:UInt64=0
    private var layoutNumber:UInt64=0
    private var foregroundPID:pid_t=0
    private var activePID:pid_t=0
    private var windowID:ElementID?
    private var reader:SystemAXReader?
    private var observation:AXObservation?
    private var scanToken:Cancellation?
    private var layoutToken:Cancellation?
    private var actionToken=Cancellation()
    private var scanning=false
    private var geometryValid=false
    private var snapshot:ScanSnapshot?
    private var pendingSnapshot:ScanSnapshot?
    private var regions:[Region]=[]
    private var codebook=CodeBook()
    private var codes:[ElementID:String]=[:]
    private var pages=LabelPages(geometry:[],codes:[:])
    private var page=0
    private var wholeWindow=false
    private var rowGroups:[RowActionGroup]=[]
    private var expandedRow:ElementID?
    private var screens:[Screen]=[]
    private var labelSize=Point(35,23)
    private var regionReservations:[Rect]=[]
    private var refreshWork:DispatchWorkItem?
    private var transitionWork:[DispatchWorkItem]=[]
    private var retryWork:DispatchWorkItem?
    private var warmWork:DispatchWorkItem?
    private var warmToken=Cancellation()
    private var backoff=RetryBackoff()
    private var recovery=TapRecovery()
    private var route:Point?
    private var endpoint:Endpoint?
    private var extentPending=false
    private var nextExtentTime=0.0
    private var shifted=false
    private var scrollIntentAt=0.0
    private var scrolling=false
    private var enteredAt=0.0
    private var firstRegion=false, firstLabels=false
    private var lastFullScan=0.0
    private var transitionSerial:UInt64=0
    private var refreshPlan=TransitionRefreshPlan()
    private var pendingRefresh=false
    private var scanStarted=0.0
    private var readyChanged:(()->Void)?
    init(preferences:Preferences) {
        self.preferences=preferences
        capture.handle={ [weak self] type,event in guard let self else { return false }; return self.queue.sync { self.event(type,event) } }
        capture.disabled={ [weak self] timeout,enabled in self?.queue.async { self?.tapDisabled(timeout:timeout,alreadyEnabled:enabled) } }
        poster.tick={ [weak self] in self?.pollEndpoint() }
    }
    func configure(_ preferences:Preferences) {
        queue.async {
            self.preferences=preferences; self.machine.automaticClick=preferences.automaticClick
            if !preferences.enabled { self.exit(); self.warmWork?.cancel() }
            else if self.machine.mode != .inactive { self.measureAndLayout() }
        }
    }
    func foregroundChanged(pid:pid_t) {
        queue.async {
            if self.machine.mode != .inactive,self.activePID == pid { return }
            self.exit(reason:"foreground_changed"); self.foregroundPID=pid; self.warmWork?.cancel()
            guard self.preferences.enabled, AXIsProcessTrusted(), pid != ProcessInfo.processInfo.processIdentifier else { return }
            let token=self.session
            self.warmToken.cancel(); let cancellation=Cancellation(); self.warmToken=cancellation
            let work=DispatchWorkItem { [weak self] in
                guard let self, self.session == token, self.preferences.enabled else { return }
                self.axQueue.async {
                    guard !cancellation.cancelled else { return }
                    let reader=SystemAXReader(pid:pid,registry:AXRegistry()); reader.prewarm()
                    guard !cancellation.cancelled else { return }
                    _=self.capture.prepare()
                    self.queue.async {
                        guard self.session == token,self.foregroundPID == pid else { return }
                        self.reader=reader
                    }
                }
                DispatchQueue.main.async { self.overlay.prepare(); self.updateScreenMetrics() }
            }
            self.warmWork=work; self.queue.asyncAfter(deadline:.now()+0.060,execute:work)
        }
    }
    func interrupted(resetScreens:Bool=false) { queue.async { self.exit(reason:"workspace_interrupted"); self.warmWork?.cancel(); if resetScreens { DispatchQueue.main.async { self.overlay.reset(); self.updateScreenMetrics() } } } }
    func shutdown() { queue.sync { self.exit(); self.capture.enable(false); self.warmWork?.cancel() } }
    func hotkey(toggle:Bool) {
        queue.async {
            guard self.preferences.enabled else { return }
            if self.machine.mode == .inactive { self.enter() }
            else if toggle { self.exit() }
        }
    }
    func reconnectCapture() { axQueue.async { _=self.capture.prepare() } }
    private func event(_ type:CGEventType,_ event:CGEvent) -> Bool {
        if [.leftMouseDown,.rightMouseDown,.otherMouseDown].contains(type) {
            if machine.mode == .navigation { expandedRow=nil; machine.cancelRowSelection(); invalidateGeometry(); planTransition(delay:0.140) }
            return false
        }
        if type == .flagsChanged { process(machine.flags(InputCapture.modifiers(event.flags))); return false }
        let code=UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let result=machine.key(code:code,down:type == .keyDown,repeat:event.getIntegerValueField(.keyboardEventAutorepeat) != 0,modifiers:InputCapture.modifiers(event.flags),time:ProcessInfo.processInfo.systemUptime)
        if result.effects.contains(where:{if case .scroll = $0 { return true }; return false}) { scrollIntentAt=ProcessInfo.processInfo.systemUptime }
        process(result.effects)
        if !machine.hasPrefix,let pending=pendingSnapshot,!scrolling,machine.mode == .navigation { pendingSnapshot=nil; accept(pending) }
        if !machine.hasPrefix,pendingRefresh,machine.mode == .navigation,!scrolling { pendingRefresh=false; scheduleRefresh(0) }
        drainTransitions()
        if machine.mode == .inactive && !machine.hasSwallowedKeys { capture.enable(false) }
        return result.swallow
    }
    private func process(_ effects:[Effect]) {
        for effect in effects {
            switch effect {
            case .enter: enter()
            case .exit: exit()
            case .input:
                Diagnostics.shared.record("input_mode",["session":session])
                expandedRow=nil
                stopScroll(); scanToken?.cancel(); scanning=false; layoutToken?.cancel(); retryWork?.cancel(); cancelRefreshes()
                actionToken.cancel(); actionToken=Cancellation()
                geometryValid=false; poster.restorePointer(); draw()
            case .resume: invalidateGeometry(); planTransition(delay:0)
            case .redraw: draw()
            case .refreshShortcut: expandedRow=nil; machine.cancelRowSelection(); invalidateGeometry(); planTransition(delay:0.220)
            case .rowActions:
                if expandedRow != nil {
                    expandedRow=nil; machine.cancelRowSelection(); poster.restorePointer()
                    invalidateGeometry(); planTransition(delay:0.140)
                } else {
                    if rowGroups.isEmpty || snapshot?.overlays.isEmpty == false { machine.cancelRowSelection() }
                    wholeWindow=false; page=0; pages.display=[]; syncButtons(); measureAndLayout()
                }
            case let .expandRow(id): expandRow(id)
            case let .scroll(direction,shift): shifted=shift; setScroll(direction:direction)
            case let .jump(top): jump(top:top)
            case let .selectRegion(id): selectRegion(id)
            case let .click(id,kind): click(id,kind:kind)
            case let .page(delta):
                if delta == 0 { expandedRow=nil; wholeWindow=true; page=0; measureAndLayout() }
                else if !pages.display.isEmpty { page=(page+delta+pages.display.count)%pages.display.count; syncButtons(); draw() }
            }
        }
    }
    private func enter() {
        guard preferences.enabled,foregroundPID != ProcessInfo.processInfo.processIdentifier else { machine.deactivate(); return }
        guard AXIsProcessTrusted() else {
            machine.deactivate(); DispatchQueue.main.async { Settings.shared.trusted=false; Settings.shared.status="请在辅助功能设置中允许 KeyPilot，再点“重新连接”。"; Settings.shared.show() }; return
        }
        if !capture.available { _=capture.prepare() }
        guard capture.available else { machine.deactivate(); DispatchQueue.main.async { Settings.shared.status="无法建立输入捕获，请确认辅助功能权限后重新连接。" }; return }
        session += 1; activePID=foregroundPID; machine.activate(); machine.automaticClick=preferences.automaticClick
        actionToken.cancel(); actionToken=Cancellation()
        machine.selectedRegion=nil; machine.regions=[]
        windowID=nil; regions=[]; snapshot=nil; codebook=CodeBook(); codes=[:]; pages=LabelPages(geometry:[],codes:[:]); page=0; wholeWindow=false
        rowGroups=[]; expandedRow=nil
        geometryValid=false; route=nil; firstRegion=false; firstLabels=false; enteredAt=ProcessInfo.processInfo.systemUptime; lastFullScan=0
        capture.enable(true); updateScreenMetricsOnMain(); startScan()
        Diagnostics.shared.record("navigation_enter")
    }
    private func exit(reason:String="requested") {
        if machine.mode != .inactive { Diagnostics.shared.record("navigation_exit",["reason":reason,"session":session,"mode":machine.mode.rawValue]) }
        warmToken.cancel()
        session += 1; scanToken?.cancel(); layoutToken?.cancel(); scanning=false; geometryValid=false
        actionToken.cancel()
        machine.deactivate(); stopScroll(); poster.restorePointer(); cancelRefreshes(); retryWork?.cancel(); retryWork=nil
        snapshot=nil; pendingSnapshot=nil; regions=[]; pages=LabelPages(geometry:[],codes:[:]); codes=[:]; codebook=CodeBook(); windowID=nil; backoff.reset()
        rowGroups=[]; expandedRow=nil
        if !machine.hasSwallowedKeys { capture.enable(false) }
        if let observation { self.observation=nil; axQueue.async { observation.stop() } }
        DispatchQueue.main.async { self.overlay.hide() }
    }
    private func cancelRefreshes() { refreshWork?.cancel(); refreshWork=nil; transitionWork.forEach{$0.cancel()}; transitionWork=[]; transitionSerial += 1; refreshPlan.cancel(); pendingRefresh=false }
    private func invalidateGeometry() {
        actionToken.cancel(); actionToken=Cancellation()
        geometryValid=false; route=nil; endpoint=nil; pages.display=[]; syncButtons(); stopScroll(clearIntent:false)
        scanToken?.cancel(); scanning=false; layoutToken?.cancel(); draw()
    }
    private func scheduleRefresh(_ delay:Double) {
        refreshWork?.cancel()
        let generation=session
        Diagnostics.shared.record("refresh_scheduled",["delay_ms":delay*1000,"session":session])
        let work=DispatchWorkItem { [weak self] in
            guard let self,self.session == generation,self.machine.mode == .navigation else { return }
            if self.scrolling || self.machine.hasPrefix { self.pendingRefresh=true; Diagnostics.shared.record("refresh_deferred",["scrolling":self.scrolling,"prefix":self.machine.hasPrefix]); return }
            if self.scanning { Diagnostics.shared.record("refresh_coalesced"); return }
            self.startScan()
        }
        refreshWork=work; queue.asyncAfter(deadline:.now()+delay,execute:work)
    }
    /// Two finite rediscoveries catch delayed deep content even when known ancestors do not change.
    private func planTransition(delay:Double) {
        transitionWork.forEach{$0.cancel()}; transitionWork=[]; transitionSerial += 1
        let serial=transitionSerial, generation=session, began=ProcessInfo.processInfo.systemUptime
        refreshPlan.replace(now:began)
        scheduleRefresh(delay)
        for delay in [0.650,1.500] {
            let work=DispatchWorkItem { [weak self] in self?.transitionDue(session:generation,serial:serial,deadline:began+delay) }
            transitionWork.append(work); queue.asyncAfter(deadline:.now()+delay,execute:work)
        }
    }
    private func transitionDue(session generation:UInt64,serial:UInt64,deadline:Double) {
        guard session == generation,transitionSerial == serial,machine.mode != .inactive else { return }
        drainTransitions()
    }
    private func drainTransitions() {
        if refreshPlan.takeDue(now:ProcessInfo.processInfo.systemUptime,canScan:machine.mode == .navigation && !scrolling && !scanning && !machine.hasPrefix,lastCompletedScanStarted:lastFullScan) { startScan() }
    }
    private func startScan() {
        guard machine.mode == .navigation,!scrolling,!scanning,!machine.hasPrefix else { return }
        scanning=true; scanNumber += 1
        Diagnostics.shared.record("scan_started",["session":session,"scan":scanNumber])
        actionToken.cancel(); actionToken=Cancellation()
        snapshot=nil; pendingSnapshot=nil
        geometryValid=false; pages.display=[]; syncButtons()
        scanStarted=ProcessInfo.processInfo.systemUptime
        let number=scanNumber,generation=session,pid=activePID,token=Cancellation()
        scanToken=token; retryWork?.cancel(); retryWork=nil
        let existingReader=reader
        axQueue.async {
            guard !token.cancelled else { return }
            let reader=(existingReader?.pid == pid ? existingReader:nil) ?? SystemAXReader(pid:pid,registry:AXRegistry())
            reader.begin()
            if let actual=reader.frontmostPID(),actual != pid {
                self.queue.async { guard self.session == generation,!token.cancelled else { return }; self.exit(reason:"keyboard_application_changed") }; return
            }
            guard let window=reader.currentWindow() else {
                self.queue.async { guard self.session == generation,self.scanNumber == number,!token.cancelled else { return }; self.scanning=false; self.windowUnavailable() }; return
            }
            self.queue.async {
                guard self.session == generation,!token.cancelled else { return }
                self.reader=reader; self.backoff.reset()
                if self.windowID != window.id {
                    if self.windowID != nil { self.machine.interruptScroll(); self.machine.clearPrefix(); self.machine.selectedRegion=nil }
                    self.expandedRow=nil; self.rowGroups=[]; self.machine.cancelRowSelection()
                    self.windowID=window.id; self.codebook=CodeBook(); self.codes=[:]; self.regions=[]; self.pages=LabelPages(geometry:[],codes:[:]); self.geometryValid=false; self.route=nil; self.wholeWindow=false
                }
            }
            let traversal=ScanTraversal(reader:reader,root:window.id,window:window.frame,additionalRoots:window.extras)
            self.scanSlice(traversal,reader:reader,window:window,token:token,generation:generation,number:number)
        }
    }
    private func scanSlice(_ traversal:ScanTraversal,reader:SystemAXReader,window:AXWindow,token:Cancellation,generation:UInt64,number:UInt64) {
        guard !token.cancelled else { return }
        let began=ProcessInfo.processInfo.systemUptime
        let result=traversal.step(cancelled:{token.cancelled})
        let local=max(0,ProcessInfo.processInfo.systemUptime-began)
        let axCalls=reader.calls,axSeconds=reader.ipcSeconds,resolutionSeconds=traversal.resolutionSeconds,dedupeSeconds=traversal.localSeconds,computationSeconds=traversal.computationSeconds
        guard !token.cancelled else { return }
        if result.final && result.exhaustive { reader.registry.prune(keeping:Set(result.nodes.keys).union([window.id])) }
        self.queue.async {
            guard self.session == generation,self.scanNumber == number,!token.cancelled,self.machine.mode == .navigation else { return }
            if result.final { self.scanning=false; self.lastFullScan=self.scanStarted }
            if self.machine.hasPrefix || self.scrolling { self.pendingSnapshot=result } else { self.accept(result) }
            if result.final {
                Diagnostics.shared.record("scan_complete",["nodes":result.count,"targets":result.targets.count,"regions":result.regions.count,"exhaustive":result.exhaustive,"ax_calls":axCalls,"ax_ms":axSeconds*1000,"scan_work_ms":result.workingSeconds*1000,"scan_local_ms":computationSeconds*1000,"region_resolution_ms":resolutionSeconds*1000,"target_dedupe_ms":dedupeSeconds*1000,"last_slice_total_ms":local*1000])
                self.installObservation(reader:reader,window:window.id,result:result,token:token,generation:generation)
                self.drainTransitions()
            }
        }
        if !result.final { axQueue.async { self.scanSlice(traversal,reader:reader,window:window,token:token,generation:generation,number:number) } }
    }
    private func accept(_ result:ScanSnapshot) {
        guard machine.mode == .navigation,!scrolling else { return }
        snapshot=result
        if machine.choosingRow,!result.overlays.isEmpty { machine.cancelRowSelection() }
        let previousSelection=machine.selectedRegion
        // A provisional window fallback is not a user-selected scrolling container.
        let provisional=regions.first(where:{$0.id == machine.selectedRegion})?.kind == .fallback && !firstRegion
        let selection=RegionSelection.resolve(previous:provisional ? nil:machine.selectedRegion,interacted:machine.interacted,regions:result.regions,final:result.final)
        machine.selectedRegion=selection.selected; geometryValid=selection.geometryValid
        if previousSelection != selection.selected || (result.final && expandedRow.map{result.nodes[$0] == nil} == true) { expandedRow=nil }
        if result.final {
            Diagnostics.shared.record("region_selection",["session":session,"scan":scanNumber,"regions":result.regions.count,"previous_retained":previousSelection != nil && result.regions.contains{$0.id == previousSelection},"selection_changed":previousSelection != selection.selected,"geometry_valid":geometryValid])
        }
        if !selection.preserveOldBorder { regions=result.regions }
        machine.regions=regions.map(\.id); route=nil; endpoint=nil
        if geometryValid && !firstRegion { firstRegion=true; Diagnostics.shared.record("first_region",["elapsed_ms":(ProcessInfo.processInfo.systemUptime-enteredAt)*1000]) }
        if machine.hasHeldScrollKeys && geometryValid { setScroll(direction:machine.scrollDirection); if scrolling { return } }
        measureAndLayout()
    }
    private func installObservation(reader:SystemAXReader,window:ElementID,result:ScanSnapshot,token:Cancellation,generation:UInt64) {
        let observer=AXObservation { [weak self] in self?.queue.async {
            guard let self,self.session == generation,self.windowID == window,self.machine.mode == .navigation else { return }
            if self.scrolling { return }
            self.invalidateGeometry(); self.planTransition(delay:0.120)
        } }
        let previous=observation; observation=observer
        axQueue.async { previous?.stop(); guard !token.cancelled else { return }; observer.install(reader:reader,window:window,nodes:result.nodes) }
        let known=Array(result.nodes.values.filter{$0.node.scroll || $0.node.listContainer || $0.node.landmarkContainer || $0.node.role == "AXSplitGroup"}.prefix(64))
        queue.asyncAfter(deadline:.now()+0.350) {
            guard self.session == generation,!self.scrolling,!self.scanning,self.machine.mode == .navigation else { return }
            self.checkKnown(known,index:0,reader:reader,generation:generation)
        }
    }
    private func checkKnown(_ nodes:[ScannedNode],index:Int,reader:SystemAXReader,generation:UInt64) {
        guard index < nodes.count else { return }
        axQueue.async {
            var changed=false,next=index
            let start=ProcessInfo.processInfo.systemUptime
            for item in nodes.dropFirst(index).prefix(8) {
                next += 1
                if let fresh=reader.readFresh(item.node.id) { changed = changed || fresh.frame != item.node.frame || fresh.childCount != item.node.childCount }
                else { changed=true }
                if ProcessInfo.processInfo.systemUptime-start >= 0.012 { break }
            }
            self.queue.async {
                guard self.session == generation,!self.scanning,!self.scrolling,self.machine.mode == .navigation else { return }
                if changed { self.invalidateGeometry(); self.scheduleRefresh(0) }
                else if next < nodes.count { self.checkKnown(nodes,index:next,reader:reader,generation:generation) }
            }
        }
    }
    private func windowUnavailable() {
        geometryValid=false; route=nil; pages.display=[]; syncButtons(); stopScroll(clearIntent:false); draw()
        let delay=backoff.next(),generation=session
        Diagnostics.shared.record("window_retry",["delay_ms":delay*1000])
        let work=DispatchWorkItem { [weak self] in guard let self,self.session == generation,self.machine.mode == .navigation else { return }; self.startScan() }
        retryWork=work; queue.asyncAfter(deadline:.now()+delay,execute:work)
    }
    private func selectRegion(_ id:ElementID) {
        expandedRow=nil; machine.cancelRowSelection()
        stopScroll(clearIntent:false); endpoint=nil; wholeWindow=false; page=0; route=nil
        machine.selectedRegion=id
        // Reuse only geometry confirmed by the currently running traversal.
        if scanning,let snapshot,snapshot.regions.contains(where:{$0.id == id}) { geometryValid=true; measureAndLayout(); setScroll(direction:machine.scrollDirection) }
        else { invalidateGeometry(); scheduleRefresh(0) }
    }
    private func setScroll(direction:Int) {
        Diagnostics.shared.record("scroll_intent",["direction":direction,"geometry_valid":geometryValid,"mode":machine.mode.rawValue,"session":session,"scanning":scanning,"was_scrolling":scrolling])
        if direction == 0 {
            let wasScrolling=scrolling; stopScroll(clearIntent:false); draw()
            if wasScrolling { scheduleRefresh(0.450) }
            return
        }
        guard machine.mode == .navigation,geometryValid,let region=regions.first(where:{$0.id == machine.selectedRegion}) else { return }
        expandedRow=nil; machine.cancelRowSelection()
        if !scrolling {
            if route == nil,let snapshot { route=ScrollRoute.point(in:region,snapshot:snapshot) }
            guard route != nil else { return }
            scanToken?.cancel(); scanning=false; layoutToken?.cancel(); refreshWork?.cancel(); pages.display=[]; syncButtons()
        }
        endpoint=nil; scrolling=true
        poster.scroll(direction:direction,speed:preferences.speed*(shifted ? preferences.acceleration:1),point:route ?? region.frame.center,intentAt:scrollIntentAt)
        draw(); pollEndpoint()
    }
    private func stopScroll(clearIntent:Bool=false) {
        poster.stop(); scrolling=false; endpoint=nil
        if clearIntent { machine.interruptScroll() }
    }
    private func pollEndpoint() {
        let now=ProcessInfo.processInfo.systemUptime
        guard scrolling,!extentPending,now >= nextExtentTime,let reader,let id=machine.selectedRegion else { return }
        extentPending=true; nextExtentTime=now+0.200
        let generation=session,direction=machine.scrollDirection
        axQueue.async {
            let extent=reader.extent(region:id)
            self.queue.async {
                self.extentPending=false
                guard self.session == generation,self.scrolling,self.machine.selectedRegion == id,self.machine.scrollDirection == direction else { return }
                if extent == nil { self.nextExtentTime=ProcessInfo.processInfo.systemUptime+1 }
                let edge=extent?.endpoint(direction:direction)
                if self.endpoint != edge { self.endpoint=edge; self.draw() }
            }
        }
    }
    private func jump(top:Bool) {
        guard geometryValid,let reader,let region=regions.first(where:{$0.id == machine.selectedRegion}),let window=windowID else { return }
        let generation=session,action=actionToken
        expandedRow=nil; machine.cancelRowSelection()
        stopScroll(clearIntent:true); pages.display=[]; syncButtons(); draw()
        axQueue.async {
            guard !action.cancelled,reader.frontmostMatches(),reader.currentWindow(includeExtras:false)?.id == window,let fresh=reader.readFresh(region.id)?.frame,fresh.intersection(region.frame).area > 1,!action.cancelled else { return }
            let moved=reader.jump(region:region.id,top:top)
            self.queue.async {
                guard self.session == generation,!action.cancelled,self.machine.mode == .navigation,self.geometryValid else { return }
                if !moved,let snapshot=self.snapshot {
                    var live=region; live.frame=region.frame.intersection(fresh)
                    if let point=ScrollRoute.point(in:live,snapshot:snapshot) { self.poster.jump(top:top,point:point) }
                }
                self.invalidateGeometry(); self.planTransition(delay:0.140)
            }
        }
    }
    private func click(_ id:ElementID,kind:ClickKind) {
        guard geometryValid,!scrolling,let reader,let window=windowID,
              let target=currentPlacements().first(where:{$0.target.id == id})?.target,target.purpose == .control else { return }
        let generation=session,number=scanNumber,clippingRegions=Set(regions.map(\.id))
        stopScroll(clearIntent:false)
        axQueue.async {
            let point=reader.validatedHit(target:target,window:window,clippingRegions:clippingRegions)
            self.queue.async {
                guard self.session == generation,self.scanNumber == number,self.machine.mode == .navigation,self.geometryValid else { return }
                if let point { self.poster.click(point:point,kind:kind) }
                else { Diagnostics.shared.record("click_rejected_stale") }
                self.invalidateGeometry(); self.planTransition(delay:0.140)
            }
        }
    }
    private func expandRow(_ anchor:ElementID) {
        guard geometryValid,!scrolling,let reader,let window=windowID,
              currentPlacements().contains(where:{$0.target.id == anchor}),
              let group=rowGroups.first(where:{$0.anchor.id == anchor}) else { return }
        let generation=session,number=scanNumber,action=actionToken,clippingRegions=Set(regions.map(\.id))
        stopScroll(clearIntent:true); pages.display=[]; syncButtons(); draw()
        axQueue.async {
            guard !action.cancelled else { return }
            let point=reader.validatedHover(target:group.row,window:window,clippingRegions:clippingRegions)
            self.queue.async {
                guard self.session == generation,self.scanNumber == number,!action.cancelled,
                      self.machine.mode == .navigation,self.geometryValid,!self.scrolling,!self.machine.hasHeldScrollKeys else { return }
                if let point { self.expandedRow=group.row.id; self.poster.hover(point:point) }
                else { Diagnostics.shared.record("row_hover_rejected_stale") }
                self.invalidateGeometry(); self.planTransition(delay:0.140)
            }
        }
    }
    private func measureAndLayout() {
        guard machine.mode == .navigation,!scrolling,!machine.hasPrefix,let snapshot else { draw(); return }
        let generation=session,number=scanNumber
        let priorBook=codebook,previous=pages.geometry,regions=self.regions,selected=machine.selectedRegion,prefs=preferences,wholeWindow=self.wholeWindow
        let expanded=self.expandedRow,choosing=machine.choosingRow
        layoutNumber += 1; let layoutID=layoutNumber
        layoutToken?.cancel(); let token=Cancellation(); layoutToken=token
        DispatchQueue.main.async {
            guard !token.cancelled else { return }
            let font=NSFont.monospacedSystemFont(ofSize:prefs.fontSize,weight:.semibold)
            let size=Point(("SSS" as NSString).size(withAttributes:[.font:font]).width+10,prefs.fontSize+10)
            let labels=Dictionary(uniqueKeysWithValues:RegionCodes.group(regions:regions.map(\.id),selected:selected))
            let screens=OverlayManager.screenModels
            let reserved=Array(OverlayCanvas.regionLabelRects(regions,labels:labels,fontSize:prefs.fontSize,screens:screens).values)
            self.layoutQueue.async {
                guard !token.cancelled else { return }
                let scoped=TargetScope.filter(snapshot.targets,regions:snapshot.regions,selected:selected,wholeWindow:wholeWindow,overlays:snapshot.overlays)
                let groupingStart=ProcessInfo.processInfo.systemUptime
                let disclosure=RowDisclosure(targets:scoped,nodes:snapshot.nodes,regions:snapshot.regions)
                let groupingMS=(ProcessInfo.processInfo.systemUptime-groupingStart)*1000
                let presented=TargetScope.filter(disclosure.presented(scoped,fold:prefs.foldRowActions,expanded:expanded,choosing:choosing,all:wholeWindow),regions:snapshot.regions,selected:selected,wholeWindow:wholeWindow,overlays:snapshot.overlays)
                let unoccluded=TargetScope.filter(snapshot.targets,regions:snapshot.regions,selected:selected,wholeWindow:true,overlays:snapshot.overlays).count
                let codeStart=ProcessInfo.processInfo.systemUptime
                var book=priorBook
                let allCodes=book.publish(ids:presented.map(\.id),alive:Set(snapshot.nodes.keys),final:snapshot.final,exhaustive:snapshot.exhaustive)
                let codeMS=(ProcessInfo.processInfo.systemUptime-codeStart)*1000
                let available=presented.filter{allCodes[$0.id] != nil}
                let began=ProcessInfo.processInfo.systemUptime
                let geometry=LabelLayout.layout(targets:available,screens:screens,reserved:reserved,size:size,previous:previous,cancelled:{token.cancelled})
                let pages=LabelPages(geometry:geometry,codes:allCodes)
                let layoutMS=(ProcessInfo.processInfo.systemUptime-began)*1000
                self.queue.async {
                    guard self.session == generation,self.scanNumber == number,self.layoutNumber == layoutID,!token.cancelled,!self.scrolling,self.machine.mode == .navigation else { return }
                    guard !self.machine.hasPrefix else { self.pendingSnapshot=snapshot; return }
                    self.codebook=book; self.codes=allCodes; self.pages=pages; self.screens=screens; self.labelSize=size; self.regionReservations=reserved
                    self.rowGroups=disclosure.groups
                    if choosing,disclosure.groups.isEmpty { self.machine.cancelRowSelection() }
                    self.page=min(self.page,max(0,pages.display.count-1)); self.syncButtons()
                    let first = !self.firstLabels && !pages.display.isEmpty
                    self.draw(milestones:(first ? ["first_labels_drawn"]:[]) + (snapshot.final ? ["all_labels_drawn"]:[]))
                    Diagnostics.shared.record("codes",["count":allCodes.count,"ms":codeMS])
                    Diagnostics.shared.record("layout",["ms":layoutMS,"candidates":available.count,"geometry_pages":geometry.count,"display_pages":pages.display.count])
                    let presentedIDs=Set(presented.map(\.id))
                    Diagnostics.shared.record("coverage",["session":generation,"scan":number,"final":snapshot.final,"regions":snapshot.regions.count,"selected_owned":scoped.filter{$0.id == selected || $0.ancestors.contains(where:{$0 == selected})}.count,"discovered":snapshot.targets.count,"occluded":snapshot.targets.count-unoccluded,"scope_hidden":unoccluded-scoped.count,"waiting_for_final":presented.count-available.count,"current_page":self.page+1,"visible_on_page":self.currentPlacements().count,"scan_exhaustive":snapshot.exhaustive,"row_groups":disclosure.groups.count,"row_actions_folded":scoped.filter{!presentedIDs.contains($0.id)}.count,"visual_unknown":scoped.filter{$0.visualVisibility == .unknown}.count,"choosing_row":choosing,"row_expanded":expanded != nil])
                    if snapshot.final {
                        var grouping:[String:Any]=["session":generation,"scan":number,"ms":groupingMS,"candidates":disclosure.candidateCount,"semantic":disclosure.groups.filter{$0.kind == .semantic}.count,"primary":disclosure.groups.filter{$0.kind == .primary}.count,"repeated":disclosure.groups.filter{$0.kind == .repeated}.count,"peers":disclosure.groups.filter{$0.kind == .peers}.count,"action_candidates":disclosure.actionCount,"actions_unassigned":disclosure.unassignedActionCount,"fold_enabled":prefs.foldRowActions,"all_targets":wholeWindow]
                        grouping.merge(disclosure.structureCounts.mapValues{$0 as Any}){_,new in new}
                        Diagnostics.shared.record("row_grouping",grouping)
                    }
                    if !self.firstLabels,!pages.display.isEmpty { self.firstLabels=true; Diagnostics.shared.record("first_labels",["elapsed_ms":(ProcessInfo.processInfo.systemUptime-self.enteredAt)*1000]) }
                    if snapshot.final { Diagnostics.shared.record("all_labels",["elapsed_ms":(ProcessInfo.processInfo.systemUptime-self.enteredAt)*1000,"exhaustive":snapshot.exhaustive]) }
                }
            }
        }
        draw() // Region geometry can appear before button layout finishes.
    }
    private func currentPlacements() -> [Placement] { pages.display.indices.contains(page) ? pages.display[page]:[] }
    private func syncButtons() {
        machine.buttons=currentPlacements().compactMap{ p in codes[p.target.id].map{(p.target.id,$0)} }
        machine.expandableRows=Set(rowGroups.map{$0.anchor.id})
        machine.disclosureTargets=Set(currentPlacements().filter{$0.target.purpose == .rowDisclosure}.map{$0.target.id})
    }
    private func draw(milestones:[String]=[]) {
        guard machine.mode != .inactive else { return }
        let state=OverlayFrame(regions:regions,selected:machine.selectedRegion,regionLabels:Dictionary(uniqueKeysWithValues:RegionCodes.group(regions:regions.map(\.id),selected:machine.selectedRegion)),placements:scrolling ? []:currentPlacements(),codes:codes,buttonPrefix:machine.buttonPrefix,regionPrefix:machine.regionPrefix,selectedButton:machine.selectedButton,mode:machine.mode,endpoint:endpoint,preferences:preferences)
        let generation=session,started=enteredAt
        DispatchQueue.main.async {
            // Display requests preserve queue ordering; a later exit always enqueues hide after these.
            let start=ProcessInfo.processInfo.systemUptime; self.overlay.show(state)
            Diagnostics.shared.record("publish",["session":generation,"ms":(ProcessInfo.processInfo.systemUptime-start)*1000,"labels":state.placements.count])
            for milestone in milestones { Diagnostics.shared.record(milestone,["session":generation,"elapsed_ms":(ProcessInfo.processInfo.systemUptime-started)*1000,"labels":state.placements.count]) }
        }
    }
    private func updateScreenMetricsOnMain() { DispatchQueue.main.async { self.updateScreenMetrics() } }
    private func updateScreenMetrics() { let models=OverlayManager.screenModels; queue.async { self.screens=models } }
    private func tapDisabled(timeout:Bool,alreadyEnabled:Bool) {
        // Intentional idle disable notifications must not recursively disable the tap again.
        guard TapRecovery.shouldHandleDisabledEvent(mode:machine.mode,currentlyEnabled:alreadyEnabled) else { return }
        stopScroll(clearIntent:true); machine.resetPairing()
        let generation=session
        DispatchQueue.main.async {
            let actual=NSWorkspace.shared.frontmostApplication?.processIdentifier, trusted=AXIsProcessTrusted()
            self.queue.async {
                guard self.session == generation,self.machine.mode != .inactive,!self.capture.enabled else { return }
                if self.recovery.shouldRecover(now:ProcessInfo.processInfo.systemUptime,alreadyEnabled:false,timeout:timeout,sameSession:actual == self.activePID,trusted:trusted) {
                    self.capture.enable(true)
                    if self.capture.enabled { Diagnostics.shared.record("tap_recovered"); if self.machine.mode == .navigation { self.scheduleRefresh(0.120) }; return }
                }
                self.exit(reason:"tap_disabled"); self.capture.enable(false); Diagnostics.shared.record("tap_released")
            }
        }
    }
}
