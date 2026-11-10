import Foundation

/// Session/window scoped. Published labels are immutable; conflicts are resolved only by paging.
public struct CodeBook {
    public static let heads=Array("SADFHL").map(String.init)
    public static let tails=Array("SADFHJKLG").map(String.init)
    public static let repeats=["SS","AA","DD","FF","HH","LL"]
    public private(set) var mapping: [ElementID:String]=[:]
    private var previews=0
    public init() {}
    public static func conflict(_ a:String,_ b:String) -> Bool { a.hasPrefix(b) || b.hasPrefix(a) }
    public mutating func publish(ids:[ElementID], alive:Set<ElementID>, final:Bool, exhaustive:Bool) -> [ElementID:String] {
        if final && exhaustive { mapping=mapping.filter { alive.contains($0.key) } }
        let missing=ids.filter { mapping[$0] == nil }
        if !final {
            for id in missing {
                guard previews < 6, let code=Self.repeats.first(where:{ c in !mapping.values.contains(where:{Self.conflict(c,$0)}) }) else { break }
                mapping[id]=code; previews += 1
            }
        } else {
            assign(missing, visible:Set(ids))
        }
        let visible=Set(ids)
        return mapping.filter { visible.contains($0.key) }
    }
    private mutating func assign(_ ids:[ElementID], visible:Set<ElementID>) {
        var remaining=ids
        while !remaining.isEmpty {
            var pool=Self.pool(occupied:Array(mapping.values), demand:remaining.count)
            if pool.isEmpty {
                // Window space exhausted: first reuse codes hidden by the current scope.
                let inScope=mapping.filter { visible.contains($0.key) }.map(\.value)
                pool=Self.pool(occupied:inScope, demand:remaining.count)
            }
            if pool.isEmpty { pool=Self.pool(occupied:[], demand:min(remaining.count,486)) }
            guard !pool.isEmpty else { return }
            var counts=Dictionary(uniqueKeysWithValues:Self.heads.map { head in (head,mapping.values.filter{$0.hasPrefix(head)}.count) })
            while !remaining.isEmpty && !pool.isEmpty {
                let repeated=Self.repeats.first { pool.contains($0) }
                let chosen=repeated ?? pool.min { a,b in
                    let ah=String(a.prefix(1)), bh=String(b.prefix(1))
                    if counts[ah,default:0] != counts[bh,default:0] { return counts[ah,default:0] < counts[bh,default:0] }
                    if ah != bh { return Self.heads.firstIndex(of:ah)! < Self.heads.firstIndex(of:bh)! }
                    if a.count != b.count { return a.count < b.count }
                    let ar=Self.repeatRank(a), br=Self.repeatRank(b)
                    if ar != br { return ar < br }
                    return Self.order(a) < Self.order(b)
                }!
                mapping[remaining.removeFirst()]=chosen
                counts[String(chosen.prefix(1)),default:0] += 1
                pool.removeAll { Self.conflict($0,chosen) }
            }
        }
    }
    private static func repeatRank(_ code:String) -> Int {
        let chars=Array(code)
        if Set(chars).count == 1 { return 0 }
        if chars.count == 3 && chars[1] == chars[2] { return 1 }
        return 2
    }
    private static func order(_ code:String) -> Int {
        Array(code).reduce(0) { $0*10+(tails.firstIndex(of:String($1)) ?? 9) }
    }
    private static func pool(occupied:[String], demand:Int) -> [String] {
        var available:[String]=[]
        for head in heads {
            for tail in tails {
                let branch=head+tail
                if occupied.contains(branch) { continue }
                if occupied.contains(where:{$0.hasPrefix(branch)}) {
                    available += tails.map { branch+$0 }.filter { c in !occupied.contains(where:{conflict(c,$0)}) }
                } else { available.append(branch) }
            }
        }
        // Reserve exactly the needed unpublished branches before issuing any of their short codes.
        var expandCounts=Dictionary(uniqueKeysWithValues:heads.map { ($0,0) })
        while available.count < demand {
            let expandable=available.filter{$0.count == 2}
            guard let branch=expandable.min(by:{ a,b in
                let ah=String(a.prefix(1)),bh=String(b.prefix(1))
                if repeats.contains(a) != repeats.contains(b) { return !repeats.contains(a) }
                if expandCounts[ah,default:0] != expandCounts[bh,default:0] { return expandCounts[ah,default:0] < expandCounts[bh,default:0] }
                return order(a) < order(b)
            }) else { break }
            available.removeAll{$0 == branch}; available += tails.map{branch+$0}
            expandCounts[String(branch.prefix(1)),default:0] += 1
        }
        return available
    }
}

