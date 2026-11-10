import Foundation

public struct RegionSelection {
    public var selected:ElementID?
    public var geometryValid:Bool
    public var preserveOldBorder:Bool
    public static func resolve(previous:ElementID?,interacted:Bool,regions:[Region],final:Bool) -> RegionSelection {
        let retained=regions.first{$0.id == previous}
        if previous != nil && retained == nil && !final && interacted { return RegionSelection(selected:previous,geometryValid:false,preserveOldBorder:true) }
        let selected = interacted && retained != nil ? retained:regions.max{$0.frame.area < $1.frame.area}
        return RegionSelection(selected:selected?.id,geometryValid:selected != nil && (selected?.kind != .fallback || final),preserveOldBorder:false)
    }
}

/// Finite deadlines, not a polling timer. Deferred work is reconsidered only on a meaningful state change.
public struct TransitionRefreshPlan {
    public private(set) var deadlines:[Double]=[]
    public init() {}
    public mutating func replace(now:Double) { deadlines=[now+0.650,now+1.500] }
    public mutating func cancel() { deadlines=[] }
    public mutating func takeDue(now:Double,canScan:Bool,lastCompletedScanStarted:Double) -> Bool {
        deadlines.removeAll{$0 <= lastCompletedScanStarted}
        guard canScan,deadlines.contains(where:{$0 <= now}) else { return false }
        deadlines.removeAll{$0 <= now}; return true
    }
}
