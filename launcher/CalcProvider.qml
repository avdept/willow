// Calc provider — inline math evaluator. Triggers on a leading `=`
// so it never competes with normal queries. JS Function() eval over a
// strict character allowlist (digits + math operators); rejects
// anything else without spawning a subprocess, so it's fast enough to
// run on every keystroke. Score 10000 keeps the result pinned to the
// top of the aggregated list.

import QtQuick

Provider {
    id: prov

    name: "Calc"
    tag: "calc"
    iconText: ""
    description: "Inline calculator (=5+5)"
    showAsCategory: false

    // Always-on. We don't use the prefix system because it requires a
    // trailing space (`= 5+5`); the leading `=` is checked manually so
    // `=5+5` works.
    prefix: ""

    // Strict allowlist: digits, decimal, math operators, parens, spaces.
    // `^` is rewritten to `**` after this check passes.
    readonly property var _allowed: /^[0-9+\-*\/%^().\s]+$/

    function search(text) {
        const q = (text || "").trim();
        if (q.length < 2 || q[0] !== "=") {
            results = [];
            return;
        }
        const expr = q.slice(1).trim();
        if (expr.length === 0 || !_allowed.test(expr)) {
            results = [];
            return;
        }
        let value;
        try {
            const jsExpr = expr.replace(/\^/g, "**");
            value = (new Function('"use strict"; return (' + jsExpr + ')'))();
        } catch (e) {
            results = [];
            return;
        }
        if (typeof value !== "number" || !isFinite(value)) {
            results = [];
            return;
        }
        // Trim trailing zeros on decimals; leave integers untouched.
        const display = Number.isInteger(value)
            ? String(value)
            : String(parseFloat(value.toFixed(10)));
        results = [{
            title:    display,
            subtitle: "Enter to copy",
            iconText: "",
            score:    10000,
            tagColor: "accent",
            data:     { value: display }
        }];
    }

    function activate(result) {
        const v = result?.data?.value;
        if (!v) return;
        openExternal(["sh", "-c",
            "printf %s '" + String(v).replace(/'/g, "'\\''") + "' | wl-copy"]);
    }
}
