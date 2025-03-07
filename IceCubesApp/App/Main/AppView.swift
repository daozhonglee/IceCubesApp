// 导入音视频处理相关框架
import AVFoundation
// 导入账户管理相关模块
import Account
import AppAccount
// 导入设计系统模块
import DesignSystem
// 导入环境配置模块
import Env
// 导入钥匙串访问框架
import KeychainSwift
// 导入媒体UI模块
import MediaUI
// 导入网络相关模块
import Network
// 导入应用内购相关框架
import RevenueCat
// 导入状态管理模块
import StatusKit
// 导入SwiftUI框架
import SwiftUI
// 导入时间线相关模块
import Timeline

// 使用@MainActor标记确保视图在主线程上运行
@MainActor
// 定义应用的主视图结构体，遵循View协议
struct AppView: View {
  // 从环境中获取应用账户管理器实例，用于处理用户账户相关操作
  @Environment(AppAccountsManager.self) private var appAccountsManager
  // 从环境中获取用户偏好设置实例，用于管理用户的应用配置
  @Environment(UserPreferences.self) private var userPreferences
  // 从环境中获取主题管理实例，用于控制应用的视觉样式
  @Environment(Theme.self) private var theme
  // 从环境中获取流监视器实例，用于监控实时数据流
  @Environment(StreamWatcher.self) private var watcher

  // 从环境中获取打开窗口的函数，用于在visionOS等平台上打开新窗口
  @Environment(\.openWindow) var openWindow
  // 从环境中获取水平尺寸类别，用于适配不同设备的布局
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  // 使用@Binding创建双向绑定的选中标签页状态
  @Binding var selectedTab: AppTab
  // 使用@Binding创建双向绑定的路由路径状态，用于页面导航
  @Binding var appRouterPath: RouterPath

  // 使用@State管理iOS标签页状态，使用单例模式确保全局唯一性
  @State var iosTabs = iOSTabs.shared
  // 使用@State管理侧边栏标签页状态，使用单例模式确保全局唯一性
  @State var sidebarTabs = SidebarTabs.shared
  // 使用@State管理标签页滚动状态，-1表示不滚动
  @State var selectedTabScrollToTop: Int = -1

  var body: some View {
    // 根据设备类型选择不同的视图布局
    switch UIDevice.current.userInterfaceIdiom {
    case .vision:
      tabBarView // visionOS设备使用标签栏视图
    case .pad, .mac:
      #if !os(visionOS)
        sidebarView // iPad和Mac使用侧边栏视图
      #else
        tabBarView // visionOS使用标签栏视图
      #endif
    default:
      tabBarView // 其他设备默认使用标签栏视图
    }
  }

  // 计算可用的标签页数组
  var availableTabs: [AppTab] {
    // 如果用户未登录，返回登出状态的标签页
    guard appAccountsManager.currentClient.isAuth else {
      return AppTab.loggedOutTab()
    }
    // 根据设备类型和尺寸类别返回不同的标签页集合
    if UIDevice.current.userInterfaceIdiom == .phone || horizontalSizeClass == .compact {
      return iosTabs.tabs
    } else if UIDevice.current.userInterfaceIdiom == .vision {
      return AppTab.visionOSTab()
    }
    return sidebarTabs.tabs.map { $0.tab }
  }

  // 标签栏视图构建器
  @ViewBuilder
  var tabBarView: some View {
    TabView(
      selection: .init(
        get: {
          selectedTab // 获取当前选中的标签页
        },
        set: { newTab in
          updateTab(with: newTab) // 更新选中的标签页
        })
    ) {
      // 遍历可用标签页创建标签项
      ForEach(availableTabs) { tab in
        tab.makeContentView(selectedTab: $selectedTab)
          .tabItem {
            // 根据用户偏好显示标签文本或仅显示图标
            if userPreferences.showiPhoneTabLabel {
              tab.label
                .environment(\.symbolVariants, tab == selectedTab ? .fill : .none)
            } else {
              Image(systemName: tab.iconName)
            }
          }
          .tag(tab)
          .badge(badgeFor(tab: tab)) // 显示标签页的徽章（如通知数）
          .toolbarBackground(theme.primaryBackgroundColor.opacity(0.30), for: .tabBar) // 设置工具栏背景
      }
    }
    .id(appAccountsManager.currentClient.id) // 使用客户端ID作为视图标识，用于强制刷新
    .withSheetDestinations(sheetDestinations: $appRouterPath.presentedSheet) // 添加页面导航支持
    .environment(\.selectedTabScrollToTop, selectedTabScrollToTop) // 传递滚动到顶部的状态
  }

