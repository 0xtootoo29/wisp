// Wisp — service worker：Native Messaging 桥接 + 语音编排
// 取代 v0.7 的 AppleScript 注入路线：App → wisp-bridge → 这里 → voice.js 点按钮

const HOST = 'com.tootoo.wisp';
const CHATGPT = 'https://chatgpt.com/*';
let port = null;

function connect() {
  if (port) return; // 防重入：SW 顶层 + onStartup/onInstalled 都会调这里，只许一条端口
  try {
    port = chrome.runtime.connectNative(HOST);
  } catch (e) {
    port = null;
    return;
  }
  port.onMessage.addListener((msg) => {
    if (!msg) return;
    if (msg.cmd === 'toggle') toggle();
    else if (msg.cmd === 'status') reportStatus();
    else if (msg.cmd === 'setup-tab') setupTab();
    // msg.cmd === 'ping'：bridge 保活心跳，收到即可（重置 SW 空闲计时）
  });
  port.onDisconnect.addListener(() => {
    port = null;
    setTimeout(connect, 5000);
  });
  report('hello'); // 握手：App 端引导窗以此判定"扩展已装好"
}

function report(state) {
  try { if (port) port.postMessage({ event: 'state', state }); } catch (e) {}
}

async function ask(tabId, type) {
  try { return await chrome.tabs.sendMessage(tabId, { type }); } catch (e) { return null; }
}

// 全局页面状态：none 无标签 / unready 有标签但未登录或未就绪 / idle 就绪 / live 通话中
async function overallState() {
  const tabs = await chrome.tabs.query({ url: CHATGPT });
  if (!tabs.length) return 'none';
  const states = await Promise.all(tabs.map((t) => ask(t.id, 'state')));
  if (states.some((s) => s && s.state === 'live')) return 'live';
  if (states.some((s) => s && s.state === 'idle')) return 'idle';
  return 'unready';
}

async function reportStatus() { report('status-' + await overallState()); }

// 打开（或复用）ChatGPT 标签并固定置顶，前台弹出供登录
async function setupTab() {
  const tabs = await chrome.tabs.query({ url: CHATGPT });
  let tab = tabs[0];
  if (tab) await chrome.tabs.update(tab.id, { pinned: true, active: true });
  else tab = await chrome.tabs.create({ url: 'https://chatgpt.com/', pinned: true, active: true });
  try { await chrome.windows.update(tab.windowId, { focused: true }); } catch (e) {}
}

// 轮询等标签页内容脚本就绪（reload 唤醒 / 新建标签 共用）
async function waitReady(tabId, tries = 40) {
  for (let i = 0; i < tries; i++) {
    await new Promise((r) => setTimeout(r, 500));
    const s = await ask(tabId, 'state');
    if (s && (s.state === 'idle' || s.state === 'live')) return s.state;
  }
  return null;
}

async function toggle() {
  const tabs = await chrome.tabs.query({ url: CHATGPT });
  const states = await Promise.all(tabs.map((t) => ask(t.id, 'state')));

  // 先挂断：结束所有通话中的标签（多会话全杀，防"挂断后还在说话"）
  const live = tabs.filter((t, i) => states[i] && states[i].state === 'live');
  if (live.length) {
    await Promise.all(live.map((t) => ask(t.id, 'end')));
    report('idle');
    return;
  }

  // 启动：优先用已有可用标签
  let target = tabs.find((t, i) => states[i] && states[i].state === 'idle');

  // 有 chatgpt 标签但内容脚本没响应（被省内存休眠 / 扩展更新前就开着的旧标签）
  // → 唤醒复用（固定标签优先），绝不另开新页
  if (!target && tabs.length) {
    report('busy');
    const t = [...tabs].sort((a, b) => Number(b.pinned) - Number(a.pinned))[0];
    await chrome.tabs.reload(t.id);
    const st = await waitReady(t.id);
    if (st === 'live') { report('live'); return; }
    if (st === 'idle') target = t;
  }

  // 完全没有 chatgpt 标签 → 后台开一个（active:false 不抢焦点，零跳转）
  if (!target && !tabs.length) {
    report('busy');
    const created = await chrome.tabs.create({ url: 'https://chatgpt.com/', active: false });
    const st = await waitReady(created.id);
    if (st === 'live') { report('live'); return; }
    if (st === 'idle') target = created;
  }

  if (!target) { report('idle'); return; } // 20s 没就绪（未登录等）→ 放弃

  report('busy');
  await ask(target.id, 'start');
  // 连上/失败由 voice.js 的 MutationObserver 实时推送，无需轮询
}

// content script 状态推送 → 转发给 App
// idle 先做跨标签聚合：别的标签还在通话时，新开标签的 idle 不能把球打回空闲
chrome.runtime.onMessage.addListener((msg) => {
  if (!msg || msg.event !== 'state') return;
  if (msg.state === 'idle') {
    overallState().then((s) => { if (s !== 'live') report('idle'); });
  } else {
    report(msg.state);
  }
});

// 工具栏图标点击 = 点球（同一套 toggle）
chrome.action.onClicked.addListener(() => toggle());

chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
connect();
