// Todo provider — JSON-backed task list with reminders.
//
// Data lives in todos.json next to this file. CRUD mutates `todos`
// and persists immediately via FileView.setText.
//
// UI lives in TodoView (the customComponent root) and TodoForm
// (the "new todo" sidebar that opens when `formOpen` is true).
//
// Schema per todo (see addTodo() for defaults):
//   id            string   opaque, generated
//   name          string
//   description   string
//   due_date      string?  ISO-8601 or null
//   completed_on  string?  ISO-8601 or null
//   created_at    string   ISO-8601
//   priority      string   "low" | "medium" | "high"
//   tags          string[]
//   reminder_at   string?  ISO-8601 or null

import QtQuick
import Quickshell.Io
import ".."
import "."

Provider {
    id: prov

    name: "Todos"
    tag: "todos"
    iconText: ""
    description: "Tasks & reminders"
    shortcuts: ["t", "todo", "todos"]
    // `+t` (alone or `+t buy milk`) drills in and opens the New-Todo
    // form with the trailing text pre-filled as the name. See
    // invokeAction() below for the handler.
    actionShortcuts: ({ "+t": "new" })

    resultsLayout: "custom"
    // Card width grows by `_sidebarWidth` when the form is open so the
    // sidebar slides into freshly-allocated space instead of squashing
    // the list. The launcher animates card.width via its existing
    // Behavior; TodoView's sidebar matches the same duration/easing.
    readonly property int _baseWidth: 880
    readonly property int _sidebarWidth: 340
    requestedWidth: _baseWidth + (formOpen ? _sidebarWidth : 0)
    requestedHeight: 640

    // ── State ───────────────────────────────────────────────────────────
    property var todos: []
    // When true, the right side of TodoView reveals a form sidebar.
    // openForm() / closeForm() are the only ways to flip this so
    // focus management (see Launcher.qml's Connections on todoProv)
    // can react.
    property bool formOpen: false
    // Empty = creating a new todo. Set = editing an existing one.
    property string editingId: ""
    // Field values to hydrate the form with on open. Set by openForm()
    // (empty for create mode, pre-filled for edit mode); the form
    // reads it on formOpen → true via its Connections block.
    property var editingDraft: ({})

    // Open the form. Pass an existing todo id to enter edit mode;
    // call with no args to create a fresh todo.
    function openForm(id) {
        if (id) {
            const t = todos.find(x => x.id === id);
            if (!t)
                return;
            editingId = id;
            editingDraft = {
                name: t.name || "",
                description: t.description || "",
                due_date: t.due_date || "",
                priority: t.priority || "medium",
                tags: Array.isArray(t.tags) ? t.tags.join(", ") : "",
                reminder_at: t.reminder_at || ""
            };
        } else {
            editingId = "";
            editingDraft = {};
        }
        formOpen = true;
    }

    function closeForm() {
        formOpen = false;
        editingId = "";
        editingDraft = {};
    }

    // ── Persistence ─────────────────────────────────────────────────────
    FileView {
        id: store
        path: Qt.resolvedUrl("todos.json").toString().replace(/^file:\/\//, "")
        watchChanges: true
        onLoaded: prov._parse(text())
        onFileChanged: {
            reload();
        }
    }

    Component.onCompleted: store.reload()

    function _parse(src) {
        if (!src || !src.length) {
            todos = [];
            return;
        }
        try {
            const parsed = JSON.parse(src);
            todos = Array.isArray(parsed) ? parsed : [];
        } catch (e) {
            console.warn("TodoProvider: failed to parse todos.json:", e);
            todos = [];
        }
    }

    function _save() {
        store.setText(JSON.stringify(todos, null, 2) + "\n");
    }

    // ── CRUD ────────────────────────────────────────────────────────────
    function _newId() {
        return Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
    }

    function addTodo(fields) {
        const t = Object.assign({
            id: _newId(),
            name: "",
            description: "",
            due_date: null,
            completed_on: null,
            created_at: new Date().toISOString(),
            priority: "medium",
            tags: [],
            reminder_at: null
        }, fields || {});
        todos = todos.concat([t]);
        _save();
        return t.id;
    }

    function updateTodo(id, patch) {
        todos = todos.map(t => t.id === id ? Object.assign({}, t, patch) : t);
        _save();
    }

    function removeTodo(id) {
        todos = todos.filter(t => t.id !== id);
        _save();
    }

    function completeTodo(id) {
        updateTodo(id, {
            completed_on: new Date().toISOString()
        });
    }

    function uncompleteTodo(id) {
        updateTodo(id, {
            completed_on: null
        });
    }

    // ── Launcher contract ───────────────────────────────────────────────
    // The search input does double duty:
    //   • In menu mode, search() populates `results` so todos appear in
    //     the aggregated main-page search across all providers.
    //   • In provider mode, the same `searchQuery` filters the in-view
    //     list (see `filteredTodos` below).
    property string searchQuery: ""

    // Count of currently-active todos. Bound from NowProvider's
    // dashboard tile via Launcher.qml.
    readonly property int unfinishedCount: todos.filter(t => !t.completed_on).length

    function _matches(t, q) {
        if (!q) return true;
        return (t.name || "").toLowerCase().includes(q)
            || (t.description || "").toLowerCase().includes(q)
            || (t.tags || []).some(tag => (tag || "").toLowerCase().includes(q));
    }

    function search(text) {
        const q = (text || "").toLowerCase().trim();
        searchQuery = q;
        if (!q) { results = []; return; }
        const matches = todos.filter(t => _matches(t, q));
        results = matches.map(t => ({
            title: t.name || "(untitled)",
            subtitle: t.completed_on
                ? "Completed " + (t.completed_on || "").slice(0, 10)
                : (t.description || (t.due_date ? "Due " + t.due_date : "")),
            // Pending todos rank above completed ones in the merged list.
            score: t.completed_on ? 200 : 700,
            tagColor: t.completed_on ? "success" : "info",
            data: t,
        }));
    }

    function activate(result) {
        if (!result || !result.data) return;
        // Open the edit form for the chosen todo, then ask the launcher
        // to drill into this provider so the user actually sees it.
        openForm(result.data.id);
        requestEnter("Todos", searchQuery);
        return true;    // keep launcher open
    }

    // Handle action shortcuts registered above. Called by the launcher
    // after it has already drilled into this provider.
    function invokeAction(name, rest) {
        if (name === "new") {
            // Skip openForm() so we can seed the draft with whatever
            // the user typed after "+t " (the form's Connections
            // hydrate from editingDraft and focus the name input).
            editingId = "";
            editingDraft = { name: (rest || "").trim() };
            formOpen = true;
        }
    }

    // View-bound list: `todos` filtered by the current searchQuery.
    // Used as the model for TodoView's ListView so typing in the
    // search input narrows the visible list live.
    readonly property var filteredTodos: {
        const q = searchQuery;
        const cutoff = Date.now() - 24 * 60 * 60 * 1000;

        let list = q ? todos.filter(t => _matches(t, q)) : todos.slice();

        list = list.filter(t => {
            if (!t.completed_on) return true;
            const ms = Date.parse(t.completed_on);
            return isNaN(ms) || ms >= cutoff;
        });

        list.sort((a, b) => {
            const ad = !!a.completed_on, bd = !!b.completed_on;
            if (ad !== bd) return ad ? 1 : -1;
            return (b.created_at || "").localeCompare(a.created_at || "");
        });

        return list;
    }

    // First Escape closes the form sidebar; the launcher then handles
    // a second Escape (back to menu).
    function goBack() {
        if (formOpen) {
            closeForm();
            return true;
        }
        return false;
    }

    // Launcher resets every provider on close / return to menu — drop
    // the form and clear the filter so re-entry is clean.
    function reset() {
        formOpen = false;
        searchQuery = "";
    }

    customComponent: Component {
        TodoView {}
    }
}
