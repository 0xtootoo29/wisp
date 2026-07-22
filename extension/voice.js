// Wisp — 语音控制 content script（isolated world, document_idle）
// 职责：找语音按钮、执行点击、用 MutationObserver 实时推送状态变化（取代 12s 轮询）

const START_LABELS = ['启动语音功能', 'Start voice mode', 'Use voice mode', 'Start voice'];
const END_LABELS = ['结束语音功能', 'End voice mode', 'End voice'];

function find(labels) {
  for (const b of document.querySelectorAll('button[aria-label]')) {
    if (labels.includes(b.getAttribute('aria-label'))) return b;
  }
  return null;
}

function voiceState() {
  if (find(END_LABELS)) return 'live';
  if (find(START_LABELS)) return 'idle';
  return 'unknown'; // 页面加载中 / 连接过渡态
}

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg.type === 'state') { sendResponse({ state: voiceState() }); return; }
  if (msg.type === 'start') { const b = find(START_LABELS); if (b) b.click(); sendResponse({ ok: !!b }); return; }
  if (msg.type === 'end') { const b = find(END_LABELS); if (b) b.click(); sendResponse({ ok: !!b }); return; }
  if (msg.type === 'newchat') {
    // 点侧栏「新聊天」（SPA 切换，快、不重载页面）；找不到按钮由 SW 走导航兜底
    const sels = [
      '[data-testid="create-new-chat-button"]',
      'a[aria-label="新聊天"]', 'button[aria-label="新聊天"]',
      'a[aria-label="新建聊天"]', 'button[aria-label="新建聊天"]',
      'a[aria-label="New chat"]', 'button[aria-label="New chat"]',
    ];
    for (const s of sels) {
      const el = document.querySelector(s);
      if (el) { el.click(); sendResponse({ ok: true }); return; }
    }
    sendResponse({ ok: false });
    return;
  }
});

// 状态变化推送（400ms 防抖，只推确定态，unknown 过渡不打扰）
let last = voiceState();
let timer = null;
// 加载即报一次初始状态（引导窗第③步"登录就绪"检测 + Chrome 重启后的状态同步）
if (last !== 'unknown') {
  try { chrome.runtime.sendMessage({ event: 'state', state: last }); } catch (e) {}
}
new MutationObserver(() => {
  clearTimeout(timer);
  timer = setTimeout(() => {
    const s = voiceState();
    if (s === 'unknown' || s === last) return;
    last = s;
    try { chrome.runtime.sendMessage({ event: 'state', state: s }); } catch (e) {}
  }, 400);
}).observe(document.documentElement, {
  subtree: true,
  childList: true,
  attributes: true,
  attributeFilter: ['aria-label'],
});
