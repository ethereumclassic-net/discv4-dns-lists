#!/usr/bin/env bash
#
# Keep one status issue for the nightly run: rewrite it every run, and comment
# only when the state changes.
#
#   GITHUB_REPOSITORY=owner/repo GH_TOKEN=... \
#   ./scripts/report-status.sh <success|failure|cancelled> <run url> [run log] [bootnode status]
#
# A failing run must not be silent, and a run that keeps failing must not open
# an issue a night. So there is exactly one issue, labeled STATUS_LABEL and
# opened by the workflow itself, and every run rewrites its title and body with
# the latest result. GitHub notifies nobody of an edit, so the run also comments
# on the first failure after a success and on the first success after a failure:
# subscribing to the issue is how to be told about exactly those two events.
#
# The issue also lists the bootnodes Core-Geth ships and whether each answered
# the run's crawl, from the file update-lists.sh writes to BOOTNODE_STATUS. A
# bootnode that does not answer gets one comment, so subscribers hear of it
# once. The first run it answers again deletes that comment rather than adding
# another: the table already shows it answering, and a one-night miss then
# leaves nothing in the thread. A run without that file changes no bootnode
# comment, since it has nothing new to say about them.
#
# It also shows the trees the run built, one row per network, from the TREE
# lines update-lists.sh prints: each tree's nodes against its seats, how many of
# them first answered that run, how many nodes the per-address and per-subnet
# limits held back, and how the nodes that answered spread over addresses and
# over /24 or /48 networks.
#
# The issue is found by its label and its author, never its title. A bootnode
# comment is likewise found by its marker and its author, so a reader's comment
# that quotes one is never deleted. Only the run log's ERROR and WARNING lines,
# and the figures on its TREE lines, reach the issue, never the log itself,
# because the issue is public. A run that publishes can still warn -- most of a
# tree's addresses not answering, for one -- and its warnings are shown until
# the next run replaces them.
#
# Exit 0 reported, 1 could not report.

set -uo pipefail

