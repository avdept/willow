// GitHub provider — flat search across your PRs, issues, projects, and
// repos via the `gh` CLI. All four kinds appear in one list (distinguished
// by a colored tag pill); type to filter the whole set. Activation opens
// the item's URL via xdg-open.
//
// On selection, a side-by-side DetailsPane shows the item's metadata
// (state, author, dates, body, …). Details are fetched lazily with a
// single GraphQL `resource(url:)` query, debounced and cached per URL.
//
// Required `gh` scopes: `repo`, `read:org`, `read:project`. Missing
// `read:project` just makes the projects list empty — run
// `gh auth refresh -s read:project` to enable.

import QtQuick
import Quickshell.Io

Provider {
    id: prov

    // ── Identity ─────────────────────────────────────────────────────────
    name: "GitHub"
    tag: "github"
    iconText: ""
    description: "Search PRs, issues, and repos"
    shortcuts: ["gh", "github"]

    // ── Launcher-facing config ───────────────────────────────────────────
    // `detailsEnabled` flips on once the auth check passes; until then
    // (and forever, if auth fails) the side-by-side details pane is
    // suppressed and the popup uses the launcher's default width.
    detailsEnabled: false
    detailWidth: 420
    requestedWidth: _ghReady ? 1080 : 0

    // ── Cached list data (populated at startup, reused across opens) ─────
    property var _prs: []
    property var _issues: []
    property var _projects: []
    property var _repos: []
    property string _viewerLogin: ""   // for personal-project avatars
    property int _pending: 0           // open initial-list `gh` calls

    // ── Per-URL detail cache ─────────────────────────────────────────────
    property var _detailCache: ({})
    // Wait this long after the selection settles before firing the detail
    // call. Stops a fetch per row when the user sweeps the mouse.
    readonly property int _fetchDebounceMs: 300

    // True once `gh auth status` succeeds. Until then (and forever, if it
    // fails) the list fetches don't run and the empty-state surfaces a
    // remediation hint. Re-checked once per launcher startup.
    property bool _ghReady: false

    Component.onCompleted: _checkAuth()

    // ════════════════════════════════════════════════════════════════════
    // gh availability / auth check
    // ════════════════════════════════════════════════════════════════════

    function _checkAuth() {
        emptyStateText = "Checking GitHub CLI…";
        results = [];
        authCheckProc._buf = "";
        if (authCheckProc.running)
            authCheckProc.running = false;
        authCheckProc.running = true;
    }

    Process {
        id: authCheckProc
        running: false
        // Three possible outputs:
        //   MISSING — gh isn't on PATH
        //   UNAUTH  — gh is installed but `gh auth status` fails
        //   OK      — both fine
        command: ["sh", "-c", `
            if ! command -v gh >/dev/null 2>&1; then echo MISSING
            elif ! gh auth status >/dev/null 2>&1; then echo UNAUTH
            else echo OK
            fi
        `]
        property string _buf: ""
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => authCheckProc._buf += line
        }
        onRunningChanged: if (!running)
            prov._onAuthChecked(_buf.trim())
    }

    function _onAuthChecked(state) {
        if (state === "OK") {
            _ghReady = true;
            detailsEnabled = true;
            _refetchAll();
            return;
        }
        _ghReady = false;
        detailsEnabled = false;
        results = [];
        emptyStateText = state === "MISSING" ? "GitHub CLI (`gh`) is not installed — install the `github-cli` package to enable this category." : "Not signed in to GitHub — run `gh auth login` in a terminal, then restart Quickshell.";
    }

    // ════════════════════════════════════════════════════════════════════
    // Initial-list fetches
    // ════════════════════════════════════════════════════════════════════

    function _refetchAll() {
        _prs = [];
        _issues = [];
        _projects = [];
        _repos = [];
        _pending = 4;
        emptyStateText = "Loading…";
        prsBuf = issuesBuf = projectsBuf = reposBuf = "";
        for (const p of [prsProc, issuesProc, projectsProc, reposProc]) {
            if (p.running)
                p.running = false;
            p.running = true;
        }
    }

    function _onFetchDone() {
        _pending = Math.max(0, _pending - 1);
        if (_pending === 0)
            emptyStateText = "";
        refresh();
    }

    // Parse JSON or return the default on failure (and warn once).
    function _parseJson(buf, dflt, label) {
        try {
            return JSON.parse(buf || dflt);
        } catch (e) {
            console.warn("[GithubProvider] " + label + " JSON parse:", e);
            return JSON.parse(dflt);
        }
    }

    // PRs and issues share a JSON shape, so they share a mapper.
    function _mapPrOrIssue(arr, kind) {
        return arr.map(it => ({
                    kind: kind,
                    title: it.title,
                    repo: it.repository ? it.repository.nameWithOwner : "",
                    num: it.number,
                    url: it.url
                }));
    }

    property string prsBuf: ""
    Process {
        id: prsProc
        running: false
        command: ["gh", "search", "prs", "--involves", "@me", "--state", "open", "--json", "number,title,url,repository", "--limit", "50"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => prov.prsBuf += line
        }
        onRunningChanged: if (!running) {
            prov._prs = prov._mapPrOrIssue(prov._parseJson(prov.prsBuf, "[]", "PRs"), "pr");
            prov._onFetchDone();
        }
    }

    property string issuesBuf: ""
    Process {
        id: issuesProc
        running: false
        command: ["gh", "search", "issues", "--involves", "@me", "--state", "open", "--json", "number,title,url,repository", "--limit", "50"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => prov.issuesBuf += line
        }
        onRunningChanged: if (!running) {
            prov._issues = prov._mapPrOrIssue(prov._parseJson(prov.issuesBuf, "[]", "issues"), "issue");
            prov._onFetchDone();
        }
    }

    // Projects V2 (viewer-owned + each org's). Silently empty without
    // the `read:project` scope.
    property string projectsBuf: ""
    Process {
        id: projectsProc
        running: false
        command: ["gh", "api", "graphql", "-f", "query=" + `
            {
              viewer {
                login
                projectsV2(first: 50, query: "is:open") { nodes { number title url } }
                organizations(first: 30) {
                  nodes {
                    login
                    projectsV2(first: 30, query: "is:open") { nodes { number title url } }
                  }
                }
              }
            }
        `]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => prov.projectsBuf += line
        }
        onRunningChanged: if (!running) {
            const viewer = prov._parseJson(prov.projectsBuf, "{}", "projects")?.data?.viewer || {};
            prov._viewerLogin = viewer.login || "";
            const out = (viewer.projectsV2?.nodes || []).map(p => ({
                        kind: "project",
                        title: p.title,
                        repo: prov._viewerLogin || "@me",
                        num: p.number,
                        url: p.url
                    }));
            for (const org of (viewer.organizations?.nodes || []))
                for (const p of (org.projectsV2?.nodes || []))
                    out.push({
                        kind: "project",
                        title: p.title,
                        repo: org.login,
                        num: p.number,
                        url: p.url
                    });
            prov._projects = out;
            prov._onFetchDone();
        }
    }

    // Repos across personal + org-member + collaborator affiliations.
    // GraphQL caps `first` at 100 so we paginate with gh and merge with
    // jq. Sorted by most-recently-pushed.
    property string reposBuf: ""
    Process {
        id: reposProc
        running: false
        command: ["sh", "-c", `
            gh api --paginate graphql -f query='
              query($endCursor: String) {
                viewer {
                  repositories(
                    first: 100,
                    after: $endCursor,
                    ownerAffiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER],
                    orderBy: { field: PUSHED_AT, direction: DESC }
                  ) {
                    pageInfo { hasNextPage endCursor }
                    nodes { name nameWithOwner description url isPrivate }
                  }
                }
              }' 2>/dev/null \
              | jq -s 'reduce .[] as $r ([]; . + ($r.data.viewer.repositories.nodes // []))'
        `]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => prov.reposBuf += line
        }
        onRunningChanged: if (!running) {
            const arr = prov._parseJson(prov.reposBuf, "[]", "repos");
            prov._repos = arr.map(it => ({
                        kind: "repo",
                        title: it.nameWithOwner,
                        repo: "",
                        desc: it.description || "",
                        isPrivate: !!it.isPrivate,
                        url: it.url
                    }));
            prov._onFetchDone();
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Search, row rendering, activation
    // ════════════════════════════════════════════════════════════════════

    // Baseline score when no query is typed — PRs first, repos last.
    // Within each kind, items keep their fetch order (gh returns by recency).
    readonly property var _KIND_BASE: ({
            pr: 4000,
            issue: 3000,
            project: 2000,
            repo: 1000
        })

    // Per-kind row presentation (tag pill, color, fallback glyph).
    readonly property var _KIND_META: ({
            pr: {
                tag: "pr",
                color: "success",
                icon: ""
            },
            issue: {
                tag: "issue",
                color: "warn",
                icon: ""
            },
            project: {
                tag: "project",
                color: "purple",
                icon: ""
            },
            repo: {
                tag: "repo",
                color: "info",
                icon: ""
            }
        })

    function search(text) {
        const q = (text || "").toLowerCase().trim();
        const out = [];

        function _emit(it, i) {
            const lcTitle = it.title.toLowerCase();
            const lcRepo = (it.repo || it.title).toLowerCase();
            const lcDesc = (it.desc || "").toLowerCase();
            let score;
            if (q.length === 0)
                score = _KIND_BASE[it.kind] - i;
            else if (lcTitle === q)
                score = 1000;
            else if (lcTitle.startsWith(q))
                score = 700;
            else if (lcTitle.indexOf(q) !== -1)
                score = 400;
            else if (lcRepo.indexOf(q) !== -1)
                score = 200;
            else if (it.kind === "repo" && lcDesc.indexOf(q) !== -1)
                score = 80;
            else
                return;
            out.push(_toRow(it, score));
        }

        for (const list of [_prs, _issues, _projects, _repos])
            for (let i = 0; i < list.length; i++)
                _emit(list[i], i);

        out.sort((a, b) => b.score - a.score);
        results = out;
    }

    function _toRow(it, score) {
        const meta = _KIND_META[it.kind];
        const owner = _ownerLogin(it);
        return {
            title: it.title,
            subtitle: _subtitleFor(it),
            iconUrl: owner ? ("https://github.com/" + owner + ".png?size=64") : "",
            iconText: (it.kind === "repo" && it.isPrivate) ? "" : meta.icon,
            providerTag: meta.tag,
            tagColor: meta.color,
            score: score,
            data: {
                kind: it.kind,
                url: it.url
            }
        };
    }

    function _subtitleFor(it) {
        if (it.kind === "repo")
            return it.desc || "";
        if (it.kind === "project")
            return it.repo + " · project #" + it.num;
        return it.repo + " #" + it.num;        // pr / issue
    }

    // First slash-separated segment of the owner-bearing field —
    // `it.repo` for pr/issue/project, `it.title` for repo.
    function _ownerLogin(it) {
        const s = (it.kind === "repo" ? it.title : it.repo) || "";
        return s.split("/")[0];
    }

    function activate(result) {
        const url = result?.data?.url;
        if (!url)
            return;
        openProc.command = ["xdg-open", url];
        if (openProc.running)
            openProc.running = false;
        openProc.running = true;
    }

    Process {
        id: openProc
        running: false
    }

    // ════════════════════════════════════════════════════════════════════
    // Details pane — selection → debounce → graphql → render
    // ════════════════════════════════════════════════════════════════════

    onSelectedRowChanged: _onSelectionChanged()

    function _onSelectionChanged() {
        const r = selectedRow;
        if (!r || !r.data || !r.data.url) {
            detail = null;
            detailDebounce.stop();
            return;
        }
        if (_detailCache[r.data.url]) {
            detail = _detailCache[r.data.url];
            detailDebounce.stop();
            return;
        }
        // Show what we already know from the row, then debounce the fetch.
        detail = {
            loading: true,
            iconUrl: r.iconUrl,
            iconText: r.iconText,
            title: r.title,
            subtitle: r.subtitle
        };
        detailDebounce.restart();
    }

    Timer {
        id: detailDebounce
        interval: prov._fetchDebounceMs
        repeat: false
        onTriggered: {
            const r = prov.selectedRow;
            if (!r || !r.data || !r.data.url)
                return;
            // Race-guard: an earlier in-flight fetch may have landed
            // during the wait and populated the cache.
            if (prov._detailCache[r.data.url]) {
                prov.detail = prov._detailCache[r.data.url];
                return;
            }
            prov._fetchDetailFor(r);
        }
    }

    function _fetchDetailFor(row) {
        if (row.data?.kind === "project") {
            // No rich detail source for ProjectsV2 — synthesize from the row.
            const out = _stubDetail(row, "open", "purple");
            _detailCache[row.data.url] = out;
            detail = out;
            return;
        }
        _startDetailFetch(row);
    }

    function _stubDetail(row, stateText, stateColor) {
        return {
            iconUrl: row.iconUrl,
            iconText: row.iconText,
            title: row.title,
            subtitle: row.subtitle,
            state: {
                text: stateText,
                color: stateColor
            },
            meta: [],
            body: ""
        };
    }

    // Single GraphQL query — `resource(url:)` resolves any github.com URL
    // to a typed node (PullRequest / Issue / Repository). __typename
    // selects the matching builder below.
    readonly property string _detailQuery: `
        query($url: URI!) {
          resource(url: $url) {
            __typename
            ... on PullRequest {
              title state isDraft createdAt updatedAt body baseRefName headRefName
              author { login }
              labels(first: 10) { nodes { name } }
            }
            ... on Issue {
              title state createdAt updatedAt body
              author { login }
              labels(first: 10) { nodes { name } }
            }
            ... on Repository {
              nameWithOwner description isPrivate isArchived isFork
              stargazerCount forkCount pushedAt
              primaryLanguage { name }
              defaultBranchRef { name }
              licenseInfo { spdxId }
              issues(states: OPEN) { totalCount }
            }
          }
        }
    `

    // In-flight detail request.
    property string detailReqUrl: ""
    property var detailReqRow: null
    property string detailBuf: ""
    property string detailErrBuf: ""

    function _startDetailFetch(row) {
        detailReqUrl = row.data.url;
        detailReqRow = row;
        detailBuf = "";
        detailErrBuf = "";
        if (detailProc.running)
            detailProc.running = false;
        detailProc.command = ["gh", "api", "graphql", "-f", "url=" + row.data.url, "-f", "query=" + _detailQuery];
        detailProc.running = true;
    }

    Process {
        id: detailProc
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => prov.detailBuf += line
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: line => prov.detailErrBuf += line + "\n"
        }
        onRunningChanged: if (!running)
            prov._onDetailDone()
    }

    function _onDetailDone() {
        const buf = detailBuf;
        const errBuf = detailErrBuf;
        detailBuf = detailErrBuf = "";

        // Bail if the selection moved on while we were fetching.
        if (!detailReqRow || (selectedRow && selectedRow.data && selectedRow.data.url !== detailReqUrl))
            return;
        if (!buf || buf.trim().length === 0) {
            const msg = (errBuf.split("\n").find(l => l.trim().length > 0) || "").trim();
            _detailError(msg || "gh returned no data");
            return;
        }

        let parsed;
        try {
            parsed = JSON.parse(buf);
        } catch (e) {
            _detailError("Failed to parse response");
            return;
        }

        const node = parsed?.data?.resource;
        if (!node) {
            _detailError("URL didn't resolve");
            return;
        }

        let out;
        if (node.__typename === "PullRequest" || node.__typename === "Issue")
            out = _buildPrIssueDetail(detailReqRow, node);
        else if (node.__typename === "Repository")
            out = _buildRepoDetail(detailReqRow, node);
        else {
            _detailError("Unsupported type: " + node.__typename);
            return;
        }

        _detailCache[detailReqUrl] = out;
        detail = out;
    }

    function _detailError(msg) {
        detail = Object.assign({}, detail, {
            loading: false,
            error: msg
        });
    }

    function _buildPrIssueDetail(row, n) {
        const isPr = n.__typename === "PullRequest";
        const state = (n.state || "").toLowerCase();           // GraphQL is uppercase
        const pillColor = n.isDraft ? "border" : state === "closed" ? "danger" : state === "merged" ? "purple" : "success";

        const meta = [];
        if (n.author?.login)
            meta.push({
                label: "Author",
                value: "@" + n.author.login
            });
        if (n.createdAt)
            meta.push({
                label: "Opened",
                value: _formatDate(n.createdAt)
            });
        if (n.updatedAt)
            meta.push({
                label: "Updated",
                value: _formatDate(n.updatedAt)
            });
        if (isPr && n.headRefName && n.baseRefName)
            meta.push({
                label: "Branch",
                value: n.headRefName + " → " + n.baseRefName
            });
        const labels = (n.labels?.nodes || []).map(l => l.name);
        if (labels.length > 0)
            meta.push({
                label: "Labels",
                value: labels.join(", ")
            });

        return {
            iconUrl: row.iconUrl,
            iconText: row.iconText,
            title: n.title || row.title,
            subtitle: row.subtitle,
            state: {
                text: n.isDraft ? "draft" : state,
                color: pillColor
            },
            meta: meta,
            body: _truncate(n.body || "", 2000)
        };
    }

    function _buildRepoDetail(row, n) {
        const meta = [];
        if (n.primaryLanguage?.name)
            meta.push({
                label: "Language",
                value: n.primaryLanguage.name
            });
        if (typeof n.stargazerCount === "number")
            meta.push({
                label: "Stars",
                value: String(n.stargazerCount)
            });
        if (typeof n.forkCount === "number")
            meta.push({
                label: "Forks",
                value: String(n.forkCount)
            });
        if (n.issues?.totalCount != null)
            meta.push({
                label: "Open issues",
                value: String(n.issues.totalCount)
            });
        if (n.defaultBranchRef?.name)
            meta.push({
                label: "Default",
                value: n.defaultBranchRef.name
            });
        if (n.pushedAt)
            meta.push({
                label: "Pushed",
                value: _formatDate(n.pushedAt)
            });
        if (n.licenseInfo?.spdxId)
            meta.push({
                label: "License",
                value: n.licenseInfo.spdxId
            });

        const state = n.isArchived ? {
            text: "archived",
            color: "warn"
        } : n.isFork ? {
            text: "fork",
            color: "border"
        } : null;

        return {
            iconUrl: row.iconUrl,
            iconText: row.iconText,
            title: n.nameWithOwner || row.title,
            subtitle: n.isPrivate ? "Private" : "Public",
            state: state,
            meta: meta,
            body: n.description || ""
        };
    }

    function _truncate(s, n) {
        if (!s)
            return "";
        return s.length > n ? (s.slice(0, n) + "…") : s;
    }

    // "2026-05-21T08:12:34Z" → "2026-05-21" (display only — no tz math).
    function _formatDate(iso) {
        if (!iso)
            return "";
        const t = iso.indexOf("T");
        return t > 0 ? iso.slice(0, t) : iso;
    }
}
