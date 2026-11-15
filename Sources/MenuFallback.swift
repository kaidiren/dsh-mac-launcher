// MenuFallback.swift —— WebKit 缺少 CSS Anchor Positioning 时的菜单定位兜底。
//
// DSH Web 前端的弹层菜单（`[role=menu][data-anchor-side]`）用 CSS 锚点定位
// （`anchor()` / `position-anchor` / `position-try-fallbacks`）相对触发器摆放。
// macOS 15 的 WebKit 尚未实现这套 API（`CSS.supports('anchor-name: --a')` 为 false），
// 含 `anchor()` 的声明整条失效，只剩 `top: <窗口内边距>` 或 `bottom: 12px`：
// 账户菜单被钉在窗口左上角，向下弹出的菜单被推到窗口底边。
//
// 这里在页面脚本之前注入兜底：不支持锚点定位时，按触发器的实际矩形自己算坐标，
// 并在窗口尺寸变化/滚动时重算。支持该 API 的引擎上脚本立刻返回，不做任何事。
import WebKit

enum MenuFallback {
    static func script() -> WKUserScript {
        WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    /// 判断依据是 `CSS.supports('anchor-name: --a')`：与前端 `_portal` 的
    /// CSS 依赖的是同一批特性（`anchor-name` / `anchor()` / `anchor-size()`），
    /// 因此"支持"与"前端能正确摆放"是同一件事。
    private static let source = """
(function () {
  if (window.__dshMenuFallback) { return }
  window.__dshMenuFallback = true
  try {
    if (window.CSS && CSS.supports && CSS.supports('anchor-name: --dsh-probe')) { return }
  } catch (error) {
    return
  }

  var MARGIN = 12
  var GAP = 4
  var MENU_SELECTOR = '[role="menu"]'
  var TRIGGER_SELECTOR = '[aria-haspopup="menu"]'
  var lastTrigger = null

  function windowTopInset() {
    var raw = getComputedStyle(document.documentElement).getPropertyValue('--dsh-frame-overlay-top')
    var inset = parseFloat(raw)
    return isNaN(inset) ? MARGIN : Math.max(inset, MARGIN)
  }

  function visible(el) {
    var rect = el.getBoundingClientRect()
    return rect.width > 0 || rect.height > 0
  }

  function expandedTriggers() {
    var list = document.querySelectorAll('[aria-haspopup="menu"][aria-expanded="true"]')
    var out = []
    for (var i = 0; i < list.length; i++) {
      if (visible(list[i])) { out.push(list[i]) }
    }
    return out
  }

  // 多个触发器同时展开时（菜单切换的过渡帧），优先用最近一次真正展开的那个：
  // 菜单是按展开顺序挂到 body 上的，取"最后一个 expanded"会把新菜单摆到旧触发器上。
  // 右键菜单没有 aria-expanded 触发器。它的锚点是前端在鼠标处插的一个 0 尺寸 fixed span，
  // 但页面上还可能有其它 0 尺寸 fixed span，靠"最后一个"配对并不可靠（实测会抓错，
  // 菜单落到 (12,404) 而鼠标在 (48,312)）。所以以 contextmenu 事件坐标为准：
  // 在 document 的捕获阶段记录，React 的 onContextMenu 随后才处理，坐标一定是本次的。
  var lastContext = null

  document.addEventListener('contextmenu', function (event) {
    lastContext = { x: event.clientX, y: event.clientY, at: Date.now() }
  }, true)

  // 有些菜单的触发器是个普通 button：既没有 aria-haspopup 也没有 aria-expanded
  // （例：composer 里的「访问模式，当前：工作区内修改」）。这类只能靠"刚点的是谁"来配对。
  var lastPointer = null

  document.addEventListener('pointerdown', function (event) {
    var el = event.target
    if (el && el.nodeType === 1) { lastPointer = { el: el, at: Date.now() } }
  }, true)

  function pointerTarget() {
    if (!lastPointer || Date.now() - lastPointer.at > 2000) { return null }
    var el = lastPointer.el
    if (!el || !el.isConnected) { return null }
    // pointerdown 的 target 常是按钮内部的 span/svg，提到最近的按钮再量
    var host = el.closest ? el.closest('button, [role="button"], [aria-haspopup="menu"]') : null
    var rect = (host || el).getBoundingClientRect()
    return (rect.width > 0 || rect.height > 0) ? rect : null
  }

  function pointAt(x, y) {
    return { left: x, right: x, top: y, bottom: y, width: 0, height: 0 }
  }

  function contextPoint() {
    if (lastContext && Date.now() - lastContext.at < 3000) {
      return pointAt(lastContext.x, lastContext.y)
    }
    // 事件没收到时的退路：找 0 尺寸的 fixed span（其 left/top 是普通 CSS，不受 anchor 支持影响）
    var spans = document.querySelectorAll('span[style*="position: fixed"]')
    for (var i = spans.length - 1; i >= 0; i--) {
      var rect = spans[i].getBoundingClientRect()
      if (rect.width === 0 && rect.height === 0) { return rect }
    }
    return null
  }

  function activeTrigger() {
    // 隐藏的触发器不能当锚点：侧栏里很多操作按钮平时是 display:none / 0 尺寸，
    // 只有 hover 才显形。抓到它们会把菜单摆到窗口左上角（实测 (12,4)）。
    if (lastTrigger && lastTrigger.isConnected && lastTrigger.getAttribute('aria-expanded') === 'true'
        && visible(lastTrigger)) {
      return lastTrigger
    }
    var list = expandedTriggers()
    return list.length ? list[list.length - 1] : null
  }

  // 菜单材质是 70% 白 + backdrop-filter: blur(40px)。WebKit 里这个 blur 解析成功
  // 但不渲染（截图里能看清下层文字），前端为 macOS 原生窗口准备的 _backing 不透明底
  // 又因为 html[data-platform=darwin] 未命中而 display:none。这里直接把材质补成不透明。
  function solidMaterial(menu) {
    if (menu.getAttribute('data-menu-material') !== 'translucent') { return }
    var material = menu.querySelector('[class*="_material_"]')
    if (!material) { return }
    var base = getComputedStyle(document.body).getPropertyValue('--dsw-alias-bg-base').trim()
    if (base) { material.style.background = base }
  }

  function place(menu) {
    // 右键菜单（data-context-menu）必须只认鼠标坐标：它没有自己的 aria-expanded，
    // 而页面上可能残留别的"已展开"按钮，照触发器配对会把菜单摆到那个按钮旁边
    // （实测踩过：右键 (48,312)，菜单落到 (12,404)，配到了侧栏某行 (8,368)）。
    var isContextMenu = menu.hasAttribute('data-context-menu')
    var t = null
    if (isContextMenu) {
      t = contextPoint()
    } else {
      // 优先"刚点过谁"：页面上可能有别的 aria-expanded=true 按钮（比如侧栏里某个
      // 已展开的下拉），先查触发器会把它抢走 —— 实测「访问模式」菜单就这样被拽到了 (12,220)。
      t = pointerTarget()
      if (!t) {
        var trigger = activeTrigger()
        t = trigger ? trigger.getBoundingClientRect() : null
      }
    }
    // 量不出面积的锚点一律不用：宁可保持原样，也别把菜单摆到窗口角上
    if (!t || (t.width === 0 && t.height === 0)) { return false }
    // 两种菜单并存：前端 Menu 组件带 data-anchor-side/align（“更多”“账号菜单”等），
    // 模型与推理等级那类自绘菜单没有这两个属性，方向写死在 CSS 里（向上、右对齐、间距 8）。
    var hasSide = menu.hasAttribute('data-anchor-side')
    var side = hasSide ? menu.getAttribute('data-anchor-side') : 'top'
    var align = hasSide ? (menu.getAttribute('data-anchor-align') || 'start') : 'end'
    var gap = hasSide ? GAP : 8

    menu.style.position = 'fixed'
    menu.style.top = '0px'
    menu.style.left = '0px'
    menu.style.right = 'auto'
    menu.style.bottom = 'auto'
    var box = menu.getBoundingClientRect()
    var w = box.width
    var h = box.height
    var vw = window.innerWidth
    var vh = window.innerHeight
    var topLimit = windowTopInset()

    var x = t.left
    var y = t.bottom + gap
    if (side === 'top') {
      x = (align === 'end') ? t.right - w : t.left
      y = t.top - gap - h
    } else if (side === 'right') {
      x = t.right + gap
      y = (align === 'end') ? t.bottom - h : t.top
    } else if (side === 'left') {
      x = t.left - gap - w
      y = (align === 'end') ? t.bottom - h : t.top
    } else {
      x = (align === 'end') ? t.right - w : t.left
      y = t.bottom + gap
    }

    x = Math.max(MARGIN, Math.min(x, vw - w - MARGIN))
    if (y < topLimit) {
      var below = t.bottom + gap
      y = (below + h <= vh - MARGIN) ? below : topLimit
    } else if (y + h > vh - MARGIN) {
      var above = t.top - gap - h
      y = (above >= topLimit) ? above : Math.max(topLimit, vh - MARGIN - h)
    }

    menu.style.top = y + 'px'
    menu.style.left = x + 'px'
    menu.setAttribute('data-dsh-fallback', '1')
    solidMaterial(menu)
    return true
  }

  function placeAll() {
    var menus = document.querySelectorAll(MENU_SELECTOR)
    for (var i = 0; i < menus.length; i++) { place(menus[i]) }
  }

  // 菜单挂载与触发器 aria-expanded 的更新可能不在同一批 mutation 记录里，
  // 所以下一次 rAF 再摆一次（幂等）：第一次可能还没有可用的触发器。
  function placeSoon(menu, attempt) {
    var ok = place(menu)
    var tries = attempt || 0
    if (ok && tries > 0) { return }
    if (tries >= 6) { return }
    requestAnimationFrame(function () { placeSoon(menu, tries + 1) })
  }

  function isMenu(node) {
    return node.nodeType === 1 && node.getAttribute && node.getAttribute('role') === 'menu'
  }

  function scan(root) {
    if (!root || root.nodeType !== 1) { return }
    if (isMenu(root)) { placeSoon(root) }
    var found = root.querySelectorAll ? root.querySelectorAll(MENU_SELECTOR) : []
    for (var i = 0; i < found.length; i++) { placeSoon(found[i]) }
  }

  function boot() {
    var observer = new MutationObserver(function (records) {
      for (var i = 0; i < records.length; i++) {
        var record = records[i]
        if (record.type === 'attributes') {
          var target = record.target
          if (target.getAttribute('aria-expanded') === 'true') {
            lastTrigger = target
          } else if (target === lastTrigger) {
            lastTrigger = null
          }
          continue
        }
        var added = record.addedNodes
        for (var j = 0; j < added.length; j++) { scan(added[j]) }
      }
    })
    observer.observe(document.body, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['aria-expanded'],
    })
    window.addEventListener('resize', placeAll, true)
    window.addEventListener('scroll', placeAll, true)
  }

  if (document.body) { boot() } else {
    document.addEventListener('DOMContentLoaded', boot)
  }
})()
"""
}