[ $# -ge 2 ] || { echo "usage: $0 <success|failure|cancelled> <run url> [run log] [bootnode status]" >&2; exit 1; }
[ -n "${GITHUB_REPOSITORY:-}" ] || { echo "report-status: GITHUB_REPOSITORY is unset" >&2; exit 1; }

python3 - "$@" <<'PYEOF'
import datetime, json, os, re, subprocess, sys

outcome, run_url = sys.argv[1], sys.argv[2]
log = sys.argv[3] if len(sys.argv) > 3 else ""
boot_file = sys.argv[4] if len(sys.argv) > 4 else ""
gh = os.environ.get("GH", "gh")
repo = os.environ["GITHUB_REPOSITORY"]
label = os.environ.get("STATUS_LABEL", "pipeline-status")
now = os.environ.get("NOW") or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
BOTS = {"app/github-actions", "github-actions", "github-actions[bot]"}

def gh_run(args, body=None):
    r = subprocess.run([gh, *args, "--repo", repo], input=body, capture_output=True, text=True, encoding="utf-8")
    if r.returncode != 0:
        sys.exit("report-status: gh %s failed: %s" % (" ".join(args[:2]), r.stderr.strip()))
    return r.stdout

def gh_api(args):
    # `gh api` takes no --repo: its paths name the repository.
    r = subprocess.run([gh, "api", *args], capture_output=True, text=True, encoding="utf-8")
    if r.returncode != 0:
        sys.exit("report-status: gh api %s failed: %s" % (args[-1], r.stderr.strip()))
    return r.stdout

def pages(text):
    # `gh api --paginate` prints each page's JSON array in turn.
    dec, i, out = json.JSONDecoder(), 0, []
    while True:
        while i < len(text) and text[i].isspace():
            i += 1
        if i == len(text):
            return out
        page, i = dec.raw_decode(text, i)
        out.extend(page)

def shown(ts):
    # A crawler timestamp, written the way the rest of the issue writes times.
    return str(ts).replace("T", " ")[:16] + " UTC" if ts else None

# The run's ERROR and WARNING lines, bounded and unable to close the code fence, and the figures on
# its TREE lines.
FIGURES = ("nodes", "cap", "first_answered", "held_back")
SPREADS = ("per_address", "per_subnet")

def read_spread(v):
    # A TREE line's spread: at most 64 [nodes, how many] pairs of positive whole numbers.
    if not isinstance(v, list) or len(v) > 64 or not all(
            isinstance(p, list) and len(p) == 2 and all(type(x) is int and x > 0 for x in p) for p in v):
        raise ValueError("not a spread")
    return sorted(((p[0], p[1]) for p in v), reverse=True)

errors, warnings, trees = [], [], {}
if log and os.path.exists(log):
    for line in open(log, errors="replace"):
        if re.match(r"\s*ERROR:", line):
            errors.append(line.rstrip()[:240].replace("```", "'''"))
        elif re.match(r"\s*WARNING:", line):
            warnings.append(line.rstrip()[:240].replace("```", "'''"))
        elif re.match(r"\s*TREE: ", line):
            # One line per tree, and a network's tree is built alike on every domain, so keep one per
            # network. Only whole numbers reach the issue.
            try:
                t = json.loads(line.split("TREE: ", 1)[1])
                net = re.fullmatch(r"all\.([a-z]+)\.[A-Za-z0-9.-]+", t["tree"]).group(1)
                figures = {k: int(t[k]) for k in FIGURES}
                figures.update((k, read_spread(t[k])) for k in SPREADS)
            except (ValueError, KeyError, TypeError, AttributeError):
                continue
            if net not in trees and len(trees) < 10:
                trees[net] = figures
errors = errors[:20] or ["(no ERROR line in the run's output; see the run log)"]
warnings = warnings[:20]

# Whether each bootnode answered this run's crawl. A file that cannot be read is
# treated as no file: the run's own state must still be reported.
boot = None
if boot_file and os.path.exists(boot_file):
    try:
        boot = []
        for r in json.load(open(boot_file)):
            if not re.fullmatch(r"[0-9a-f]{16}", r["id"]) or not re.fullmatch(r"[a-z]+", r["network"]):
                raise ValueError("unexpected row %r" % (r,))
            boot.append({"id": r["id"], "network": r["network"], "answered": r["answered"] is True,
                         "host": re.sub(r"[^0-9A-Za-z.:\[\]-]", "", str(r["host"])),
                         "last_answered": shown(r.get("last_answered"))})
    except (ValueError, KeyError, TypeError) as e:
        print("report-status: ignoring %s: %s" % (boot_file, e), file=sys.stderr)
        boot = None

gh_run(["label", "create", label, "--color", "5319e7", "--force",
        "--description", "The nightly run's status issue, maintained by the workflow"])
found = json.loads(gh_run(["issue", "list", "--label", label, "--state", "all", "--limit", "20",
                           "--json", "number,state,body,author"]) or "[]")
found = sorted((i for i in found if (i.get("author") or {}).get("login") in BOTS), key=lambda i: i["number"])
issue = found[0] if found else None

prev, prev_failure = {}, ""
if issue:
    m = re.search(r"<!-- status: (\{.*?\}) -->", issue.get("body") or "")
    if m:
        try:
            prev = json.loads(m.group(1))
        except ValueError:
            prev = {}
    f = re.search(r"<!-- latest-failure:start -->.*?<!-- latest-failure:end -->", issue.get("body") or "", re.S)
    prev_failure = f.group(0) if f else ""

was_failing = prev.get("state") == "failing"
if outcome == "success":
    st = {"state": "passing", "since": None, "failures": 0,
          "last_success": now, "last_failure": prev.get("last_failure")}
    comment = ("**Recovered** as of %s ([workflow run](%s)), after %d failed run%s."
               % (now, run_url, prev.get("failures", 1), "" if prev.get("failures", 1) == 1 else "s")
               if was_failing else None)
    failure_section = prev_failure
    title = "DNS lists: passing, last success %s" % now
else:
    n = prev.get("failures", 0) + 1 if was_failing else 1
    st = {"state": "failing", "since": prev.get("since") if was_failing else now, "failures": n,
          "last_success": prev.get("last_success"), "last_failure": now}
    block = "```\n%s\n```" % "\n".join(errors)
    comment = (None if was_failing else
               "**Failing** as of %s ([workflow run](%s)): the run %s.\n\n%s"
               % (now, run_url, "was canceled" if outcome == "cancelled" else "did not complete", block))
    failure_section = ("<!-- latest-failure:start -->\n### Latest failure: %s\n\n%s\n<!-- latest-failure:end -->"
                       % (now, block))
    title = "DNS lists: FAILING since %s (%d run%s)" % (st["since"], n, "" if n == 1 else "s")

# Each bootnode's state, kept in the issue so that when one was last missed, and
# when it last answered after the crawl has dropped it, survive from run to run.
prev_boot = prev.get("bootnodes") if isinstance(prev.get("bootnodes"), dict) else {}
prev_boot = {k: v for k, v in prev_boot.items() if isinstance(v, dict) and {"network", "host", "answered"} <= set(v)}
if boot is None:
    bootnodes, checked = prev_boot, prev.get("bootnodes_checked")
else:
    bootnodes, checked = {}, now
    for r in boot:
        p = prev_boot.get(r["id"], {})
        bootnodes[r["id"]] = {"network": r["network"], "host": r["host"], "answered": r["answered"],
                              "last_answered": r["last_answered"] or p.get("last_answered"),
                              "last_missed": p.get("last_missed") if r["answered"] else now}
st["bootnodes"], st["bootnodes_checked"] = bootnodes, checked
down = [b for b in bootnodes.values() if not b["answered"]]
if down:
    title += "; %d bootnode%s unresponsive" % (len(down), "" if len(down) == 1 else "s")

boot_section = ["### Bootnodes", ""]
if not bootnodes:
    boot_section.append("Not checked yet.")
else:
    boot_section += [
        "The bootnodes Core-Geth ships, from `params/bootnodes_classic.go` and",
        "`params/bootnodes_mordor.go` on its `main`, and whether each answered the run's",
        "crawl. A bootnode that does not answer gets one comment on this issue, deleted",
        "on the first run it answers again.",
        "",
    ]
    if boot is None:
        boot_section += ["Not checked this run, so these rows are from %s." % (checked or "an earlier run"), ""]
    boot_section += ["| Network | Bootnode | Status | Last answered | Last missed |", "|---|---|---|---|---|"]
    for b in bootnodes.values():
        boot_section.append("| %s | `%s` | %s | %s | %s |" % (
            b["network"].capitalize(), b["host"], "Responsive" if b["answered"] else "**Unresponsive**",
            b.get("last_answered") or "none recorded", b.get("last_missed") or "none recorded"))

warn_section = ["### Warnings", "", "From the latest run's output:", "",
                "```", *warnings, "```", ""] if warnings else []

def spread_cell(pairs, one, many):
    # As "10 addresses: 3, 2 ×2, 1 ×7".
    total = sum(n for _, n in pairs)
    if not total:
        return "none"
    return "%d %s: %s" % (total, one if total == 1 else many,
                          ", ".join(str(size) if n == 1 else "%d ×%d" % (size, n) for size, n in pairs))

tree_section = ["### Trees", "",
                "The trees the latest run built, one row per network. The last two columns group the nodes",
                "that answered this run on the network's current fork, before the address and subnet limits,",
                "by address and by /24 network (/48 for IPv6): how many of each, then how many nodes each",
                "holds, largest first. `2 ×5` means five of them hold two nodes each.", "",
                "| Network | Nodes | Seats | First answered this run | Over the address or subnet limit "
                "| Nodes per address | Nodes per /24 or /48 |",
                "|---|---|---|---|---|---|---|",
                *("| %s | %d | %d | %d | %d | %s | %s |" % (
                    net.capitalize(), f["nodes"], f["cap"], f["first_answered"], f["held_back"],
                    spread_cell(f["per_address"], "address", "addresses"),
                    spread_cell(f["per_subnet"], "network", "networks"))
                  for net, f in trees.items()),
                ""] if trees else []

body = "\n".join([
    "<!-- status: %s -->" % json.dumps(st),
    "This issue is the status page for the nightly **Update DNS discovery lists** workflow. The",
    "workflow rewrites it on every scheduled run, and comments on it only when something changes:",
    "on the first failure after a success, on the first success after a failure, and when a",
    "bootnode stops answering. **Subscribe to this issue to be notified of exactly those.** Please",
    "do not close it.",
    "",
    "Owners: @ethereumclassic/core-developers",
    "",
    "| | |",
    "|---|---|",
    "| State | **%s** |" % ("passing" if st["state"] == "passing" else "FAILING"),
    "| Last run | %s, [workflow run](%s) |" % (now, run_url),
    "| Last success | %s |" % (st["last_success"] or "none recorded"),
    "| Last failure | %s |" % (st["last_failure"] or "none recorded"),
    "| Consecutive failures | %d |" % st["failures"],
    "",
    *boot_section,
    "",
    *warn_section,
    *tree_section,
    failure_section,
]).rstrip() + "\n"

if issue is None:
    url = gh_run(["issue", "create", "--title", title, "--label", label, "--body-file", "-"], body).strip()
    m = re.search(r"/issues/(\d+)", url)
    if not m:
        sys.exit("report-status: cannot read the new issue's number from %r" % url)
    num = m.group(1)
else:
    num = str(issue["number"])
    if issue.get("state", "").upper() == "CLOSED":
        gh_run(["issue", "reopen", num])
    gh_run(["issue", "edit", num, "--title", title, "--body-file", "-"], body)
    if comment:
        gh_run(["issue", "comment", num, "--body-file", "-"], comment)

posted = deleted = 0
if boot is not None:
    mine = {}
    for c in pages(gh_api(["--paginate", "repos/%s/issues/%s/comments?per_page=100" % (repo, num)])):
        m = re.search(r"<!-- bootnode: ([0-9a-f]{16}) -->", c.get("body") or "")
        if m and (c.get("user") or {}).get("login") in BOTS:
            mine.setdefault(m.group(1), []).append(c["id"])
    for bid, ids in mine.items():
        b = bootnodes.get(bid)
        # One comment while a bootnode does not answer, the earliest; none once it
        # answers, or once Core-Geth no longer ships it.
        for cid in (sorted(ids)[1:] if b and not b["answered"] else ids):
            gh_api(["-X", "DELETE", "repos/%s/issues/comments/%s" % (repo, cid)])
            deleted += 1
    for bid, b in bootnodes.items():
        if b["answered"] or bid in mine:
            continue
        last = ("It last answered %s." % b["last_answered"] if b.get("last_answered")
                else "The crawl has no record of it answering.")
        gh_run(["issue", "comment", num, "--body-file", "-"], "\n".join([
            "**Bootnode unresponsive:** the %s bootnode `%s` did not answer the crawl of %s "
            "([workflow run](%s)). %s" % (b["network"].capitalize(), b["host"], now[:10], run_url, last),
            "",
            "It may be down, or out of this runner's reach. This comment is deleted on the first run",
            "it answers again.",
            "",
            "<!-- bootnode: %s -->" % bid,
        ]) + "\n")
        posted += 1

print("status issue #%s: %s%s; bootnodes %s" % (
    num, st["state"], ", commented" if comment and issue is not None else "",
    "not checked" if boot is None else "%d unresponsive, %d comment%s posted, %d deleted"
    % (len(down), posted, "" if posted == 1 else "s", deleted)))
PYEOF
