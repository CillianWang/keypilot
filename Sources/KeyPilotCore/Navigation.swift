import Foundation

public enum Mode: String, Sendable { case inactive, navigation, input }
public struct Modifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let shift = Modifiers(rawValue:1)
    public static let command = Modifiers(rawValue:2)
    public static let option = Modifiers(rawValue:4)
    public static let control = Modifiers(rawValue:8)
    public var applicationShortcut: Bool { !intersection([.command,.option,.control]).isEmpty }
}
public enum Key: UInt16, CaseIterable, Sendable {
    case a=0, s=1, d=2, f=3, h=4, g=5, j=38, k=40, l=37, w=13, e=14, r=15, i=34
    case space=49, escape=53, tab=48, enter=36, backspace=51, leftBracket=33, rightBracket=30
    case up=126, down=125, home=115, end=119, semicolon=41
    public var letter: String? {
        switch self {
        case .a:return "A"; case .s:return "S"; case .d:return "D"; case .f:return "F"
        case .h:return "H"; case .g:return "G"; case .j:return "J"; case .k:return "K"
        case .l:return "L"; case .w:return "W"; case .e:return "E"; case .r:return "R"
        default:return nil
        }
    }
}
public enum ClickKind: String, Sendable { case left, right, command }
public enum Effect: Equatable, Sendable {
    case enter, exit, input, resume, redraw, refreshShortcut, rowActions
    case expandRow(ElementID)
    case scroll(Int, Bool), jump(Bool), selectRegion(ElementID), click(ElementID, ClickKind), page(Int)
}
public struct KeyResult: Equatable, Sendable {
    public var swallow: Bool
    public var effects: [Effect]
    public init(_ swallow: Bool, _ effects: [Effect] = []) { self.swallow=swallow; self.effects=effects }
}

public enum RegionCodes {
    public static let long = ["WW","EE","RR","WE","ER","RW","WR","EW","RE"]
    public static func labels(count: Int) -> [String] { count <= 3 ? Array(["W","E","R"].prefix(count)) : Array(long.prefix(min(9,count))) }
    public static func group(regions: [ElementID], selected: ElementID?) -> [(ElementID,String)] {
        let start = ((selected.flatMap { regions.firstIndex(of:$0) } ?? 0) / 9) * 9
        let ids = Array(regions.dropFirst(start).prefix(9))
        return Array(zip(ids, labels(count:ids.count)))
    }
}

