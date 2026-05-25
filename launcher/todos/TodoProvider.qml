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
    // Card width grows when the form is open so the sidebar slides into
    // fresh space instead of squashing the list.
    readonly property int _baseWidth: 880
    readonly property int _sidebarWidth: 340
    requestedWidth: _baseWidth + (formOpen ? _sidebarWidth : 0)
    requestedHeight: 640

    property var todos: []
    // openForm() / closeForm() are the only ways to flip `formOpen` so
    // focus restoration in Launcher.qml's Connections can react.
    property bool formOpen: false
    // Empty = create mode, set = editing existing.
    property string editingId: ""
    // Hydration values for the form on open; form reads on formOpen rising
    // edge via its Connections block.
    property var editingDraft: ({})

    // Pass an existing todo id to edit; no args to create.
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

    // Search input does double duty: search() populates aggregated
    // menu-mode results, and `searchQuery` filters the in-view list
    // via filteredTodos.
    property string searchQuery: ""

    // Bound from NowProvider's todos tile via Launcher.qml.
    readonly property int unfinishedCount: todos.filter(t => !t.completed_on).length

    function _score(t, q) {
        let best = scoreText(q, norm(t.name), norm(t.description));
        const tags = t.tags || [];
        for (let i = 0; i < tags.length; i++) {
            const s = scoreText(q, norm(tags[i])) * 0.4;
            if (s > best) best = s;
        }
        // Completed todos still match, but rank below pending ones with
        // the same query strength.
        return t.completed_on ? best * 0.3 : best;
    }

    function search(text) {
        const q = norm(text);
        searchQuery = q;
        if (!q) { results = []; return; }
        const out = [];
        for (let i = 0; i < todos.length; i++) {
            const t = todos[i];
            const s = _score(t, q);
            if (s <= 0) continue;
            out.push({
                title: t.name || "(untitled)",
                subtitle: t.completed_on
                    ? "Completed " + (t.completed_on || "").slice(0, 10)
                    : (t.description || (t.due_date ? "Due " + t.due_date : "")),
                score: s,
                tagColor: t.completed_on ? "success" : "info",
                data: t,
            });
        }
        results = out;
    }

    function activate(result) {
        if (!result || !result.data) return;
        openForm(result.data.id);
        requestEnter("Todos", searchQuery);
        return true;
    }

    function invokeAction(name, rest) {
        if (name === "new") {
            // Skip openForm() so we can seed the draft with what the
            // user typed after the shortcut.
            editingId = "";
            editingDraft = { name: (rest || "").trim() };
            formOpen = true;
        }
    }

    // Model for TodoView's ListView. Filtered by searchQuery so typing
    // narrows the visible list live.
    readonly property var filteredTodos: {
        const q = searchQuery;
        const cutoff = Date.now() - 24 * 60 * 60 * 1000;

        let list = q ? todos.filter(t => _score(t, q) > 0) : todos.slice();

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
