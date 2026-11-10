import AppKit
import SwiftUI

enum SettingsPage:String,CaseIterable {
    case general,appearance,shortcuts,connection
    var title:String { switch self { case .general:return "通用"; case .appearance:return "外观"; case .shortcuts:return "快捷键"; case .connection:return "连接与权限" } }
    var symbol:String { switch self { case .general:return "slider.horizontal.3"; case .appearance:return "circle.lefthalf.filled"; case .shortcuts:return "command"; case .connection:return "checkmark.shield" } }
    var subtitle:String { switch self { case .general:return "按你的节奏，选择、滚动与点击。"; case .appearance:return "清晰的标签，轻一点的存在感。"; case .shortcuts:return "让每一步，都留在键盘上。"; case .connection:return "管理 KeyPilot 与 macOS 的连接。" } }
}

private enum SettingsTheme {
    static let accent=Color(nsColor:NSColor(name:nil,dynamicProvider:{ appearance in
        appearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? Brand.mint:NSColor(srgbRed:0.19,green:0.56,blue:0.44,alpha:1)
    }))
    static let mint=Color(nsColor:Brand.mint)
    static let card=Color(nsColor:.controlBackgroundColor).opacity(0.76)
    static let line=Color.primary.opacity(0.07)
}

struct SettingsView:View {
    @ObservedObject var settings:Settings
    @State private var page:SettingsPage
    init(settings:Settings,page:SettingsPage = .general) { self.settings=settings; _page=State(initialValue:page) }
    private var status:String {
        if !settings.values.enabled { return "已暂停" }
        if !settings.trusted { return "需要授权" }
        return settings.hotkeysReady ? "已就绪":"需要重新连接"
    }
    private var healthy:Bool { settings.values.enabled && settings.trusted && settings.hotkeysReady }
    private var borderColor:Binding<Color> {
        Binding(get:{Color(red:settings.values.red,green:settings.values.green,blue:settings.values.blue)},set:{ color in
            guard let c=NSColor(color).usingColorSpace(.sRGB) else { return }
            var values=settings.values; values.red=c.redComponent; values.green=c.greenComponent; values.blue=c.blueComponent; settings.values=values
        })
    }
    var body:some View {
        HStack(spacing:0) {
            sidebar.frame(width:210)
            Rectangle().fill(SettingsTheme.line).frame(width:1)
            VStack(alignment:.leading,spacing:0) {
                HStack(alignment:.top) {
                    VStack(alignment:.leading,spacing:7) {
                        Text(page.title).font(.system(size:26,weight:.semibold))
                        Text(page.subtitle).font(.system(size:12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("实时保存",systemImage:"checkmark").font(.system(size:11,weight:.medium))
                        .foregroundStyle(.secondary).padding(.top,9)
                }.padding(.horizontal,32).padding(.top,46).padding(.bottom,25)
                ScrollView {
                    VStack(alignment:.leading,spacing:20) {
                        switch page {
                        case .general:general
                        case .appearance:appearance
                        case .shortcuts:shortcuts
                        case .connection:connection
                        }
                    }.padding(.horizontal,32).padding(.bottom,28).frame(maxWidth:.infinity,alignment:.leading)
                }.id(page)
            }.frame(maxWidth:.infinity,maxHeight:.infinity).background(Color(nsColor:.windowBackgroundColor))
        }
        .frame(minWidth:860,minHeight:650)
        .background(Color(nsColor:.windowBackgroundColor))
        .tint(SettingsTheme.accent)
        .ignoresSafeArea()
    }
    private var sidebar:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:9) {
                Image(nsImage:Brand.image(size:48)).resizable().frame(width:48,height:48).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:3) {
                    Text("KeyPilot").font(.system(size:19,weight:.semibold,design:.rounded))
                    Text("键盘导航").font(.system(size:11)).foregroundStyle(.secondary)
                }
            }.padding(.leading,15).padding(.top,48).padding(.bottom,34)
            VStack(spacing:7) {
                ForEach(Array(SettingsPage.allCases.enumerated()),id:\.element) { index,item in
                    Button { page=item } label:{
                        HStack(spacing:12) {
                            Image(systemName:item.symbol).font(.system(size:15,weight:.medium)).frame(width:20)
                            Text(item.title).font(.system(size:13,weight:page == item ? .semibold:.regular))
                            Spacer()
                        }.foregroundStyle(page == item ? SettingsTheme.accent:Color.primary.opacity(0.73))
                            .padding(.horizontal,14).frame(height:42)
                            .background(RoundedRectangle(cornerRadius:9).fill(page == item ? SettingsTheme.mint.opacity(0.25):Color.clear))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).keyboardShortcut(KeyEquivalent(Character(String(index+1))),modifiers:.command)
                        .accessibilityAddTraits(page == item ? .isSelected:[])
                }
            }.padding(.horizontal,13)
            Spacer()
            VStack(alignment:.leading,spacing:12) {
                HStack(spacing:7) {
                    Circle().fill(healthy ? SettingsTheme.accent:Color.secondary).frame(width:6,height:6)
                    Text(status).font(.system(size:12,weight:.medium))
                }
                Text("⌘1–4 切换设置页面").font(.system(size:10)).foregroundStyle(.tertiary)
                Divider()
                HStack {
                    Text("只在你的 Mac 上运行").font(.system(size:10))
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.1.0").font(.system(size:10,design:.monospaced))
                }.foregroundStyle(.secondary)
            }.padding(22)
        }.frame(maxHeight:.infinity).background(SidebarMaterial(reduced:settings.values.reduceTransparency))
    }
    private var general:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack(spacing:16) {
                Image(systemName:"keyboard").font(.system(size:25,weight:.light)).foregroundStyle(SettingsTheme.accent)
                    .frame(width:52,height:52).background(RoundedRectangle(cornerRadius:14).fill(SettingsTheme.mint.opacity(0.24)))
                VStack(alignment:.leading,spacing:7) {
                    Text("启用 KeyPilot").font(.system(size:16,weight:.semibold))
                    HStack(spacing:5) { Text("随时按").foregroundStyle(.secondary); Keycap("⇧⌘Space"); Text("开始导航").foregroundStyle(.secondary) }.font(.system(size:11))
                }
                Spacer()
                Toggle("启用 KeyPilot",isOn:$settings.values.enabled).labelsHidden().toggleStyle(.switch).accessibilityLabel("启用 KeyPilot")
            }.padding(21).background(RoundedRectangle(cornerRadius:16).fill(SettingsTheme.mint.opacity(0.10)))
                .overlay(RoundedRectangle(cornerRadius:16).strokeBorder(SettingsTheme.accent.opacity(0.14),lineWidth:1))
            SettingsSection("导航方式") {
                SettingToggle(title:"完整标签自动点击",detail:"输入完整标签后直接点击；关闭后按 Return 确认。",value:$settings.values.automaticClick)
                Divider()
                SettingToggle(title:"按需展开行内操作",detail:"保留行主目标，按 ; 选择一行展开操作。Space 显示全部。",value:$settings.values.foldRowActions)
            }
            SettingsSection("滚动手感") {
                SettingSlider(title:"滚动速度",value:$settings.values.speed,range:300...2000,step:50,display:"\(Int(settings.values.speed)) px/s",low:"慢",high:"快")
                Divider()
                SettingSlider(title:"按住 Shift 加速",value:$settings.values.acceleration,range:1...5,step:0.1,display:String(format:"%.1f ×",settings.values.acceleration),low:"1×",high:"5×")
            }
            Text("按住 J / K 向下或向上滚动；松开即停。关闭设置后，KeyPilot 仍在菜单栏运行。")
                .font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
    private var appearance:some View {
        VStack(alignment:.leading,spacing:20) {
            VStack(alignment:.leading,spacing:10) {
                sectionLabel("实时预览")
                LabelPreview(preferences:settings.values).frame(height:180).clipShape(RoundedRectangle(cornerRadius:14))
                    .overlay(RoundedRectangle(cornerRadius:14).strokeBorder(SettingsTheme.line,lineWidth:1))
                    .accessibilityLabel("区域标签、普通标签和选中标签的样式预览")
            }
            SettingsSection("标签") {
                VStack(alignment:.leading,spacing:13) {
                    Text("玻璃样式").font(.system(size:13,weight:.medium))
                    Picker("玻璃样式",selection:$settings.values.glassStyle) {
                        ForEach(GlassStyle.allCases,id:\.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("玻璃样式")
                }.padding(18)
                Divider()
                SettingSlider(title:"按钮字号",value:$settings.values.fontSize,range:11...20,step:1,display:"\(Int(settings.values.fontSize)) pt",low:"小",high:"大")
            }
            SettingsSection("区域高亮") {
                HStack {
                    VStack(alignment:.leading,spacing:5) { Text("边框颜色").font(.system(size:13,weight:.medium)); Text("只勾勒区域，保持内容通透。").font(.system(size:11)).foregroundStyle(.secondary) }
                    Spacer()
                    ColorPicker("边框颜色",selection:borderColor,supportsOpacity:false).labelsHidden().accessibilityLabel("边框颜色")
                }.padding(18)
                Divider()
                SettingToggle(title:"呼吸边框",detail:"10 秒淡出、10 秒淡入；跟随系统减少动态效果设置。",value:Binding(get:{settings.values.animation},set:{settings.values.animation=$0}))
            }
            HStack(alignment:.top) {
                Text(settings.values.reduceTransparency ? "系统已开启减少透明度，标签使用实色背景。":"毛玻璃与动效遵循 macOS 的辅助显示设置。")
                    .font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                Spacer(minLength:16)
                Button("恢复默认外观") {
                    var value=settings.values
                    let base=Preferences()
                    value.fontSize=base.fontSize; value.red=base.red; value.green=base.green; value.blue=base.blue
                    value.animation=base.animation; value.glassStyle=base.glassStyle; settings.values=value
                }.font(.system(size:11)).buttonStyle(.link)
            }
        }
    }
    private var shortcuts:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack(spacing:13) {
                Keycap("⇧⌘Space",large:true)
                VStack(alignment:.leading,spacing:5) { Text("从这里开始").font(.system(size:14,weight:.semibold)); Text("进入或退出导航，也可用 ⇧⌘J 进入。").font(.system(size:11)).foregroundStyle(.secondary) }
                Spacer()
            }.padding(21).background(RoundedRectangle(cornerRadius:14).fill(SettingsTheme.mint.opacity(0.13)))
            shortcutSection("选择与点击",rows:[("W / E / R","选择区域"),("Tab / ⇧Tab","下一个 / 上一个区域"),("完整标签","定位并点击目标"),("↑ / ↓ · Return","选择目标并确认"),("⇧Return / ⌘Return","右键 / Command 点击"),("; → 行标签","展开该行操作；再次 ; 收起")])
            shortcutSection("滚动与范围",rows:[("J / K","向下 / 向上滚动"),("Shift","按住时加速滚动"),("gg / Home","滚动到顶部"),("⇧G / End","滚动到底部"),("Space","显示全窗口与行内全部目标"),("[ / ]","上一页 / 下一页标签")])
            shortcutSection("输入与退出",rows:[("I","临时输入文字"),("Esc","输入时返回导航；导航时退出"),("Backspace","删除标签前缀")])
            Text("按物理键位识别，不受输入法影响。区域较多时使用两位区域码；关闭自动点击后需 Return 确认。")
                .font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
    private var connection:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack(spacing:16) {
                Image(systemName:healthy ? "checkmark.shield":"shield").font(.system(size:30,weight:.light)).foregroundStyle(SettingsTheme.accent)
                VStack(alignment:.leading,spacing:6) {
                    Text(healthy ? "一切就绪":status).font(.system(size:20,weight:.semibold))
                    Text(healthy ? "KeyPilot 已连接，可以开始键盘导航。":"完成下方连接检查后即可开始导航。")
                        .font(.system(size:12)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24).background(RoundedRectangle(cornerRadius:16).fill(SettingsTheme.mint.opacity(0.12)))
            SettingsSection("系统连接") {
                HStack(alignment:.center) {
                    connectionLabel("辅助功能权限",detail:"用于发现界面控件，并执行点击与滚动。",ready:settings.trusted)
                    Spacer(minLength:20)
                    Button("打开权限设置") { settings.openPermission() }.controlSize(.large)
                }.padding(20)
                Divider()
                HStack {
                    connectionLabel("全局快捷键",detail:settings.values.enabled ? "⇧⌘Space  /  ⇧⌘J":"KeyPilot 暂停时，快捷键也会停用。",ready:settings.hotkeysReady)
                    Spacer(minLength:20)
                    Button("重新连接") { settings.reconnect?() }.controlSize(.large)
                }.padding(20)
                Divider()
                Text(settings.status).font(.system(size:11)).foregroundStyle(.secondary).textSelection(.enabled).padding(18).frame(maxWidth:.infinity,alignment:.leading)
            }
            SettingsSection("在本机，保持简单") {
                VStack(alignment:.leading,spacing:17) {
                    privacyLine("macbook",title:"本机处理",detail:"只读取前台应用公开的辅助功能结构。")
                    privacyLine("eye.slash",title:"无需录屏",detail:"不截取屏幕，不保存输入文字或控件正文。")
                    privacyLine("network.slash",title:"不联网",detail:"没有账户、云端处理或遥测上传。")
                }.padding(20)
            }
            Text("部分应用的自绘控件可能无法标记。行内操作采用按需展开，也可能收起常显按钮；Space 始终保留全量入口。")
                .font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
    private func shortcutSection(_ title:String,rows:[(String,String)]) -> some View {
        SettingsSection(title) {
            VStack(spacing:0) {
                ForEach(rows.indices,id:\.self) { index in
                    HStack(spacing:16) { Text(rows[index].1).font(.system(size:12)); Spacer(); Keycap(rows[index].0) }.padding(.horizontal,18).padding(.vertical,11)
                    if index < rows.count-1 { Divider().padding(.horizontal,18) }
                }
            }
        }
    }
    private func connectionLabel(_ title:String,detail:String,ready:Bool) -> some View {
        VStack(alignment:.leading,spacing:7) {
            HStack(spacing:8) { Text(title).font(.system(size:13,weight:.semibold)); Image(systemName:ready ? "checkmark.circle.fill":"circle.dashed").foregroundStyle(ready ? SettingsTheme.accent:Color.secondary) }
            Text(detail).font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
    private func privacyLine(_ symbol:String,title:String,detail:String) -> some View {
        HStack(alignment:.top,spacing:13) {
            Image(systemName:symbol).font(.system(size:16)).foregroundStyle(SettingsTheme.accent).frame(width:22)
            VStack(alignment:.leading,spacing:4) { Text(title).font(.system(size:12,weight:.medium)); Text(detail).font(.system(size:11)).foregroundStyle(.secondary) }
        }
    }
}

private func sectionLabel(_ text:String) -> some View {
    Text(text).font(.system(size:11,weight:.semibold)).foregroundStyle(.secondary).padding(.leading,3)
}
private struct SettingsSection<Content:View>:View {
    let title:String
    let content:Content
    init(_ title:String,@ViewBuilder content:()->Content) { self.title=title; self.content=content() }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            sectionLabel(title)
            VStack(spacing:0) { content }.frame(maxWidth:.infinity,alignment:.leading)
                .background(RoundedRectangle(cornerRadius:13).fill(SettingsTheme.card))
                .overlay(RoundedRectangle(cornerRadius:13).strokeBorder(SettingsTheme.line,lineWidth:1))
        }
    }
}
private struct SettingToggle:View {
    let title:String,detail:String
    @Binding var value:Bool
    var body:some View {
        HStack(spacing:24) {
            VStack(alignment:.leading,spacing:6) {
                Text(title).font(.system(size:13,weight:.medium))
                Text(detail).font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            Spacer(minLength:0)
            Toggle(title,isOn:$value).labelsHidden().toggleStyle(.switch).accessibilityLabel(title).accessibilityHint(detail)
        }.padding(18)
    }
}
private struct SettingSlider:View {
    let title:String
    @Binding var value:Double
    let range:ClosedRange<Double>,step:Double,display:String,low:String,high:String
    var body:some View {
        VStack(spacing:12) {
            HStack { Text(title).font(.system(size:13,weight:.medium)); Spacer(); Text(display).font(.system(size:12,weight:.medium,design:.monospaced)).foregroundStyle(.secondary) }
            HStack(spacing:12) {
                Text(low).font(.system(size:10)).foregroundStyle(.tertiary)
                SettingsSlider(value:$value,range:range,step:step,title:title).frame(height:20)
                Text(high).font(.system(size:10)).foregroundStyle(.tertiary)
            }
        }.padding(18)
    }
}
private struct Keycap:View {
    let text:String
    var large=false
    init(_ text:String,large:Bool=false) { self.text=text; self.large=large }
    var body:some View {
        Text(text).font(.system(size:large ? 16:11,weight:.medium,design:.monospaced))
            .padding(.horizontal,large ? 15:7).padding(.vertical,large ? 13:4)
            .background(RoundedRectangle(cornerRadius:large ? 10:5).fill(Color(nsColor:.controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius:large ? 10:5).strokeBorder(Color.primary.opacity(0.09),lineWidth:1))
            .shadow(color:.black.opacity(0.04),radius:0,y:2)
    }
}
private struct SidebarMaterial:NSViewRepresentable {
    let reduced:Bool
    func makeNSView(context:Context) -> NSVisualEffectView { NSVisualEffectView() }
    func updateNSView(_ view:NSVisualEffectView,context:Context) {
        view.material = .sidebar; view.blendingMode = .behindWindow; view.state = .active
        view.wantsLayer=true
        view.layer?.backgroundColor=reduced ? NSColor.windowBackgroundColor.cgColor:nil
    }
}
