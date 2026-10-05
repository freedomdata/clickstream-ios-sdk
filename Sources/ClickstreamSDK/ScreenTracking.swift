import UIKit

/**
 Регистрирует появление экранов для события screen_view.
 */
internal enum ScreenTracking {

    private nonisolated(unsafe) static var onScreenAppear: ((String) -> Void)?
    private nonisolated(unsafe) static var didSwizzle = false
    private static let lock = NSLock()

    /**
     Устанавливает callback для появления экрана.
     - Parameters:
       - block: Замыкание с названием появившегося экрана.
     */
    static func setOnScreenAppear(_ block: ((String) -> Void)?) {
        lock.lock()
        onScreenAppear = block
        if block != nil, !didSwizzle {
            swizzleViewDidAppear()
            swizzleViewWillAppear()
            swizzleViewDidDisappear()
            didSwizzle = true
        }
        lock.unlock()
    }

    /**
     Подменяет viewWillAppear у UIViewController.
     */
    private static func swizzleViewWillAppear() {
        guard let original = class_getInstanceMethod(UIViewController.self, #selector(UIViewController.viewWillAppear(_:))),
              let swizzled = class_getInstanceMethod(UIViewController.self, #selector(UIViewController.cs_viewWillAppear(_:))) else {
            return
        }
        method_exchangeImplementations(original, swizzled)
    }

    /**
     Подменяет viewDidAppear у UIViewController.
     */
    private static func swizzleViewDidAppear() {
        guard let original = class_getInstanceMethod(UIViewController.self, #selector(UIViewController.viewDidAppear(_:))),
              let swizzled = class_getInstanceMethod(UIViewController.self, #selector(UIViewController.cs_viewDidAppear(_:))) else {
            return
        }
        method_exchangeImplementations(original, swizzled)
    }

    /**
     Подменяет viewDidDisappear у UIViewController.
     */
    private static func swizzleViewDidDisappear() {
        guard let original = class_getInstanceMethod(UIViewController.self, #selector(UIViewController.viewDidDisappear(_:))),
              let swizzled = class_getInstanceMethod(UIViewController.self, #selector(UIViewController.cs_viewDidDisappear(_:))) else {
            return
        }
        method_exchangeImplementations(original, swizzled)
    }

    /**
     Передает название экрана в установленный callback.
     - Parameters:
       - name: Название появившегося экрана.
     */
    static func reportScreenName(_ name: String) {
        lock.lock()
        let block = onScreenAppear
        lock.unlock()
        block?(name)
    }

    /**
     Возвращает название экрана для переданного UIViewController.
     - Parameters:
       - viewController: Контроллер для определения названия экрана.
     - Returns: Название экрана или пустая строка.
     */
    @MainActor
    static func resolveScreenName(from viewController: UIViewController) -> String {
        let resolved = unwrapContainers(from: viewController)

        if shouldIgnoreController(resolved) {
            return ""
        }

        if isLikelySwiftUIHostingController(resolved) {
            if let name = extractSwiftUIViewName(from: resolved) {
                return name
            }
        }

        return normalizeControllerTypeName(String(describing: type(of: resolved)))
    }

    /**
     Проверяет, нужно ли игнорировать контроллер.
     - Parameters:
       - vc: Контроллер для проверки.
     - Returns: Флаг игнорирования контроллера.
     */
    private static func shouldIgnoreController(_ vc: UIViewController) -> Bool {
        if isLikelySwiftUIHostingController(vc) { return false }
        let typeName = String(describing: type(of: vc))
        if typeName.localizedCaseInsensitiveContains("keyboard") { return true }
        if typeName.localizedCaseInsensitiveContains("input") { return true }
        if typeName.localizedCaseInsensitiveContains("texteffects") { return true }
        if typeName.localizedCaseInsensitiveContains("remote") { return true }

        let bundleId = Bundle(for: type(of: vc)).bundleIdentifier ?? ""
        if bundleId.hasPrefix("com.apple"), typeName == "RootView" {
            return true
        }
        if bundleId.hasPrefix("com.apple"), typeName.hasPrefix("UI") {
            return true
        }
        return false
    }

    /**
     Возвращает вложенный экранный контроллер из контейнера.
     - Parameters:
       - vc: Контроллер или контейнер для разворачивания.
     - Returns: Развернутый экранный контроллер.
     */
    @MainActor
    private static func unwrapContainers(from vc: UIViewController) -> UIViewController {
        if let nav = vc as? UINavigationController, let visible = nav.visibleViewController {
            return unwrapContainers(from: visible)
        }
        if let tab = vc as? UITabBarController, let selected = tab.selectedViewController {
            return unwrapContainers(from: selected)
        }
        if let split = vc as? UISplitViewController, let last = split.viewControllers.last {
            return unwrapContainers(from: last)
        }
        let typeName = String(describing: type(of: vc))
        if typeName.localizedCaseInsensitiveContains("RootViewController"), let child = vc.children.first {
            return unwrapContainers(from: child)
        }
        if vc.children.count == 1, let child = vc.children.first, isLikelySwiftUIHostingController(child) {
            return unwrapContainers(from: child)
        }
        return vc
    }

    /**
     Возвращает имя контроллера без технического суффикса.
     - Parameters:
       - raw: Исходное имя типа контроллера.
     - Returns: Нормализованное имя контроллера.
     */
    private static func normalizeControllerTypeName(_ raw: String) -> String {
        var s = raw
        if s.hasSuffix("ViewController") { s = String(s.dropLast("ViewController".count)) }
        return s
    }

    /**
     Проверяет, похож ли контроллер на UIHostingController.
     - Parameters:
       - vc: Контроллер для проверки.
     - Returns: Флаг принадлежности к SwiftUI hosting controller.
     */
    private static func isLikelySwiftUIHostingController(_ vc: UIViewController) -> Bool {
        let t = String(describing: type(of: vc))
        return t.hasPrefix("UIHostingController<") || t.contains("UIHostingController")
    }

    /**
     Возвращает самый верхний UIViewController в текущем окне.
     - Returns: Самый верхний контроллер или nil.
     */
    @MainActor
    static func topMostViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .rootViewController

        guard let root else { return nil }
        return topMost(from: root)
    }

    /**
     Возвращает самый верхний контроллер начиная с переданного.
     - Parameters:
       - vc: Начальный контроллер для поиска.
     - Returns: Самый верхний контроллер.
     */
    @MainActor
    private static func topMost(from vc: UIViewController) -> UIViewController {
        if let presented = vc.presentedViewController {
            return topMost(from: presented)
        }
        if let nav = vc as? UINavigationController, let visible = nav.visibleViewController {
            return topMost(from: visible)
        }
        if let tab = vc as? UITabBarController, let selected = tab.selectedViewController {
            return topMost(from: selected)
        }
        if let split = vc as? UISplitViewController, let last = split.viewControllers.last {
            return topMost(from: last)
        }
        return vc
    }

    /**
     Извлекает имя SwiftUI View из hosting controller.
     - Parameters:
       - vc: Контроллер для анализа.
     - Returns: Имя SwiftUI View или nil.
     */
    private static func extractSwiftUIViewName(from vc: UIViewController) -> String? {
        var visited = Set<ObjectIdentifier>()
        var candidates: [String] = []

        func tryAddCandidatesFromHostingControllerTypeName() {
            let t = String(describing: type(of: vc))
            guard let open = t.firstIndex(of: "<"), let close = t.lastIndex(of: ">"), open < close else { return }
            let inner = String(t[t.index(after: open)..<close])
            for token in extractIdentifierTokens(from: inner) {
                addCandidateToken(token)
            }
        }

        func addCandidateToken(_ short: String) {
            if short.isEmpty { return }
            if short.hasPrefix("_") { return }
            if short.localizedCaseInsensitiveContains("hosting") { return }
            if short.hasSuffix("Modifier") { return }
            if short == "RootView" { return }
            if short.contains("<") || short.contains(">") { return }
            if swiftUIWrappers.contains(short) { return }
            candidates.append(short)
        }

        func addCandidate(_ name: String) {
            let short = name.split(separator: ".").last.map(String.init) ?? name
            addCandidateToken(short)

            if short.contains("<") || short.contains(">") {
                for token in extractIdentifierTokens(from: short) {
                    addCandidateToken(token)
                }
            }
        }

        func walk(_ value: Any, depth: Int) {
            if depth > 12 { return }

            if let obj = value as AnyObject? {
                let id = ObjectIdentifier(obj)
                if visited.contains(id) { return }
                visited.insert(id)
            }

            addCandidate(String(describing: type(of: value)))

            let m = Mirror(reflecting: value)
            for child in m.children {
                walk(child.value, depth: depth + 1)
            }
        }

        let mirror = Mirror(reflecting: vc)
        if let root = mirror.children.first(where: { ($0.label ?? "").localizedCaseInsensitiveContains("root") })?.value {
            walk(root, depth: 0)
        }
        walk(vc, depth: 0)
        tryAddCandidatesFromHostingControllerTypeName()

        func score(_ name: String) -> Int {
            if name == "RootView" { return 0 }
            if name.hasSuffix("View") { return 5 }
            if name.hasSuffix("Screen") || name.localizedCaseInsensitiveContains("Screen") { return 4 }
            return 1
        }

        var best: String?
        var bestScore = 0
        for c in candidates {
            let s = score(c)
            if s > bestScore {
                best = c
                bestScore = s
                continue
            }
            if s == bestScore {
                if best == "RootView", c != "RootView" {
                    best = c
                    continue
                }
                best = c
            }
        }
        guard let best, bestScore >= 4 else { return nil }
        return best
    }

    /**
     Извлекает идентификаторы из строкового имени типа.
     - Parameters:
       - typeName: Строковое имя типа.
     - Returns: Массив найденных идентификаторов.
     */
    private static func extractIdentifierTokens(from typeName: String) -> [String] {
        let pattern = #"[A-Za-z_][A-Za-z0-9_]*"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = typeName as NSString
        let matches = re.matches(in: typeName, range: NSRange(location: 0, length: ns.length))
        return matches.map { ns.substring(with: $0.range) }
    }

    private static let swiftUIWrappers: Set<String> = [
        "UIHostingController",
        "PresentationHostingController",
        "AnyView",
        "ModifiedContent",
        "TupleView",
        "Optional",
        "Group",
        "ForEach",
        "VStack",
        "HStack",
        "ZStack",
        "ScrollView",
        "List",
        "NavigationStack",
        "NavigationView",
        "EmptyView",
        "Text"
    ]
}

extension UIViewController {

    /**
     Обрабатывает вызов viewWillAppear после swizzle.
     - Parameters:
       - animated: Флаг анимации появления контроллера.
     */
    @MainActor
    @objc fileprivate dynamic func cs_viewWillAppear(_ animated: Bool) {
        cs_viewWillAppear(animated)
        let name = ScreenTracking.resolveScreenName(from: self)
        if name.isEmpty { return }
        ScreenTracking.reportScreenName(name)
    }

    /**
     Обрабатывает вызов viewDidAppear после swizzle.
     - Parameters:
       - animated: Флаг анимации появления контроллера.
     */
    @MainActor
    @objc fileprivate dynamic func cs_viewDidAppear(_ animated: Bool) {
        cs_viewDidAppear(animated)
        let name = ScreenTracking.resolveScreenName(from: self)
        if name.isEmpty { return }
        ScreenTracking.reportScreenName(name)
    }

    /**
     Обрабатывает вызов viewDidDisappear после swizzle.
     - Parameters:
       - animated: Флаг анимации исчезновения контроллера.
     */
    @MainActor
    @objc fileprivate dynamic func cs_viewDidDisappear(_ animated: Bool) {
        cs_viewDidDisappear(animated)

        guard (isBeingDismissed || isMovingFromParent) else { return }

        if let top = ScreenTracking.topMostViewController() {
            let name = ScreenTracking.resolveScreenName(from: top)
            if name.isEmpty { return }
            ScreenTracking.reportScreenName(name)
        }
    }
}