/// Owns each down/up pair even when I/Esc changes modes halfway through a physical press.
public struct NavigationMachine {
    public private(set) var mode: Mode = .inactive
    public private(set) var buttonPrefix = ""
    public private(set) var regionPrefix = ""
    public private(set) var selectedButton: ElementID?
    public var selectedRegion: ElementID?
    public var regions: [ElementID] = []
    public var buttons: [(id: ElementID, code: String)] = []
    public var automaticClick = true
    public private(set) var choosingRow = false
    public var expandableRows:Set<ElementID> = []
    public var disclosureTargets:Set<ElementID> = []
    public private(set) var interacted = false
    private var owners: [UInt16:Bool] = [:]
    private var scrollingKeys: Set<Key> = []
    private var lastG: Double?
    private var shifted = false
    public init() {}
    public var hasPrefix: Bool { !buttonPrefix.isEmpty || !regionPrefix.isEmpty }
    public var scrollDirection: Int { (scrollingKeys.contains(.j) ? 1:0) - (scrollingKeys.contains(.k) ? 1:0) }
    public var hasHeldScrollKeys: Bool { !scrollingKeys.isEmpty }
    public var hasSwallowedKeys: Bool { owners.values.contains(true) }
    public mutating func activate() {
        mode = .navigation; clearPrefix(); interacted=false; selectedButton=nil; scrollingKeys=[]; lastG=nil; choosingRow=false
    }
    public mutating func deactivate() {
        mode = .inactive; clearPrefix(); scrollingKeys=[]; selectedButton=nil; lastG=nil; choosingRow=false
        // Do not discard pair ownership: captured releases must remain paired during teardown.
    }
    public mutating func clearPrefix() { buttonPrefix=""; regionPrefix="" }
    public mutating func cancelRowSelection() { choosingRow=false; clearPrefix(); selectedButton=nil }
    private var activeButtons:[(id:ElementID,code:String)] { choosingRow ? buttons.filter{expandableRows.contains($0.id)}:buttons }
    private mutating func activateTarget(_ id:ElementID,kind:ClickKind) -> KeyResult {
        if choosingRow || disclosureTargets.contains(id) {
            guard expandableRows.contains(id) else { return KeyResult(true) }
            cancelRowSelection(); interacted=true
            return KeyResult(true,[.expandRow(id)])
        }
        interacted=true; clearPrefix(); return KeyResult(true,[.click(id,kind)])
    }
    public mutating func interruptScroll() { scrollingKeys=[]; lastG=nil }
    public mutating func resetPairing() { owners=[:] }
    public mutating func flags(_ flags: Modifiers) -> [Effect] {
        shifted = flags.contains(.shift)
        return mode == .navigation && hasHeldScrollKeys ? [.scroll(scrollDirection,shifted)] : []
    }
    public mutating func key(code: UInt16, down: Bool, repeat isRepeat: Bool = false, modifiers: Modifiers = [], time: Double) -> KeyResult {
        guard down else {
            let swallowed = owners.removeValue(forKey:code) ?? false
            if let key=Key(rawValue:code), scrollingKeys.remove(key) != nil {
                return KeyResult(swallowed,[.scroll(scrollDirection,modifiers.contains(.shift))])
            }
            return KeyResult(swallowed)
        }
        if let owner=owners[code] { return KeyResult(owner) }
        if isRepeat { return KeyResult(mode == .navigation) }
        let result = handleDown(code:code, modifiers:modifiers, time:time)
        owners[code] = result.swallow
        return result
    }
    private mutating func handleDown(code:UInt16, modifiers:Modifiers, time:Double) -> KeyResult {
        let key = Key(rawValue:code)
        if modifiers.intersection([.shift,.command,.option,.control]) == [.shift,.command], key == .space || key == .j {
            if mode == .inactive { activate(); return KeyResult(true,[.enter]) }
            if key == .space { deactivate(); return KeyResult(true,[.exit]) }
            return KeyResult(true)
        }
        guard mode != .inactive else { return KeyResult(false) }
        if key == .escape {
            if mode == .input { mode = .navigation; clearPrefix(); return KeyResult(true,[.resume]) }
            deactivate(); return KeyResult(true,[.exit])
        }
        if mode == .input { return KeyResult(false) }
        if key == .enter && !modifiers.contains(.option) && !modifiers.contains(.control) {
            guard regionPrefix.isEmpty else { return KeyResult(true) }
            if !buttonPrefix.isEmpty && !activeButtons.contains(where:{$0.code == buttonPrefix}) { return KeyResult(true) }
            guard let target=selectedButton ?? (buttonPrefix.isEmpty ? activeButtons.first?.id : nil), activeButtons.contains(where:{$0.id == target}) else { return KeyResult(true) }
            return activateTarget(target,kind:modifiers.contains(.command) ? .command : modifiers.contains(.shift) ? .right : .left)
        }
        if modifiers.applicationShortcut { interacted=true; return KeyResult(false,[.refreshShortcut]) }
        switch key {
        case .semicolon:
            choosingRow.toggle(); clearPrefix(); selectedButton=nil; scrollingKeys=[]; lastG=nil; interacted=true
            return KeyResult(true,[.scroll(0,false),.rowActions])
        case .i:
            mode = .input; cancelRowSelection(); scrollingKeys=[]; lastG=nil
            return KeyResult(true,[.scroll(0,false),.input])
        case .tab:
            guard !regions.isEmpty else { return KeyResult(true) }
            let idx = regions.firstIndex(of:selectedRegion ?? 0) ?? 0
            let next = (idx + (modifiers.contains(.shift) ? regions.count-1:1)) % regions.count
            selectedRegion=regions[next]; interacted=true; cancelRowSelection()
            return KeyResult(true,[.selectRegion(regions[next])])
        case .space:
            cancelRowSelection(); interacted=true; return KeyResult(true,[.page(0)])
        case .backspace:
            if !regionPrefix.isEmpty { regionPrefix.removeLast() } else if !buttonPrefix.isEmpty { buttonPrefix.removeLast() }
            return KeyResult(true,[.redraw])
        case .leftBracket, .rightBracket:
            clearPrefix(); interacted=true; return KeyResult(true,[.page(key == .leftBracket ? -1:1)])
        case .up, .down:
            guard !activeButtons.isEmpty else { return KeyResult(true) }
            let idx = activeButtons.firstIndex { $0.id == selectedButton } ?? (key == .down ? -1:0)
            selectedButton=activeButtons[(idx + (key == .up ? activeButtons.count-1:1)) % activeButtons.count].id
            clearPrefix(); interacted=true; return KeyResult(true,[.redraw])
        case .w, .e, .r:
            choosingRow=false; buttonPrefix=""; regionPrefix += key!.letter!
            let codes=RegionCodes.group(regions:regions, selected:selectedRegion)
            if let match=codes.first(where:{$0.1 == regionPrefix}) {
                selectedRegion=match.0; clearPrefix(); interacted=true
                return KeyResult(true,[.selectRegion(match.0)])
            }
            if !codes.contains(where:{$0.1.hasPrefix(regionPrefix)}) { regionPrefix=key!.letter! }
            return KeyResult(true,[.redraw])
        default: break
        }
        if !regionPrefix.isEmpty { return KeyResult(true) }
        if buttonPrefix.isEmpty {
            switch key {
            case .j, .k:
                choosingRow=false; scrollingKeys.insert(key!); shifted=modifiers.contains(.shift); interacted=true; lastG=nil
                return KeyResult(true,[.scroll(scrollDirection,shifted)])
            case .g:
                interacted=true
                if modifiers.contains(.shift) { lastG=nil; return KeyResult(true,[.jump(false)]) }
                if let previous=lastG, time-previous < 0.7 { lastG=nil; return KeyResult(true,[.jump(true)]) }
                lastG=time; return KeyResult(true)
            case .home, .end: interacted=true; return KeyResult(true,[.jump(key == .home)])
            default: lastG=nil
            }
        }
        guard let letter=key?.letter, "SADF HJKLG".contains(letter) else { return KeyResult(true) }
        buttonPrefix += letter
        let matches=activeButtons.filter { $0.code.hasPrefix(buttonPrefix) }
        if let exact=matches.first(where:{$0.code == buttonPrefix}) {
            selectedButton=exact.id; interacted=true
            if automaticClick { return activateTarget(exact.id,kind:.left) }
        } else if matches.isEmpty { buttonPrefix="" }
        return KeyResult(true,[.redraw])
    }
}

public struct RetryBackoff {
    private var index=0
    public init() {}
    public mutating func next() -> Double { let values=[0.1,0.2,0.4,0.8,1.6,2.0]; defer { index=min(index+1,5) }; return values[index] }
    public mutating func reset() { index=0 }
}

public struct TapRecovery {
    private var attempts:[Double]=[]
    public init() {}
    public static func shouldHandleDisabledEvent(mode:Mode,currentlyEnabled:Bool) -> Bool { mode != .inactive && !currentlyEnabled }
    public mutating func shouldRecover(now:Double, alreadyEnabled:Bool, timeout:Bool, sameSession:Bool, trusted:Bool) -> Bool {
        guard !alreadyEnabled, timeout, sameSession, trusted else { return false }
        attempts.removeAll { now-$0 >= 10 }
        guard attempts.count < 2 else { return false }
        attempts.append(now); return true
    }
}
