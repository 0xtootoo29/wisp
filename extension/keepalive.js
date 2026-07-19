// GPT Live Keepalive — document_start / MAIN world
// 在 chatgpt.com 任何页面脚本运行之前，把"后台标签"伪装成"前台可见"，
// 使语音连接流程在后台标签也能完整跑通。
// 垫片范围：可见性 API / 焦点 / requestAnimationFrame / 页面冻结事件。
(() => {
  'use strict';

  // ---- 1. 可见性伪装（原型级覆盖，页面任何读取都拿到 visible）----
  try {
    Object.defineProperty(Document.prototype, 'visibilityState', {
      get() { return 'visible'; },
      configurable: true,
    });
    Object.defineProperty(Document.prototype, 'hidden', {
      get() { return false; },
      configurable: true,
    });
  } catch (e) { /* 旧内核兜底：实例级 */
    try {
      Object.defineProperty(document, 'visibilityState', { get: () => 'visible', configurable: true });
      Object.defineProperty(document, 'hidden', { get: () => false, configurable: true });
    } catch (_) {}
  }

  // ---- 2. 拦截可见性/冻结事件（捕获阶段，页面监听器收不到）----
  const swallow = (e) => { e.stopImmediatePropagation(); };
  for (const type of ['visibilitychange', 'webkitvisibilitychange', 'freeze', 'resume', 'pagehide']) {
    document.addEventListener(type, swallow, true);
    window.addEventListener(type, swallow, true);
  }

  // ---- 3. 焦点伪装 ----
  try {
    Document.prototype.hasFocus = function () { return true; };
  } catch (e) {}

  // ---- 4. rAF 垫片：后台标签 rAF 被合成器暂停，用定时器兜底 ----
  // 前台时优先走原生 rAF（保持 60fps 流畅），150ms 没回调则视为被暂停，切定时器。
  const nativeRAF = window.requestAnimationFrame.bind(window);
  const nativeCAF = window.cancelAnimationFrame.bind(window);
  let rafTimerIds = new Map();
  let nextFakeId = 1e9; // 与原生 id 空间错开

  window.requestAnimationFrame = function (cb) {
    let done = false;
    const nId = nativeRAF((ts) => {
      if (done) return;
      done = true;
      cb(ts);
    });
    // 兜底定时器：原生 rAF 没跑（后台被暂停）就用 timer 补
    const fId = nextFakeId++;
    const tId = setTimeout(() => {
      if (done) return;
      done = true;
      try { nativeCAF(nId); } catch (_) {}
      cb(performance.now());
      rafTimerIds.delete(fId);
    }, 150);
    rafTimerIds.set(fId, { tId, nId });
    return fId;
  };
  window.cancelAnimationFrame = function (id) {
    const rec = rafTimerIds.get(id);
    if (rec) {
      clearTimeout(rec.tId);
      try { nativeCAF(rec.nId); } catch (_) {}
      rafTimerIds.delete(id);
    } else {
      try { nativeCAF(id); } catch (_) {}
    }
  };

  // 供外部探测垫片已生效
  window.__gptLiveKeepalive = '0.1';
})();
