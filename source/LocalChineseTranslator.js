/*:
 * @plugindesc MV/MZ 游戏内中文翻译 v0.1（实验版，联网翻译，保留原数据）
 * @author LocalChineseTranslator
 * @help 在 Windows 桌面版 NW.js 游戏内运行。F6 或右上角按钮暂停/恢复。
 * 识别到的游戏文字会发送至 Google 翻译；免费网页接口无可用性保证。
 */
(function (root) {
    'use strict';
    var VERSION = '0.1';
    var STORAGE_KEY = 'LocalChineseTranslator.v1';
    var MAX_CACHE = 4000;
    // Export a factory for offline regression tests; the shipped game uses globals.
    function createTranslator(options) {
        var cache = Object.create(null), pending = Object.create(null);
        var failures = Object.create(null), outputs = Object.create(null), queue = [], active = false, cooldown = 0;
        var enabled = true, storedTimer = null, count = 0;
        var now = options.now || Date.now;
        var change = options.change || function () {};
        try {
            var saved = JSON.parse(options.storage.getItem(STORAGE_KEY) || '{}');
            if (saved && saved.version === VERSION && Array.isArray(saved.entries)) {
                saved.entries.slice(-MAX_CACHE).forEach(function (entry) {
                    if (Array.isArray(entry) && typeof entry[0] === 'string' && typeof entry[1] === 'string') {
                        cache[entry[0]] = entry[1]; outputs[entry[1]] = true; count++;
                    }
                });
            }
        } catch (_) {}
        function notify(error) { change({ enabled: enabled, active: active, queued: queue.length, count: count, error: error || '' }); }
        function save() {
            if (storedTimer) return;
            storedTimer = setTimeout(function () {
                storedTimer = null;
                try {
                    var keys = Object.keys(cache).slice(-MAX_CACHE);
                    options.storage.setItem(STORAGE_KEY, JSON.stringify({ version: VERSION, entries: keys.map(function (k) { return [k, cache[k]]; }) }));
                } catch (_) { /* Private mode / storage full: retain in-memory cache. */ }
            }, 500);
        }
        function protect(text) {
            var tokens = [];
            if (/ZXQPH\d+QXZ/i.test(text)) throw new Error('原文包含保留标记');
            var masked = text.replace(/\\(?:[A-Za-z]+(?:\[[^\]\r\n]*\])?|[\\.$|!><^{}])|\x1b(?:[A-Za-z]+(?:\[[^\]\r\n]*\])?|[.$|!><^{}])|%\d+|\r?\n/g, function (token) {
                var label = 'ZXQPH' + tokens.length + 'QXZ'; tokens.push(token); return label;
            });
            return { text: masked, restore: function (result) {
                tokens.forEach(function (token, i) {
                    var marker = 'ZXQPH' + i + 'QXZ';
                    if (result.split(marker).length !== 2) throw new Error('翻译改变了控制符，保留原文');
                });
                // Keep control-code order, because a moved color/name token changes meaning.
                var found = result.match(/ZXQPH\d+QXZ/g) || [];
                if (found.length !== tokens.length || found.some(function (v, i) { return v !== 'ZXQPH' + i + 'QXZ'; })) {
                    throw new Error('翻译移动了控制符，保留原文');
                }
                return result.replace(/ZXQPH(\d+)QXZ/g, function (_, i) { return tokens[Number(i)]; });
            } };
        }
        function eligible(text) {
            return typeof text === 'string' && text.trim().length >= 2 && text.length <= 3000 && !outputs[text] && /[A-Za-z\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af\u0400-\u052f\u00c0-\u024f]/.test(text);
        }
        function pump() {
            if (!enabled || active || !queue.length || now() < cooldown) return;
            var item = queue.shift(); active = true; notify();
            var safe;
            try { safe = protect(item.text); }
            catch (error) { complete(error); return; }
            var finished = false;
            function complete(error, translated) {
                if (finished) return;
                finished = true;
                clearTimeout(timer);
                var value;
                try {
                    if (error) throw error;
                    if (typeof translated !== 'string' || !translated.trim()) throw new Error('没有收到译文');
                    value = safe.restore(translated);
                    if (!Object.prototype.hasOwnProperty.call(cache, item.text)) count++;
                    cache[item.text] = value; outputs[value] = true;
                    var keys = Object.keys(cache);
                    if (keys.length > MAX_CACHE) { delete cache[keys[0]]; count--; }
                    save();
                } catch (err) {
                    error = err;
                    failures[item.text] = now() + 60000;
                    cooldown = now() + 15000;
                }
                delete pending[item.text]; active = false;
                notify(error ? String(error.message || error) : '');
                setTimeout(pump, error ? 15000 : 450);
            }
            var timer = setTimeout(function () { complete(new Error('翻译连接超时')); }, 11000);
            try { options.transport(safe.text, complete); } catch (error) { complete(error); }
        }
        function request(text, priority) {
            if (!enabled || !eligible(text) || Object.prototype.hasOwnProperty.call(cache, text) || failures[text] > now()) return;
            if (pending[text]) {
                if (priority) {
                    var index = queue.indexOf(pending[text]);
                    if (index > 0) queue.unshift(queue.splice(index, 1)[0]);
                }
                return;
            }
            // Bound background menu requests; dialogue priority may still enter.
            if (!priority && queue.length >= 80) return;
            var item = { text: text }; pending[text] = item;
            if (priority) queue.unshift(item); else queue.push(item);
            pump();
        }
        return {
            request: request,
            lookup: function (text) { return enabled && Object.prototype.hasOwnProperty.call(cache, text) ? cache[text] : text; },
            waiting: function (text) { return enabled && eligible(text) && !Object.prototype.hasOwnProperty.call(cache, text) && !(failures[text] > now()); },
            toggle: function () {
                enabled = !enabled;
                if (!enabled) { queue.forEach(function (item) { delete pending[item.text]; }); queue = []; }
                notify(); if (enabled) pump(); return enabled;
            },
            enabled: function () { return enabled; },
            protect: protect
        };
    }
    function diskStorage() {
        try {
            var fs = require('fs'), path = require('path'), crypto = require('crypto');
            var base = 'D:\\RPGTranslator', folder = path.join(base, 'cache');
            if (!fs.existsSync(base)) fs.mkdirSync(base);
            if (fs.lstatSync(base).isSymbolicLink() || !/^D:[\\/]/i.test(fs.realpathSync(base))) throw new Error('Invalid D drive');
            if (!fs.existsSync(folder)) fs.mkdirSync(folder);
            if (fs.lstatSync(folder).isSymbolicLink() || !/^D:[\\/]/i.test(fs.realpathSync(folder))) throw new Error('Redirected cache');
            var identity = fs.realpathSync(process.cwd());
            var key = crypto.createHash('sha256').update(identity).digest('hex');
            var file = path.join(folder, key + '.json');
            return {
                getItem: function () {
                    if (!fs.existsSync(file)) return null;
                    if (fs.lstatSync(file).isSymbolicLink()) throw new Error('Redirected cache file');
                    return fs.readFileSync(file, 'utf8');
                },
                setItem: function (_, value) {
                    if (fs.existsSync(file) && fs.lstatSync(file).isSymbolicLink()) throw new Error('Redirected cache file');
                    fs.writeFileSync(file, value, 'utf8');
                }
            };
        } catch (_) {
            // No writable D: cache means memory-only, never a C: fallback.
            return { getItem: function () { return null; }, setItem: function () {} };
        }
    }
    function install(g, transport, storage) {
        if (g.LocalChineseTranslator) return g.LocalChineseTranslator;
        var lastError = '', refreshTimer = null, badge = null;
        var translator = createTranslator({
            storage: storage || diskStorage(),
            transport: transport,
            change: function (state) {
                if (state.error) lastError = state.error;
                else if (!state.active && state.count) lastError = '';
                if (badge) {
                    badge.textContent = !state.enabled ? '中文翻译：暂停（F6）' : state.error || lastError ? '翻译暂不可用 · 显示原文（F6）' : state.active || state.queued ? '正在翻译…（F6 暂停）' : '中文翻译已启用（F6）';
                    badge.title = lastError || '点击暂停/恢复；首次遇到的文字需要联网，重复文字使用本机缓存。';
                }
                if (!state.active) scheduleRefresh();
            }
        });
        g.LocalChineseTranslator = translator;
        function scheduleRefresh() {
            if (refreshTimer) return;
            refreshTimer = setTimeout(function () {
                refreshTimer = null;
                var scene = g.SceneManager && g.SceneManager._scene;
                var children = scene && scene._windowLayer && scene._windowLayer.children;
                if (!children) return;
                children.slice().forEach(function (window) {
                    if (!window || !window.visible || typeof window.refresh !== 'function') return;
                    // Never restart an active message, name input, or battle log.
                    if ((g.Window_Message && window instanceof g.Window_Message) ||
                        (g.Window_NameEdit && window instanceof g.Window_NameEdit) ||
                        (g.Window_BattleLog && window instanceof g.Window_BattleLog)) return;
                    try { window.refresh(); } catch (_) {}
                });
            }, 120);
        }
        var allText = g.Game_Message.prototype.allText;
        var choices = g.Game_Message.prototype.choices;
        g.Game_Message.prototype.allText = function () { return translator.lookup(allText.call(this)); };
        g.Game_Message.prototype.choices = function () { return choices.call(this).map(function (s) { return translator.lookup(s); }); };
        if (g.Game_Message.prototype.speakerName) {
            var speakerName = g.Game_Message.prototype.speakerName;
            g.Game_Message.prototype.speakerName = function () {
                var text = speakerName.call(this); translator.request(text, true); return translator.lookup(text);
            };
        }
        function ready(window, texts) {
            if (!translator.enabled()) return true;
            var key = JSON.stringify(texts), time = Date.now();
            if (!window._localChineseGate || window._localChineseGate.key !== key) window._localChineseGate = { key: key, time: time };
            texts.forEach(function (text) { translator.request(text, true); });
            // No connection can block a dialogue indefinitely: fail open after 15s.
            if (time - window._localChineseGate.time > 15000) return true;
            return !texts.some(function (text) { return translator.waiting(text); });
        }
        var canStart = g.Window_Message.prototype.canStart;
        g.Window_Message.prototype.canStart = function () {
            if (!canStart.apply(this, arguments)) return false;
            return ready(this, [allText.call(g.$gameMessage)].concat(choices.call(g.$gameMessage)));
        };
        var startInput = g.Window_Message.prototype.startInput;
        g.Window_Message.prototype.startInput = function () {
            var list = choices.call(g.$gameMessage);
            var rawText = allText.call(g.$gameMessage);
            if (rawText && !this._textState && !ready(this, [rawText].concat(list))) return true;
            // Returning true tells the engine that input is being handled/waited for.
            if (list.length && !ready(this, list)) return true;
            return startInput.apply(this, arguments);
        };
        var clearMessage = g.Game_Message.prototype.clear;
        g.Game_Message.prototype.clear = function () {
            var result = clearMessage.apply(this, arguments);
            var scene = g.SceneManager && g.SceneManager._scene;
            if (scene && scene._messageWindow) scene._messageWindow._localChineseGate = null;
            return result;
        };
        var drawText = g.Bitmap.prototype.drawText;
        g.Bitmap.prototype.drawText = function (text) {
            var args = Array.prototype.slice.call(arguments);
            if (typeof text === 'string') { translator.request(text, false); args[0] = translator.lookup(text); }
            return drawText.apply(this, args);
        };
        // drawTextEx parses a string character-by-character, so translate before parsing.
        if (g.Window_Base && g.Window_Base.prototype.convertEscapeCharacters) {
            var convert = g.Window_Base.prototype.convertEscapeCharacters;
            g.Window_Base.prototype.convertEscapeCharacters = function (text) {
                translator.request(text, false);
                return convert.call(this, translator.lookup(text));
            };
        }
        if (g.document && g.document.body) {
            badge = g.document.createElement('button');
            badge.style.cssText = 'position:fixed;right:8px;top:8px;z-index:2147483647;background:rgba(20,28,38,.85);color:white;border:1px solid #8ba0b6;border-radius:5px;padding:5px 9px;font:12px sans-serif;cursor:pointer;';
            badge.textContent = '中文翻译已启用（F6）';
            badge.onclick = function () { translator.toggle(); scheduleRefresh(); };
            g.document.body.appendChild(badge);
            g.document.addEventListener('keydown', function (event) {
                if (event.keyCode === 117 && !event.repeat) { event.preventDefault(); translator.toggle(); scheduleRefresh(); }
            });
        }
        return translator;
    }
    function nodeTransport(text, callback) {
        var https;
        try { https = require('https'); }
        catch (_) { callback(new Error('此版本需要 NW.js 桌面版游戏')); return; }
        var path = '/translate_a/single?client=gtx&sl=auto&tl=zh-CN&dt=t&q=' + encodeURIComponent(text);
        var settled = false, req, timeout;
        function finish(error, value) {
            if (settled) return;
            settled = true; clearTimeout(timeout); callback(error, value);
        }
        req = https.get({ hostname: 'translate.googleapis.com', path: path, headers: { 'User-Agent': 'LocalChineseTranslator/0.1' } }, function (res) {
            var body = '';
            res.setEncoding('utf8');
            res.on('data', function (chunk) {
                body += chunk;
                if (body.length > 500000) { finish(new Error('翻译响应过大')); req.destroy(); }
            });
            res.on('error', function (err) { finish(err); });
            res.on('end', function () {
                try {
                    if (res.statusCode !== 200) throw new Error('翻译服务状态 ' + res.statusCode);
                    var data = JSON.parse(body);
                    if (!Array.isArray(data[0])) throw new Error('无法解析翻译响应');
                    var result = data[0].map(function (row) { return row && row[0] || ''; }).join('');
                    finish(null, result);
                } catch (error) { finish(error); }
            });
        });
        req.on('error', function (error) { finish(error); });
        timeout = setTimeout(function () { finish(new Error('翻译服务连接超时')); req.destroy(); }, 10000);
    }
    if (typeof module !== 'undefined' && module.exports && !(root && root.Game_Message)) {
        module.exports = { createTranslator: createTranslator, install: install };
    } else if (root && root.Game_Message && root.Window_Message && root.Bitmap) {
        try { install(root, nodeTransport); }
        catch (error) { console.warn('中文翻译插件启动失败，游戏保留原文：', error.message); }
    }
})(typeof window !== 'undefined' ? window : null);