public struct Placement: Equatable, Sendable {
    public var target:Target
    public var rect:Rect
    public var screen:UInt32
    public var leader:Bool
    public init(target:Target, rect:Rect, screen:UInt32) {
        self.target=target; self.rect=rect; self.screen=screen; leader = !target.frame.contains(rect.center)
    }
}
public struct LabelPages: Sendable {
    /// Never overwrite these with code-conflict pages.
    public var geometry:[[Placement]]
    public var display:[[Placement]]
    public init(geometry:[[Placement]], codes:[ElementID:String]) {
        self.geometry=geometry; display=[]
        for page in geometry {
            var split:[[Placement]]=[]
            for item in page where codes[item.target.id] != nil {
                let code=codes[item.target.id]!
                if let i=split.firstIndex(where:{ group in !group.contains { CodeBook.conflict(codes[$0.target.id]!,code) } }) { split[i].append(item) }
                else { split.append([item]) }
            }
            display += split
        }
    }
}

private struct Occupancy {
    var rects:[Rect]=[]
    var buckets:[Int64:[Int]]=[:]
    func cells(_ r:Rect) -> [Int64] {
        guard r.valid else { return [] }
        let x1=Int(floor(r.x/64)), x2=Int(floor(r.maxX/64)), y1=Int(floor(r.y/64)), y2=Int(floor(r.maxY/64))
        return (x1...x2).flatMap{x in (y1...y2).map{y in (Int64(x)<<32) ^ Int64(UInt32(bitPattern:Int32(y)))}}
    }
    mutating func insert(_ r:Rect) { let i=rects.count; rects.append(r); for c in cells(r) { buckets[c,default:[]].append(i) } }
    func overlaps(_ r:Rect) -> Bool { cells(r).contains { c in buckets[c,default:[]].contains { rects[$0].intersects(r.inset(-2)) } } }
}

public enum LabelLayout {
    public static func layout(targets:[Target], screens:[Screen], reserved:[Rect], size:Point, previous:[[Placement]] = [], cancelled:() -> Bool = {false}) -> [[Placement]] {
        var pages:[[Placement]]=[], occupied:[Occupancy]=[]
        let old=Dictionary(previous.flatMap{$0}.map{($0.target.id,$0)},uniquingKeysWith:{$1})
        // Small controls first, then let wide rows find space inside their own hit rectangle.
        let ordered=targets.sorted { a,b in a.frame.area == b.frame.area ? a.id < b.id : a.frame.area < b.frame.area }
        for target in ordered {
            if cancelled() { return [] }
            guard let screen=Screen.owner(of:target.frame,screens:screens) else { continue }
            let bounds=screen.frame.inset(2)
            var candidates:[Rect]=[]
            func add(_ x:Double,_ y:Double) {
                let r=Rect(max(bounds.x,min(bounds.maxX-size.x,x)),max(bounds.y,min(bounds.maxY-size.y,y)),size.x,size.y)
                if r.valid { candidates.append(r) }
            }
            if let prior=old[target.id], prior.target.frame.near(target.frame) { candidates.append(prior.rect) }
            let row=target.frame.intersection(screen.frame)
            add(row.x+2,row.y+max(0,(row.height-size.y)/2))
            if row.width > size.x*2 {
                let span=max(0,row.width-size.x-4)
                let steps=min(16,max(1,Int(span/(size.x+4))))
                for i in 1...steps { add(row.x+2+span*Double(i)/Double(steps),row.y+max(0,(row.height-size.y)/2)) }
                add(row.maxX-size.x-2,row.y+max(0,(row.height-size.y)/2))
            }
            for radius in stride(from:8.0,through:56.0,by:8) {
                for (dx,dy) in [(0.0,-1.0),(0,1),(-1,0),(1,0),(-0.7,-0.7),(0.7,-0.7),(-0.7,0.7),(0.7,0.7)] {
                    add(row.center.x-size.x/2+dx*radius,row.center.y-size.y/2+dy*radius)
                }
            }
            var placed=false
            for page in pages.indices {
                if let rect=candidates.first(where:{!occupied[page].overlaps($0)}) {
                    pages[page].append(Placement(target:target,rect:rect,screen:screen.id)); occupied[page].insert(rect); placed=true; break
                }
            }
            if !placed {
                var occ=Occupancy(); reserved.forEach { occ.insert($0) }
                // If a reserved region label fills every nearby location, use a bounded screen search.
                var rect=candidates.first { !occ.overlaps($0) }
                if rect == nil {
                    outer: for y in stride(from:bounds.y,through:max(bounds.y,bounds.maxY-size.y),by:size.y+4) {
                        for x in stride(from:bounds.x,through:max(bounds.x,bounds.maxX-size.x),by:size.x+4) {
                            let r=Rect(x,y,size.x,size.y)
                            if !occ.overlaps(r) { rect=r; break outer }
                        }
                    }
                }
                // Real screens are larger than a label. No silently lost target, even in pathological reservations.
                let chosen=rect ?? Rect(bounds.x,bounds.y,size.x,size.y)
                occ.insert(chosen); occupied.append(occ); pages.append([Placement(target:target,rect:chosen,screen:screen.id)])
            }
        }
        return pages
    }
}
