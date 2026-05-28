// Chat with a local LLM via any OpenAI-compatible backend (Ollama,
// LM Studio, …). Conversations and messages persist in SQLite
// (QtQuick.LocalStorage). Responses stream in as SSE via curl piped
// through SplitParser, line by line.

import QtQuick
import QtQuick.LocalStorage
import Quickshell.Io
import ".."

Provider {
    id: prov

    name: "Chat"
    tag: "chat"
    iconText: "󰭹"
    description: "Chat with local LLM (OpenAI-compatible)"
    shortcuts: ["?"]
    searchPlaceholder: "Ask chat"

    searchActions: [
        SearchAction {
            icon: "+"
            name: "New chat"
            onTriggered: prov.newConversation()
        }
    ]

    resultsLayout: "custom"
    requestedWidth: 880
    requestedHeight: 640

    aggregateInSearch: false

    property var backends: [
        ({ id: "ollama",   name: "Ollama",    baseUrl: "http://localhost:11434/v1" }),
        ({ id: "lmstudio", name: "LM Studio", baseUrl: "http://localhost:1234/v1"  })
    ]
    property int currentBackendIdx: 0
    readonly property var currentBackend: backends[currentBackendIdx] || backends[0]

    property string currentModel: ""
    property var availableModels: []

    property var conversations: []
    property string currentConversationId: ""
    property var currentMessages: []

    property bool sending: false
    property string pendingAssistant: ""
    property string lastError: ""

    // "" | "backend" | "model" — which header dropdown is open.
    property string openDropdown: ""

    property var _db: null
    property string _streamConvId: ""
    property string _streamBuffer: ""
    property string _rawStdout: ""
    // Tracks the transition between reasoning_content and content chunks
    // (Qwen, DeepSeek, etc. reasoning models) so we can drop a separator
    // between thinking and the actual answer.
    property string _lastDeltaKind: ""

    function _newId() {
        return Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
    }

    function _openDb() {
        _db = LocalStorage.openDatabaseSync("arch-rising", "1.0", "Launcher data", 5000000);
        _db.transaction(tx => {
            tx.executeSql('CREATE TABLE IF NOT EXISTS conversations ('
                + 'id TEXT PRIMARY KEY,'
                + 'title TEXT,'
                + 'model TEXT,'
                + 'backend TEXT,'
                + 'created_at INTEGER,'
                + 'updated_at INTEGER)');
            tx.executeSql('CREATE TABLE IF NOT EXISTS messages ('
                + 'id INTEGER PRIMARY KEY AUTOINCREMENT,'
                + 'conversation_id TEXT NOT NULL,'
                + 'role TEXT NOT NULL,'
                + 'content TEXT NOT NULL,'
                + 'created_at INTEGER NOT NULL)');
            tx.executeSql('CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages(conversation_id, created_at)');
        });
        // Idempotent: adds `backend` to conversations tables created
        // before that column existed. Throws "duplicate column" on
        // repeat runs — harmless.
        try {
            _db.transaction(tx => tx.executeSql('ALTER TABLE conversations ADD COLUMN backend TEXT'));
        } catch (e) {}
        console.log("ChatProvider: SQLite at", LocalStorage.databasesPath);
    }

    function _loadConversations() {
        const out = [];
        _db.readTransaction(tx => {
            const rs = tx.executeSql('SELECT id, title, model, backend, created_at, updated_at FROM conversations ORDER BY updated_at DESC');
            for (let i = 0; i < rs.rows.length; i++) {
                const r = rs.rows.item(i);
                out.push({ id: r.id, title: r.title, model: r.model, backend: r.backend, created_at: r.created_at, updated_at: r.updated_at });
            }
        });
        conversations = out;
    }

    function _loadMessages(convId) {
        const out = [];
        _db.readTransaction(tx => {
            const rs = tx.executeSql('SELECT role, content, created_at FROM messages WHERE conversation_id = ? ORDER BY created_at ASC, id ASC', [convId]);
            for (let i = 0; i < rs.rows.length; i++) {
                const r = rs.rows.item(i);
                out.push({ role: r.role, content: r.content, created_at: r.created_at });
            }
        });
        currentMessages = out;
    }

    function selectConversation(id) {
        if (sending) return;
        currentConversationId = id;
        _loadMessages(id);
        lastError = "";
    }

    function newConversation() {
        if (sending) return;
        currentConversationId = "";
        currentMessages = [];
        lastError = "";
    }

    function deleteConversation(id) {
        if (sending) return;
        _db.transaction(tx => {
            tx.executeSql('DELETE FROM messages WHERE conversation_id = ?', [id]);
            tx.executeSql('DELETE FROM conversations WHERE id = ?', [id]);
        });
        if (currentConversationId === id) newConversation();
        _loadConversations();
    }

    function stopStream() {
        if (!sending) return;
        streamProc.running = false;
    }

    function setBackend(idx) {
        if (sending) return;
        if (idx < 0 || idx >= backends.length) return;
        if (idx === currentBackendIdx) return;
        currentBackendIdx = idx;
        availableModels = [];
        currentModel = "";
        lastError = "";
        _fetchModels();
    }

    function _ensureConversation(firstMessage) {
        if (currentConversationId.length > 0) return currentConversationId;
        const id = _newId();
        const now = Date.now();
        const title = (firstMessage || "New chat").slice(0, 60);
        _db.transaction(tx => {
            tx.executeSql('INSERT INTO conversations(id, title, model, backend, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
                [id, title, currentModel, currentBackend.id, now, now]);
        });
        currentConversationId = id;
        return id;
    }

    function _appendMessage(convId, role, content) {
        const now = Date.now();
        _db.transaction(tx => {
            tx.executeSql('INSERT INTO messages(conversation_id, role, content, created_at) VALUES (?, ?, ?, ?)',
                [convId, role, content, now]);
            tx.executeSql('UPDATE conversations SET updated_at = ? WHERE id = ?', [now, convId]);
        });
        currentMessages = currentMessages.concat([{ role: role, content: content, created_at: now }]);
    }

    Process {
        id: streamProc
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                prov._rawStdout += line + "\n";
                prov._onStreamLine(line);
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if (!line || !line.length) return;
                console.log("ChatProvider: curl stderr:", line);
                prov.lastError = line;
            }
        }
        onRunningChanged: if (!running) prov._onStreamDone()
    }

    function sendMessage(text) {
        const t = (text || "").trim();
        if (!t.length || sending) return;
        if (!currentModel.length) {
            lastError = "No model loaded in " + currentBackend.name;
            return;
        }
        const convId = _ensureConversation(t);
        _appendMessage(convId, "user", t);
        _loadConversations();
        lastError = "";
        _startStream(convId);
    }

    function _startStream(convId) {
        const be = currentBackend;
        const msgs = currentMessages.map(m => ({ role: m.role, content: m.content }));
        const body = JSON.stringify({ model: currentModel, messages: msgs, stream: true });
        _streamConvId = convId;
        _streamBuffer = "";
        _rawStdout = "";
        _lastDeltaKind = "";
        pendingAssistant = "";
        sending = true;
        streamProc.command = [
            "curl", "-N", "-sS",
            "-X", "POST",
            "-H", "content-type: application/json",
            "-H", "accept: text/event-stream",
            "-d", body,
            be.baseUrl + "/chat/completions"
        ];
        streamProc.running = true;
    }

    function _onStreamLine(line) {
        if (!line) return;
        // Quickshell's SplitParser preserves the splitMarker at the
        // start of subsequent emissions, so SSE events past the first
        // arrive as "\ndata: {…}". Strip surrounding whitespace before
        // the prefix check.
        line = line.trim();
        if (!line.length) return;
        if (line.indexOf("data:") !== 0) return;
        const payload = line.slice(5).trim();
        if (!payload.length || payload === "[DONE]") return;
        try {
            const d = JSON.parse(payload);
            if (d.error) {
                lastError = (d.error && d.error.message) || JSON.stringify(d.error);
                return;
            }
            const ch = d.choices && d.choices[0];
            const delta = ch && (ch.delta || ch.message);
            const reasoning = delta && typeof delta.reasoning_content === "string" ? delta.reasoning_content : "";
            const content   = delta && typeof delta.content === "string" ? delta.content : "";
            if (reasoning.length) {
                if (_lastDeltaKind === "content") _streamBuffer += "\n\n";
                _streamBuffer += reasoning;
                _lastDeltaKind = "reasoning";
            }
            if (content.length) {
                if (_lastDeltaKind === "reasoning") _streamBuffer += "\n\n";
                _streamBuffer += content;
                _lastDeltaKind = "content";
            }
            if (reasoning.length || content.length)
                pendingAssistant = _streamBuffer;
        } catch (e) {
            console.warn("ChatProvider: bad SSE line:", e, line);
        }
    }

    function _onStreamDone() {
        if (!sending) return;
        sending = false;
        let buf = _streamBuffer;
        const convId = _streamConvId;
        const raw = _rawStdout;
        // Fallback: some backends (LM Studio especially on errors) return
        // a single non-streaming JSON blob even when stream:true was sent.
        // If the SSE buffer is empty but stdout has content, try a flat
        // parse of the whole response.
        if (buf.length === 0 && raw.trim().length > 0) {
            try {
                const d = JSON.parse(raw.trim());
                if (d.error) {
                    lastError = (d.error && d.error.message) || JSON.stringify(d.error);
                } else {
                    const ch = d.choices && d.choices[0];
                    const msg = ch && (ch.message || ch.delta);
                    const content = msg && typeof msg.content === "string" ? msg.content : "";
                    if (content.length) buf = content;
                }
            } catch (e) {
                console.warn("ChatProvider._onStreamDone: raw stdout was not JSON:",
                    raw.slice(0, 500));
            }
        }

        _streamConvId = "";
        _streamBuffer = "";
        _rawStdout = "";
        pendingAssistant = "";
        if (convId && buf.length > 0)
            _appendMessage(convId, "assistant", buf);
        else if (convId && lastError.length === 0)
            lastError = currentBackend.name + " returned no content (is a model loaded?)";
        _loadConversations();
    }

    function _fetchModels() {
        const be = currentBackend;
        if (!be) return;
        const xhr = new XMLHttpRequest();
        xhr.open("GET", be.baseUrl + "/models");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== 4) return;
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    const data = JSON.parse(xhr.responseText);
                    const ms = (data.data || []).map(m => m.id);
                    availableModels = ms;
                    currentModel = ms.length > 0 ? ms[0] : "";
                    lastError = ms.length === 0
                        ? "No models loaded in " + be.name
                        : "";
                } catch (e) {
                    console.warn("ChatProvider: failed to parse /v1/models:", e);
                    lastError = "Bad response from " + be.name;
                }
            } else {
                availableModels = [];
                currentModel = "";
                lastError = "Cannot reach " + be.name + " at " + be.baseUrl;
            }
        };
        xhr.send();
    }

    Component.onCompleted: {
        _openDb();
        _loadConversations();
        _fetchModels();
    }

    function search(text) {
        results = [];
    }

    function handleKey(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            const q = (query || "").trim();
            if (q.length > 0 && !sending) {
                sendMessage(q);
                requestEnter("Chat", "");
            }
            return true;
        }
        return false;
    }

    function goBack() {
        if (openDropdown.length > 0) {
            openDropdown = "";
            return true;
        }
        return false;
    }

    function reset() {
        currentConversationId = "";
        currentMessages = [];
        lastError = "";
        openDropdown = "";
    }

    customComponent: Component {
        ChatView {}
    }
}