  // 更新选中标签页的方法
  private func updateTab(with newTab: AppTab) {
    // 处理发帖标签页的特殊情况
    if newTab == .post {
      #if os(visionOS)
        // visionOS上打开新窗口进行编辑
        openWindow(
          value: WindowDestinationEditor.newStatusEditor(visibility: userPreferences.postVisibility)
        )
      #else
        // 其他平台显示模态编辑器
        appRouterPath.presentedSheet = .newStatusEditor(visibility: userPreferences.postVisibility)
      #endif
      return
    }

    // 触发触觉反馈和声音效果，提升用户体验
    HapticManager.shared.fireHaptic(.tabSelection)
    SoundEffectManager.shared.playSound(.tabSelection)

    // 处理标签页切换逻辑
    if selectedTab == newTab {
      // 如果点击当前标签页，触发滚动到顶部
      selectedTabScrollToTop = newTab.rawValue
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        selectedTabScrollToTop = -1
      }
    } else {
      selectedTabScrollToTop = -1
    }

    selectedTab = newTab // 更新选中的标签页状态
  }

  // 计算标签页徽章数量的方法
  private func badgeFor(tab: AppTab) -> Int {
    // 仅为通知标签页显示未读消息数
    if tab == .notifications, selectedTab != tab,
      let token = appAccountsManager.currentAccount.oauthToken
    {
      return watcher.unreadNotificationsCount + (userPreferences.notificationsCount[token] ?? 0)
    }
    return 0
  }

  #if !os(visionOS)
    // 侧边栏视图（非visionOS平台）
    var sidebarView: some View {
      SideBarView(
        selectedTab: .init(
          get: {
            selectedTab
          },
          set: { newTab in
            updateTab(with: newTab)
          }), tabs: availableTabs
      ) {
        HStack(spacing: 0) {
          if #available(iOS 18.0, *) {
            baseTabView
              #if targetEnvironment(macCatalyst)
                // macOS上使用可适应的侧边栏样式
                .tabViewStyle(.sidebarAdaptable)
                .introspect(.tabView, on: .iOS(.v17, .v18)) { (tabview: UITabBarController) in
                  tabview.sidebar.isHidden = true
                }
              #else
                // iOS上使用标准标签栏样式
                .tabViewStyle(.tabBarOnly)
              #endif
          } else {
            baseTabView
          }
          // 在iPad上显示辅助列（通知列表）
          if horizontalSizeClass == .regular,
            appAccountsManager.currentClient.isAuth,
            userPreferences.showiPadSecondaryColumn
          {
            Divider().edgesIgnoringSafeArea(.all)
            notificationsSecondaryColumn
          }
        }
      }
      .environment(appRouterPath) // 传递路由路径环境值
      .environment(\.selectedTabScrollToTop, selectedTabScrollToTop) // 传递滚动状态环境值
    }
  #endif

  // 基础标签视图，用于构建应用的主要导航界面
  private var baseTabView: some View {
    // 创建标签页视图，使用selectedTab状态进行选中标签的管理
    TabView(selection: $selectedTab) {
      // 遍历可用的标签页数组，为每个标签创建对应的内容视图
      ForEach(availableTabs) { tab in
        tab
          .makeContentView(selectedTab: $selectedTab)
          .toolbar(horizontalSizeClass == .regular ? .hidden : .visible, for: .tabBar) // 根据水平尺寸类别控制工具栏的显示和隐藏
          .tabItem {
            tab.label // 设置标签项的标签内容
          }
          .tag(tab) // 为视图设置标签，用于标识和选择
      }
    }
    #if !os(visionOS)
      // 使用introspect调整UIKit标签栏控制器的属性
      .introspect(.tabView, on: .iOS(.v17, .v18)) { (tabview: UITabBarController) in
        tabview.tabBar.isHidden = horizontalSizeClass == .regular
        tabview.customizableViewControllers = []
        tabview.moreNavigationController.isNavigationBarHidden = true
      }
    #endif
  }

  // 通知辅助列视图，用于在iPad等大屏设备上显示通知列表
  var notificationsSecondaryColumn: some View {
    // 创建通知标签页视图，固定选中通知标签，无锁定类型
    NotificationsTab(selectedTab: .constant(.notifications), lockedType: nil)
      .environment(\.isSecondaryColumn, true) // 将环境变量isSecondaryColumn设置为true，标记当前视图为辅助列
      .frame(maxWidth: .secondaryColumnWidth) // 使用预定义的辅助列宽度限制视图最大宽度
      .id(appAccountsManager.currentAccount.id) // 使用当前账户ID作为视图标识符，当账户切换时强制刷新视图
  }
}
