#!/usr/bin/env bash
#
# Crawl the Ethereum Classic DHT, filter the result per network, sign each DNS
# discovery tree and publish it to that domain's provider.
#
# Run from the repository root. Requires devp2p built from ethereumclassic/core-geth:
# upstream go-ethereum's devp2p has no "classic" or "mordor" value for -eth-network,
# and rejects them outright -- see the note on the filter step below.
#
#   DEVP2P=/path/to/devp2p \
#   DNS_SIGNING_KEY_FILE=/path/to/keystore.json \
#   DNS_SIGNING_KEY_PASSWORD_FILE=/path/to/password.txt \
#   CLOUDFLARE_API_TOKEN=... \
#   ./scripts/update-lists.sh [--dry-run]
#
# Exit 0 published (or dry run clean), 1 refused or failed, 2 did-not-run.

set -uo pipefail

DEVP2P="${DEVP2P:-devp2p}"
CRAWL_TIMEOUT="${CRAWL_TIMEOUT:-30m}"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

# When this run began, in the crawler's own timestamp format (UTC, whole
# seconds), so a node's lastResponse says whether it answered this run.
RUN_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# A crawl that returns almost nothing is a broken crawl, not a small network.
# Publishing its result would replace a working tree with a dead one, and the
# clients that read it have no way to tell the difference. Refuse instead.
#
# These are floors against a broken run, NOT targets. A run that lost only its
# seed trees can still clear them; the shrink check in publish_tree is what
# catches that.
#
# MIN_NODES_MORDOR sits well below a normal night's Mordor count deliberately --
# Mordor's ceiling is the network, not the crawl, and a floor scaled from
# classic's numbers would refuse every legitimate Mordor publish.
MIN_NODES_CLASSIC="${MIN_NODES_CLASSIC:-40}"
MIN_NODES_MORDOR="${MIN_NODES_MORDOR:-5}"

# Refuse a published tree that shrinks below this fraction of the last one.
SHRINK_TOLERANCE_PCT="${SHRINK_TOLERANCE_PCT:-50}"

# Refuse the whole run when the crawl reached under this share of the nodes that
# answered an earlier run. When this runner cannot reach the network -- its
# connection, its resolver, the host -- every node fails its check at once, and
# this catches it before any tree is built and names the cause, where the floor
# and the shrink check would only see a small tree. The crawl set holds nodes of
# every network the DHT carries, so its answer rate reflects this runner's reach
# rather than any one network's health.
REACH_MIN_PCT="${REACH_MIN_PCT:-50}"

# Warn, without refusing, when fewer than this share of the endpoints -- IP
# address and UDP port -- a tree published last time answered this run. Most of
# a tree can stop answering at once when operators rotate their node keys
# together, as the move to the v1.13 line asks. Refusing then would keep the old
# tree in DNS, and every later run, comparing against that same committed tree,
# would refuse again until someone intervened. Counted by endpoint, so a node
# that answered at the same endpoint under a new key still counts.
RETENTION_MIN_PCT="${RETENTION_MIN_PCT:-50}"

# Per-network published-node cap, derived from the DNS zone budget rather than
# from crawl yield.
#
# A tree of N nodes costs N records, plus one root, plus about one branch per
# 11 nodes: 11 nodes -> 14 records, 120 -> 132.
#
# The budget is 200 records for a whole Cloudflare free-plan zone, and BOTH
# trees live in the same zone -- they are not budgeted separately. Discovery
# also shares that zone with the domain's other services: mail, the apex site,
# subdomains for explorers and dashboards, and whatever it already carries.
#
#   classic 120 -> ~132 records
#   mordor   15 ->  ~18 records  (a ceiling; each run's count is in its commit)
#   both              ~150 of 200, leaving the rest for the domain's services
#
# A tree's job is to reach the first few peers, after which the discv4 DHT does
# the work. Against three hardcoded bootnodes, 120 nodes is already a large
# improvement and the marginal value of node 300 is close to zero. Mordor's cap
# is headroom for a small network: its tree carries every current node the crawl
# finds, up to the cap.
CAP_CLASSIC="${CAP_CLASSIC:-120}"
CAP_MORDOR="${CAP_MORDOR:-15}"
cap_for() { case "$1" in classic) echo "$CAP_CLASSIC";; mordor) echo "$CAP_MORDOR";; *) echo 100;; esac; }

# At most this many nodes per address in a published tree -- see rank_and_cap.
MAX_PER_ADDRESS="${MAX_PER_ADDRESS:-2}"

# And at most this many per /24 (IPv4) or /48 (IPv6) -- see rank_and_cap. The
# per-address cap holds one machine to MAX_PER_ADDRESS; this spreads a tree
# across networks as well as machines. It is a ceiling, not a target. A /24 is
# far narrower than a hosting provider, which is why the limit is per /24 and
# never per ASN, a span that would fall on operators who only share a provider.
# Loosen it if independent operators turn out to share one /24.
MAX_PER_SUBNET="${MAX_PER_SUBNET:-2}"

# The fork hash (EIP-2124 FORK_HASH) a synced node on each network advertises
# today. A published tree keeps only nodes whose record carries it.
#
# `nodeset filter -eth-network` does not do this. It is core-geth's
# forkid.NewStaticFilter, which judges compatibility from block zero, so every
# stage of the network's fork schedule passes -- the genesis stage included. A
# node that starts from an empty chain advertises the genesis stage until it
# imports its first block: its record is refreshed only on a new chain head, and
# a snap sync sets none until it finishes. Such a node answers every discovery
# ping and serves no blocks. The genesis stage is also the one Ethereum mainnet
# shares, so such a record cannot even say which chain the node is on.
#
# Pinned, and deliberately not read from core-geth automatically. Nothing the
# pipeline runs can report a network's current fork ID -- devp2p has no command
# for it, and the crawl never sees a chain head -- and more to the point, the
# current fork must NOT follow core-geth's main. A fork is scheduled in main's
# chain config before its release is cut and before it activates on chain, while
# the nodes serving today's syncing peers are still on the current fork. So the
# filter stays on the current hash, keeping those responsive nodes in the tree,
# until a human bumps the pin when the release is cut. keep_current_fork keeps
# only nodes on the pinned hash and leaves out a node past it. check_fork_schedule
# reads core-geth's own config nightly and only WARNS when the schedule has moved
# beyond the pin.
# Take the value from core-geth's core/forkid/forkid_test.go at release time.
FORK_HASH_CLASSIC="${FORK_HASH_CLASSIC:-be46d57c}"   # since block 19,250,000 (Spiral)
FORK_HASH_MORDOR="${FORK_HASH_MORDOR:-3a6b00d7}"     # since block 9,957,000
fork_hash_for() { case "$1" in classic) echo "$FORK_HASH_CLASSIC";; mordor) echo "$FORK_HASH_MORDOR";; *) return 1;; esac; }

# The fork-activation blocks ethereumclassic/core-geth's params/config_<net>.go
# carried when each pin above was last set -- the trusted basis check_fork_schedule
# compares against. core-geth is the reference client, so its chain config is the
# source of truth for the schedule; the crawl's node advertisements are not.
# Bump these together with the pin above, at release, from the same config files.
# Read by check_fork_schedule as a set; order and spacing do not matter.
FORK_SCHEDULE_CLASSIC="${FORK_SCHEDULE_CLASSIC:-1150000 2500000 3000000 5000000 5900000 8772000 9573000 10500839 11380000 11700000 13189133 14525000 19250000}"
FORK_SCHEDULE_MORDOR="${FORK_SCHEDULE_MORDOR:-0 301243 999983 2380000 2520000 3985893 5520000 9957000 10400000}"
fork_schedule_for() { case "$1" in classic) echo "$FORK_SCHEDULE_CLASSIC";; mordor) echo "$FORK_SCHEDULE_MORDOR";; *) return 1;; esac; }

# domain:publisher pairs.
#
# All three domains are served from one Cloudflare account. This is not provider
# diversity: a problem with that account takes all six trees offline at once. It
# does not reach the bootnodes, which clients contact by IP address, and it
# cannot alter a tree, which is signed with a key held apart from the account.
#
# Moving a domain to another provider needs no devp2p change: render with
# `to-txt` and hand the result to an external publisher. Such a publisher must
# be incremental -- see publish_desec.
DOMAINS="${DOMAINS:-ethereumclassic.net:cloudflare ethclassic.net:cloudflare ethereumclassic.network:cloudflare}"

# Cloudflare zone IDs, as space-separated domain=zoneid pairs.
#
# devp2p cannot derive the zone. With --zoneid unset it looks up a zone named
# after the tree -- "all.classic.ethereumclassic.net" -- which matches no zone,
# and the publish fails with "zone could not be found".
#
# A zone ID is not a credential: it is visible in the provider dashboard and
# grants nothing on its own.
CLOUDFLARE_ZONE_IDS="${CLOUDFLARE_ZONE_IDS:-}"

zone_id_for() {
  local want="$1" pair
  for pair in $CLOUDFLARE_ZONE_IDS; do
    if [ "${pair%%=*}" = "$want" ]; then printf '%s\n' "${pair#*=}"; return 0; fi
  done
  return 1
}

log()  { printf '  %s\n' "$*"; }
fail() { printf '  ERROR: %s\n' "$*" >&2; exit 1; }

# Preflight every external command this script depends on. python3 is as load
# bearing as jq here -- it merges the seed set, counts nodes, and reads the
# shrink-check baseline -- and its absence would otherwise make the seed merge a
# silent no-op rather than a failure.
for tool in "$DEVP2P" jq python3; do
  command -v "$tool" >/dev/null 2>&1 || [ -x "$tool" ] || { echo "DID-NOT-RUN: $tool not found" >&2; exit 2; }
done

# Bootstrap set, read from the client rather than copied here. A second copy of
# a bootnode list is a second thing to go stale, and this one would go stale
# silently -- a dead entry just makes the crawl start slower, never louder.
#
# CORE_GETH_SRC must point at a core-geth checkout; the workflow uses the same
# one it builds devp2p from, so the crawl is always seeded by the list the
# client itself ships.
extract_bootnodes() {
  local file="$1"
  [ -f "$file" ] || fail "no bootnode source at $file"
  grep -oE '"enode://[^"]+"' "$file" | tr -d '"' | paste -sd,
}

CORE_GETH_SRC="${CORE_GETH_SRC:-}"
if [ -n "$CORE_GETH_SRC" ]; then
  BOOT_CLASSIC=$(extract_bootnodes "$CORE_GETH_SRC/params/bootnodes_classic.go")
  BOOT_MORDOR=$(extract_bootnodes "$CORE_GETH_SRC/params/bootnodes_mordor.go")
else
  BOOT_CLASSIC=""
  BOOT_MORDOR=""
fi

# An explicit override wins, for a one-off crawl from a known-good seed.
[ -n "${CLASSIC_BOOTNODES:-}" ] && BOOT_CLASSIC="$CLASSIC_BOOTNODES"
[ -n "${MORDOR_BOOTNODES:-}" ]  && BOOT_MORDOR="$MORDOR_BOOTNODES"

[ -n "$BOOT_CLASSIC" ] || fail "no classic bootnodes: set CORE_GETH_SRC or CLASSIC_BOOTNODES"
[ -n "$BOOT_MORDOR" ]  || fail "no mordor bootnodes: set CORE_GETH_SRC or MORDOR_BOOTNODES"
log "seeded from $(tr ',' '\n' <<<"$BOOT_CLASSIC" | wc -l) classic and $(tr ',' '\n' <<<"$BOOT_MORDOR" | wc -l) mordor bootnodes"

# Where this run records whether each of those bootnodes answered its crawl, for
# the status issue -- see bootnode_status. Unset, the result is only logged.
BOOTNODE_STATUS="${BOOTNODE_STATUS:-}"

# Seed the node set from published DNS trees, then let the crawl revalidate
# every one of them. A seed adds reach, not trust: the crawl re-pings its input
# set, and only a node that answered this run is published -- see rank_and_cap.
# Nor does an entry stay: a node that stops answering loses half its score per
# missed check and is dropped at zero, and a seeded node that has never answered
# is pruned in seed_from_trees once no seed tree carries it.
#
# It matters most on Mordor, a network small enough that a crawl from the
# bootnodes alone finds only part of it in one run. Seeded, the crawl starts from
# everything those trees carry and keeps what still answers.
#
# This project's own trees are seeded first, so a run can rebuild from what it
# last published if the others stop resolving. Two domains rather than one,
# because a seed sync that fails is skipped silently and one zone should not be
# able to take the whole seed with it.
#
# The predecessor trees stay as a further source of reach. They were once the
# only thing replenishing Mordor; since this project's own bootnodes shipped in
# the client, the crawl finds Mordor nodes by itself as well. A tree that stops
# resolving is skipped.
SEED_KEY_OURS="enrtree://APDLRZ2T7ERXPWXX4D5USB32NIFYHXMFVZQ3DZALK6JJJ5L4VSYIQ@"
SEED_KEY_PRIOR="enrtree://AJE62Q4DUX4QMMXEHCSSCSC65TDHZYSMONSD64P3WULVLSF6MRQ3K@"

SEED_TREES="${SEED_TREES:-\
${SEED_KEY_OURS}all.classic.ethereumclassic.net,\
${SEED_KEY_OURS}all.mordor.ethereumclassic.net,\
${SEED_KEY_OURS}all.classic.ethclassic.net,\
${SEED_KEY_OURS}all.mordor.ethclassic.net,\
${SEED_KEY_PRIOR}all.classic.blockd.info,\
${SEED_KEY_PRIOR}all.classic.etcdisco.net,\
${SEED_KEY_PRIOR}all.mordor.blockd.info,\
${SEED_KEY_PRIOR}all.mordor.etcdisco.net}"

count() { python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$1" 2>/dev/null || echo 0; }

seed_from_trees() {
  local out="$1" tmp merged=0 failed=0
  [ -n "$SEED_TREES" ] || { log "no seed trees configured"; return 0; }
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' RETURN
  local url
  for url in ${SEED_TREES//,/ }; do
    local dir
    dir="$tmp/$(echo "$url" | tr -c 'a-zA-Z0-9' '_')"
    # A tree that will not sync is skipped, never fatal: these are other
    # people's infrastructure and the crawl proceeds without them.
    if "$DEVP2P" dns sync "$url" "$dir" >/dev/null 2>&1; then
      local n; n=$(count "$(find "$dir" -name nodes.json | head -1)")
      log "seed tree ${url##*@}: $n nodes"
      merged=$((merged + n))
    else
      log "seed tree ${url##*@}: unreachable, skipping"
      failed=$((failed + 1))
    fi
  done
  [ "$merged" -eq 0 ] && { log "no seed nodes obtained"; return 0; }
  python3 - "$out" "$tmp" "$failed" <<'PYEOF'
import json, os, sys
out, tmp, failed = sys.argv[1], sys.argv[2], int(sys.argv[3])
merged = json.load(open(out)) if os.path.exists(out) else {}
added, seeded = 0, set()
for root, _, files in os.walk(tmp):
    for f in files:
        if f != "nodes.json":
            continue
        for k, v in json.load(open(os.path.join(root, f))).items():
            seeded.add(k)
            if k not in merged:
                merged[k] = v
                added += 1

# The crawl never removes a node that has never answered it: devp2p halves a
# failing node's score and drops it at zero, but a node already at zero is
# skipped rather than dropped, so a seed record that never answers would stay
# forever. Prune it once no seed tree carries it -- but only on a run where
# every seed tree synced. A tree that failed may still carry it, and a run where
# the syncs fail is more likely a resolver or network fault here than a verdict
# on the records.
def never_answered(v):
    return not v.get("score") and str(v.get("lastResponse") or "0001").startswith("0001")

pruned = 0
if failed:
    print("  %d seed tree(s) unreachable: not pruning records that never answered" % failed)
else:
    for k in [k for k, v in merged.items() if k not in seeded and never_answered(v)]:
        del merged[k]
        pruned += 1
json.dump(merged, open(out, "w"), indent=2)
print("  merged %d new nodes from seed trees, pruned %d that never answered (set now %d)"
      % (added, pruned, len(merged)))
PYEOF
}

crawl() {
  local net="$1" boot="$2" out="$3"
  log "crawling $net (timeout $CRAWL_TIMEOUT)"
  # crawl appends to an existing node set, so a prior run's nodes survive a
  # single bad crawl rather than being replaced by it.
  "$DEVP2P" discv4 crawl -bootnodes "$boot" -timeout "$CRAWL_TIMEOUT" "$out" \
    || fail "crawl failed for $net"
}

# Publish a signed tree directory to Cloudflare. The API token is read from the
# CLOUDFLARE_API_TOKEN environment variable, which devp2p's --token flag already
# declares as its EnvVar -- passing it on the command line as well would put the
# token into /proc/<pid>/cmdline for no gain.
publish_cloudflare() {
  local dir="$1" zone="$2"
  [ -n "${CLOUDFLARE_API_TOKEN:-}" ] || fail "CLOUDFLARE_API_TOKEN is unset"
  [ -n "$zone" ] || fail "no Cloudflare zone ID for $dir"
  # --zoneid must precede the directory: urfave/cli stops parsing flags at the
  # first positional argument, so a flag placed after it is silently ignored.
  "$DEVP2P" dns to-cloudflare --zoneid "$zone" "$dir" \
    || fail "cloudflare publish failed for $dir"
}

# Publish to deSEC via to-txt plus an external publisher.
#
# No domain selects this publisher today. It is the shape a second provider
# takes, and it fails rather than publishing if selected without
# DESEC_PUBLISHER set.
#
# deSEC allows 300 RRset changes per domain per day. A ~180-record tree
# republished by delete-and-recreate is ~360 operations, so it would fail on the
# first night and every night after. EIP-1459 records are content-addressed, so
# an unchanged node keeps its record name and value -- the publisher MUST be
# diff-based and write only genuine churn. DNSControl and octoDNS both are, and
# DNSControl ships a deSEC provider documenting this exact limit.
publish_desec() {
  local dir="$1" txt
  txt="$dir/records.txt.json"
  "$DEVP2P" dns to-txt "$dir" "$txt" || fail "to-txt failed for $dir"
  log "$dir: rendered $(jq 'length' "$txt" 2>/dev/null || echo '?') TXT records"
  [ -n "${DESEC_PUBLISHER:-}" ] \
    || fail "DESEC_PUBLISHER is unset: no diff-based publisher configured for $dir"
  [ -x "$DESEC_PUBLISHER" ] || fail "DESEC_PUBLISHER is not executable: $DESEC_PUBLISHER"
  "$DESEC_PUBLISHER" "$dir" "$txt" || fail "desec publish failed for $dir"
}

# Reduce a filtered node set, in place, to the nodes on the network's current
# fork hash -- see FORK_HASH_CLASSIC. The crawl's `-eth-network` filter admits
# every stage of the schedule, the genesis stage included; this narrows it to
# the one hash a synced current node advertises.
#
# It refuses only when NO node carries the pinned hash -- the pin is wrong or the
# crawl is broken. A node on a later hash is simply left out, never a refusal:
# whether the network has moved past the pin is core-geth's config to state (read
# by check_fork_schedule), not a crawled record's. The nodes still on the current
# fork are the ones serving syncing peers, so they stay published until a human
# bumps the pin when core-geth cuts the release.
keep_current_fork() {
  local file="$1" net="$2" fork="$3" label="$4"
  python3 - "$file" "$net" "$fork" "$label" <<'PYEOF'
import base64, collections, json, sys
path, net, want, label = sys.argv[1:5]
want = want.lower()
var = "FORK_HASH_" + net.upper()
if len(want) != 8 or any(c not in "0123456789abcdef" for c in want):
    sys.exit("  ERROR: %s: %s=%s is not a fork hash -- expected 8 hex digits" % (label, var, want))

def item(b, i):
    # One RLP item at b[i]: (payload start, payload end).
    p = b[i]
    if p < 0x80: return i, i + 1
    if p < 0xb8: return i + 1, i + 1 + p - 0x80
    if p < 0xc0:
        s = i + 1 + p - 0xb7
        return s, s + int.from_bytes(b[i + 1:s], "big")
    if p < 0xf8: return i + 1, i + 1 + p - 0xc0
    s = i + 1 + p - 0xf7
    return s, s + int.from_bytes(b[i + 1:s], "big")

def items(b, start, end):
    out = []
    while start < end:
        s, e = item(b, start)
        out.append((s, e))
        start = e
    if start != end:
        raise ValueError("RLP list overruns its length")
    return out

def fork_id(nid, record):
    # The ENR is [signature, seq, key, value, ...]; the `eth` value is
    # [[fork hash, fork next], ...]. devp2p's own filter has already decoded
    # every record here, so a failure is this decoder's fault and must stop the
    # run rather than quietly drop the node.
    try:
        s = record[4:]
        raw = base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))
        top = items(raw, *item(raw, 0))
        for k, v in zip(top[2::2], top[3::2]):
            if raw[k[0]:k[1]] == b"eth":
                fid = items(raw, *items(raw, *v)[0])
                return raw[fid[0][0]:fid[0][1]].hex(), int.from_bytes(raw[fid[1][0]:fid[1][1]], "big")
    except Exception as e:
        sys.exit("  ERROR: %s: cannot decode the eth entry of node %s: %s" % (label, nid, e))
    sys.exit("  ERROR: %s: node %s has no eth entry, which -eth-network requires" % (label, nid))

nodes = json.load(open(path))
ids = {nid: fork_id(nid, v["record"]) for nid, v in nodes.items()}

kept = {nid: v for nid, v in nodes.items() if ids[nid][0] == want}
left = collections.Counter(ids[nid] for nid in nodes if nid not in kept)
print("  %s: %d of %d nodes on %s=%s; left out: %s" % (label, len(kept), len(nodes), var, want,
      ", ".join("%s next %d x%d" % (h, nx, c) for (h, nx), c in left.most_common()) or "none"))
if not kept:
    sys.exit("  ERROR: %s: no node carries %s=%s -- check it against core-geth's fork ID tests"
             % (label, var, want))
json.dump(kept, open(path, "w"), indent=2)
PYEOF
}

# Warn if ethereumclassic/core-geth's own fork schedule has moved beyond the pin
# -- see FORK_SCHEDULE_CLASSIC. core-geth is the reference client, so its chain
# config is the trusted source for the schedule; this reads it from the same
# .core-geth checkout the build uses (CORE_GETH_SRC), never from a crawled node.
#
# It never refuses and never switches the filter. A fork lands in core-geth's
# main config before its release is cut and before it activates on chain, and the
# current-fork nodes keep serving syncing peers until then, so this only raises a
# WARNING for a human to adopt into FORK_HASH_<NET> and FORK_SCHEDULE_<NET> at
# release. Skipped, not failed, when CORE_GETH_SRC is unset (a local dry run).
check_fork_schedule() {
  local net="$1"
  local cfg="${CORE_GETH_SRC:-}/params/config_${net}.go" basis
  basis=$(fork_schedule_for "$net") || { log "WARNING: $net: no recorded fork schedule basis"; return 0; }
  if [ -z "${CORE_GETH_SRC:-}" ] || [ ! -f "$cfg" ]; then
    log "  $net: core-geth config not available (set CORE_GETH_SRC); fork schedule not checked"
    return 0
  fi
  python3 - "$cfg" "$net" "$basis" <<'PYEOF'
import re, sys
cfg, net, basis = sys.argv[1:4]
var = {"classic": "ClassicChainConfig", "mordor": "MordorChainConfig"}[net]
opener = re.compile(r"\b%s\s*=\s*&coregeth\.CoreGethChainConfig\{" % re.escape(var))
blk = re.compile(r"\b\w*Block:\s*big\.NewInt\(([0-9_]+)\)")
inside, found = False, set()
for ln in open(cfg):
    if not inside:
        if opener.search(ln):
            inside = True
        continue
    if ln.rstrip("\n") == "\t}":        # the struct's own closing brace
        break
    if re.match(r"\s*//", ln):           # a commented-out field (e.g. the declined DAO fork)
        continue
    m = blk.search(ln)
    if m:
        found.add(int(m.group(1).replace("_", "")))
if not found:
    print("  WARNING: %s: no fork blocks found in core-geth's %s -- schedule not checked" % (net, var))
    sys.exit(0)
have = {int(x) for x in basis.split()}
added = sorted(found - have)
removed = sorted(have - found)
if not added and not removed:
    print("  %s: core-geth fork schedule matches the pin's basis (%d blocks)" % (net, len(found)))
    sys.exit(0)
msg = []
if added:
    msg.append("adds block(s) %s" % ", ".join(str(x) for x in added))
if removed:
    msg.append("drops block(s) %s" % ", ".join(str(x) for x in removed))
print("  WARNING: %s: core-geth's fork schedule %s vs the pinned basis. A fork may be scheduled; "
      "the trees stay on the current pin. Update FORK_HASH_%s and FORK_SCHEDULE_%s from core-geth "
      "when the release is cut." % (net, " and ".join(msg), net.upper(), net.upper()))
PYEOF
}

# Rank a node set and cap it, writing the result to $2 -- see CAP_CLASSIC,
# MAX_PER_ADDRESS and MAX_PER_SUBNET.
#
# Only a node that answered this run is published, whatever seats are left. A
# record that did not answer, whether it answered an earlier run or never has,
# stays in the crawl set and out of the tree. Among the nodes that answered, the
# higher score ranks first -- the crawler adds a point each time a node answers
# and halves it each time one does not -- then the later lastResponse. Ties go to
# the endpoint, not the node key, so a node's place depends on where it answers
# and for how long, never on which key it answers under.
#
# No address publishes more than MAX_PER_ADDRESS nodes and no /24 (or /48) more
# than MAX_PER_SUBNET: one machine is one point of failure however many node keys
# it runs, and the subnet limit spreads a tree across networks as well as
# machines. Both are ceilings on the ranking above, not a ranking of their own,
# by design: the nodes an address or subnet keeps are its best-ranked ones, and
# nothing else orders the tree. Seats only an address or subnet already at its
# limit could fill stay empty, since the zone budget sets the cap as a ceiling,
# not a count to reach.
#
# The address is the record's own `ip` entry, else `ip6`. The crawl sent its
# request there, so a node that answered receives packets at it.
#
# Score ranks before lastResponse because lastResponse is recorded to the second:
# ranked by it first, a run's nodes fall in the order the crawl happened to reach
# them -- see docs/node-selection.md.
rank_and_cap() {
  local src="$1" out="$2" cap="$3" label="$4"
  python3 - "$src" "$out" "$cap" "$MAX_PER_ADDRESS" "$RUN_START" "$label" "$MAX_PER_SUBNET" <<'PYEOF'
import base64, collections, ipaddress, json, sys
src, out, cap, per, start, label, per_net = sys.argv[1:8]
for name, val in (("MAX_PER_ADDRESS", per), ("MAX_PER_SUBNET", per_net)):
    if not val.isdigit() or int(val) < 1:
        sys.exit("  ERROR: %s: %s=%s is not a whole number of at least 1" % (label, name, val))
cap, per, per_net = int(cap), int(per), int(per_net)

def item(b, i):
    # One RLP item at b[i]: (payload start, payload end).
    p = b[i]
    if p < 0x80: return i, i + 1
    if p < 0xb8: return i + 1, i + 1 + p - 0x80
    if p < 0xc0:
        s = i + 1 + p - 0xb7
        return s, s + int.from_bytes(b[i + 1:s], "big")
    if p < 0xf8: return i + 1, i + 1 + p - 0xc0
    s = i + 1 + p - 0xf7
    return s, s + int.from_bytes(b[i + 1:s], "big")

def items(b, start, end):
    out = []
    while start < end:
        s, e = item(b, start)
        out.append((s, e))
        start = e
    if start != end:
        raise ValueError("RLP list overruns its length")
    return out

def address(nid, record):
    # The ENR is [signature, seq, key, value, ...]. keep_current_fork has already
    # decoded every record here, so a failure is this decoder's fault and must
    # stop the run rather than quietly drop the node.
    try:
        s = record[4:]
        raw = base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))
        top = items(raw, *item(raw, 0))
        kv = {raw[k[0]:k[1]]: raw[v[0]:v[1]] for k, v in zip(top[2::2], top[3::2])}
    except Exception as e:
        sys.exit("  ERROR: %s: cannot decode the record of node %s: %s" % (label, nid, e))
    udp = int.from_bytes(kv.get(b"udp", b""), "big")
    if len(kv.get(b"ip", b"")) == 4:
        ip = ipaddress.IPv4Address(kv[b"ip"])
        return str(ip), udp, str(ipaddress.IPv4Network((ip, 24), strict=False))
    if len(kv.get(b"ip6", b"")) == 16:
        ip = ipaddress.IPv6Address(kv[b"ip6"])
        return str(ip), udp, str(ipaddress.IPv6Network((ip, 48), strict=False))
    return "id:" + nid, udp, "id:" + nid      # no address in the record: it shares none

nodes = json.load(open(src))
rows = []    # (score, lastResponse, address, udp port, id, subnet): best sorts last
silent = 0
for nid, v in nodes.items():
    last = str(v.get("lastResponse") or "")
    if last < start:
        silent += 1
        continue
    ip, udp, net = address(nid, v["record"])
    rows.append((int(v.get("score") or 0), last, ip, udp, nid, net))

def places(col):
    # Each node's place among the nodes sharing its address (col 2) or its subnet
    # (col 5), best first, so a ceiling keeps the best `per` of each group.
    groups = collections.defaultdict(list)
    for r in rows:
        groups[r[col]].append(r)
    return {r[4]: k for g in groups.values() for k, r in enumerate(sorted(g, reverse=True))}

by_address = places(2)
by_subnet = places(5)
eligible = [r for r in rows if by_address[r[4]] < per and by_subnet[r[4]] < per_net]
eligible.sort(reverse=True)
kept = eligible[:cap]
past_addr = sum(1 for r in rows if by_address[r[4]] >= per)
past_net = sum(1 for r in rows if by_address[r[4]] < per and by_subnet[r[4]] >= per_net)
with open(out, "w") as f:
    json.dump({r[4]: nodes[r[4]] for r in kept}, f, indent=2)
    f.write("\n")
print("  %s: %d of %d nodes answered this run, on %d addresses in %d networks; %d past %d per address "
      "and %d further past %d per subnet left out; %d kept, cap %d"
      % (label, len(rows), len(rows) + silent, len({r[2] for r in rows}), len({r[5] for r in rows}),
         past_addr, per, past_net, per_net, len(kept), cap))
# The tree's summary for the status issue -- see scripts/report-status.sh: the
# seats it filled, how many of its nodes first answered this run, and how many
# nodes the per-address and per-subnet limits held back, in aggregate.
busiest_addr = max(collections.Counter(r[2] for r in rows).values(), default=0)
busiest_net = max(collections.Counter(r[5] for r in rows).values(), default=0)
print("TREE: " + json.dumps({
    "tree": label, "nodes": len(kept), "cap": cap,
    "first_answered": sum(1 for r in kept if str(nodes[r[4]].get("firstResponse") or "") >= start),
    "held_back": len(rows) - len(eligible), "busiest_address": busiest_addr, "busiest_subnet": busiest_net}))
PYEOF
}

# Refuse if the crawl reached under REACH_MIN_PCT of the nodes that answered an
# earlier run -- see REACH_MIN_PCT. A node first heard from this run, and a seed
# record that has never answered, are in neither count.
check_reach() {
  python3 - "$RUN_START" "$REACH_MIN_PCT" all.json <<'PYEOF'
import json, sys
start, pct, current = sys.argv[1:4]
known = back = 0
for v in json.load(open(current)).values():
    first = str(v.get("firstResponse") or "")
    if first and not first.startswith("0001") and first < start:
        known += 1
        back += str(v.get("lastResponse") or "") >= start
if not known:
    print("  crawl reach: no node answered an earlier run, nothing to compare against")
    sys.exit(0)
print("  crawl reach: %d of the %d nodes that answered an earlier run answered this one (%.1f%%)"
      % (back, known, 100.0 * back / known))
if back * 100 < known * int(pct):
    sys.exit("  ERROR: the crawl reached under %s%% of the nodes that answered an earlier run. The\n"
             "  network does not go quiet overnight; this runner's connection can." % pct)
PYEOF
}

# Report how many of the endpoints in the last committed tree answered this run,
# and warn under RETENTION_MIN_PCT -- see RETENTION_MIN_PCT. Never refuses:
# whether the runner reached the network is check_reach's call. An endpoint
# counts once any node answered there this run, under its old key or a new one.
# The first publish has no committed tree and is not checked.
check_retention() {
  local dir="$1"
  python3 - "$dir" "$RUN_START" "$RETENTION_MIN_PCT" all.json <(git show "HEAD:$dir/nodes.json" 2>/dev/null) <<'PYEOF'
import base64, json, sys
label, start, pct, current, committed = sys.argv[1:6]

def item(b, i):
    # One RLP item at b[i]: (payload start, payload end).
    p = b[i]
    if p < 0x80: return i, i + 1
    if p < 0xb8: return i + 1, i + 1 + p - 0x80
    if p < 0xc0:
        s = i + 1 + p - 0xb7
        return s, s + int.from_bytes(b[i + 1:s], "big")
    if p < 0xf8: return i + 1, i + 1 + p - 0xc0
    s = i + 1 + p - 0xf7
    return s, s + int.from_bytes(b[i + 1:s], "big")

def items(b, start, end):
    out = []
    while start < end:
        s, e = item(b, start)
        out.append((s, e))
        start = e
    return out

def endpoint(record):
    # The ENR is [signature, seq, key, value, ...]: its `ip` (else `ip6`) and `udp` entries.
    s = record[4:]
    raw = base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))
    top = items(raw, *item(raw, 0))
    kv = {raw[k[0]:k[1]]: raw[v[0]:v[1]] for k, v in zip(top[2::2], top[3::2])}
    return (kv.get(b"ip") or kv.get(b"ip6") or b"").hex(), int.from_bytes(kv.get(b"udp", b""), "big")

try:
    prev = json.load(open(committed))
except ValueError:
    print("  %s: no committed tree, nothing to compare against" % label)
    sys.exit(0)
published = {}
for nid, v in prev.items():
    try:
        published.setdefault(endpoint(v["record"]), set()).add(nid)
    except Exception as e:
        print("  WARNING: %s: cannot read the endpoint of committed node %s (%s); retention not reported"
              % (label, nid, e))
        sys.exit(0)

answered, unreadable = {}, 0
for nid, v in json.load(open(current)).items():
    if str(v.get("lastResponse") or "") >= start:
        try:
            answered.setdefault(endpoint(v["record"]), set()).add(nid)
        except Exception:
            unreadable += 1

back = [e for e in published if e in answered]
rekeyed = sum(1 for e in back if not answered[e] & published[e])
print("  %s: %d of the %d endpoints published last time answered this run%s%s"
      % (label, len(back), len(published), ", %d under a new key" % rekeyed if rekeyed else "",
         "; %d answering records could not be read" % unreadable if unreadable else ""))
if published and len(back) * 100 < len(published) * int(pct):
    print("  WARNING: %s: %d of the %d endpoints published last time answered, though the crawl reached "
          "the rest of the network; publishing what answered" % (label, len(back), len(published)))
PYEOF
}

# Carry a node's score across a rotation of its node key, in place in $1.
#
# The crawler keys a node by its public key, so a node whose operator rotates
# its key, as the move to the v1.13 line asks, comes back as a new node with no
# score, while a node left running on its old key keeps climbing. Wherever more
# addresses answer than a tree has seats, ranking by score would then put every
# node whose operator rotated behind every node whose operator did not.
#
# So a node that answers this run at the endpoint, IP address and UDP port, of a
# key that did not, and that first answered after that key last did, takes over
# that key's score as the last committed crawl recorded it, and the silent key's
# record is dropped. Both records must carry the current fork hash of a network
# this repository publishes, the same one: the crawl set holds every network the
# DHT carries, and the rest are left as the crawl wrote them. A key silent long
# enough for the crawler to drop it leaves nothing to carry. Running this twice
# in one run carries nothing more, since the first pass drops the records the
# second would carry from.
carry_over() {
  local file="$1"
  python3 - "$file" "$RUN_START" <(git show "HEAD:$file" 2>/dev/null) \
    "classic=$FORK_HASH_CLASSIC" "mordor=$FORK_HASH_MORDOR" <<'PYEOF'
import base64, json, sys
path, start, committed = sys.argv[1:4]
pins = {}    # fork hash -> the network it is the current fork of
for arg in sys.argv[4:]:
    net, _, fork = arg.partition("=")
    pins[fork.lower()] = net

def item(b, i):
    # One RLP item at b[i]: (payload start, payload end).
    p = b[i]
    if p < 0x80: return i, i + 1
    if p < 0xb8: return i + 1, i + 1 + p - 0x80
    if p < 0xc0:
        s = i + 1 + p - 0xb7
        return s, s + int.from_bytes(b[i + 1:s], "big")
    if p < 0xf8: return i + 1, i + 1 + p - 0xc0
    s = i + 1 + p - 0xf7
    return s, s + int.from_bytes(b[i + 1:s], "big")

def items(b, start, end):
    out = []
    while start < end:
        s, e = item(b, start)
        out.append((s, e))
        start = e
    return out

def endpoint(record):
    # The ENR is [signature, seq, key, value, ...]: its `ip` (else `ip6`) and `udp` entries, and the fork
    # hash its `eth` entry carries, or None for a record without a readable one.
    s = record[4:]
    raw = base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))
    top = items(raw, *item(raw, 0))
    kv = {raw[k[0]:k[1]]: raw[v[0]:v[1]] for k, v in zip(top[2::2], top[3::2])}
    return ((kv.get(b"ip") or kv.get(b"ip6") or b"").hex(), int.from_bytes(kv.get(b"udp", b""), "big"),
            fork_hash(kv.get(b"eth")))

def fork_hash(eth):
    # The `eth` value is [[fork hash, fork next], ...].
    try:
        fid = items(eth, *items(eth, 0, len(eth))[0])
        return eth[fid[0][0]:fid[0][1]].hex()
    except Exception:
        return None

try:
    before = json.load(open(committed))
except ValueError:
    print("  key rotations: no committed crawl set to carry scores from")
    sys.exit(0)
nodes = json.load(open(path))
at, unreadable = {}, 0
for nid, v in nodes.items():
    try:
        e = endpoint(v["record"])
    except Exception:
        unreadable += 1
        continue
    if e[0] and e[2] in pins:
        at.setdefault(e, []).append(nid)

def answered(nid):
    return str(nodes[nid].get("lastResponse") or "") >= start

moved, points = {}, 0
for e, ids in at.items():
    now = [i for i in ids if answered(i)]
    if not now or len(ids) < 2:
        continue
    # The newest key answering here, and the silent keys it can have replaced.
    new = max(now, key=lambda i: (str(nodes[i].get("firstResponse") or ""), i))
    first = str(nodes[new].get("firstResponse") or "")
    old = [i for i in ids if not answered(i) and int(before.get(i, {}).get("score") or 0) > 0
           and str(nodes[i].get("lastResponse") or "") <= first]
    if not old:
        continue
    carried = max(int(before[i]["score"]) for i in old)
    nodes[new]["score"] = int(nodes[new].get("score") or 0) + carried
    for i in old:
        del nodes[i]
    moved[pins[e[2]]] = moved.get(pins[e[2]], 0) + 1
    points += carried
if moved:
    with open(path, "w") as f:
        json.dump(nodes, f, indent=4)     # devp2p's own layout, so the committed file keeps its form
print("  key rotations, nodes that took over the score of a silent key at the same endpoint and fork: %s, %d points%s"
      % (", ".join("%s %d" % (net, moved.get(net, 0)) for net in sorted(set(pins.values()))), points,
         "; %d records could not be read" % unreadable if unreadable else ""))
PYEOF
}

# Record whether each bootnode Core-Geth ships answered this run's crawl, for the
# status issue -- see scripts/report-status.sh. Read from the crawl's own record
# rather than pinged again: the crawl starts from these nodes and re-checks every
# node it holds, so a bootnode's lastResponse already says whether it answered
# this run. A bootnode is matched by its public key, which its enode URL carries
# and its node record's `secp256k1` entry holds in compressed form.
#
# Informational only. A bootnode that misses the crawl does not stop a publish,
# because clients reach the trees without it, and a failure here does not stop
# the run either: the status issue then shows the bootnodes as not checked.
bootnode_status() {
  local out="$1"
  [ -n "$out" ] && rm -f -- "$out"
  python3 - "$out" "$RUN_START" all.json "classic=$BOOT_CLASSIC" "mordor=$BOOT_MORDOR" <<'PYEOF'
import base64, json, re, sys
out, start, current = sys.argv[1:4]

def item(b, i):
    # One RLP item at b[i]: (payload start, payload end).
    p = b[i]
    if p < 0x80: return i, i + 1
    if p < 0xb8: return i + 1, i + 1 + p - 0x80
    if p < 0xc0:
        s = i + 1 + p - 0xb7
        return s, s + int.from_bytes(b[i + 1:s], "big")
    if p < 0xf8: return i + 1, i + 1 + p - 0xc0
    s = i + 1 + p - 0xf7
    return s, s + int.from_bytes(b[i + 1:s], "big")

def items(b, start, end):
    out = []
    while start < end:
        s, e = item(b, start)
        out.append((s, e))
        start = e
    return out

def record_key(record):
    # The ENR is [signature, seq, key, value, ...].
    s = record[4:]
    raw = base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))
    top = items(raw, *item(raw, 0))
    for k, v in zip(top[2::2], top[3::2]):
        if raw[k[0]:k[1]] == b"secp256k1":
            return raw[v[0]:v[1]].hex()

nodes = {}
for v in json.load(open(current)).values():
    try:
        key = record_key(v["record"])
    except Exception:
        continue   # a record this cannot read is no bootnode's: those are matched below
    if key:
        nodes[key] = v

rows = []
for arg in sys.argv[4:]:
    net, _, urls = arg.partition("=")
    for url in filter(None, urls.split(",")):
        m = re.fullmatch(r"enode://([0-9a-fA-F]{128})@([^?]+)(\?.*)?", url.strip())
        if not m:
            sys.exit("  WARNING: %s bootnode is not an enode URL: %s" % (net, url))
        pub = bytes.fromhex(m.group(1))
        # Compressed: 02 or 03 for the parity of y, then x.
        v = nodes.get((bytes([2 + (pub[-1] & 1)]) + pub[:32]).hex(), {})
        last = str(v.get("lastResponse") or "")
        last = None if last[:4] in ("", "0001") else last
        rows.append({"network": net, "host": m.group(2), "id": m.group(1)[:16].lower(),
                     "answered": bool(last) and last >= start, "last_answered": last})
        print("  bootnode %s %s: %s" % (net, m.group(2), "answered" if rows[-1]["answered"]
              else "did not answer, last answered %s" % (last or "never")))
if out:
    json.dump(rows, open(out, "w"), indent=2)
PYEOF
}

publish_tree() {
  local domain="$1" publisher="$2" src="$3" net="$4" min="$5" zone="$6"
  shift 6
  local dir="$domain"
  mkdir -p "$dir"
  "$DEVP2P" nodeset filter "$src" -eth-network "$net" "$@" > "$dir/nodes.raw.json" \
    || fail "filter failed for $domain"

  # Before the cap, so the cap chooses among current nodes only -- see
  # FORK_HASH_CLASSIC.
  local fork; fork=$(fork_hash_for "$net") || fail "$domain: no current fork hash for network '$net'"
  keep_current_fork "$dir/nodes.raw.json" "$net" "$fork" "$dir" \
    || fail "$domain: current-fork check failed -- refusing to publish"

  # Rank before truncating, so the cap keeps chosen nodes rather than an
  # arbitrary slice -- see rank_and_cap.
  local cap; cap=$(cap_for "$net")
  rank_and_cap "$dir/nodes.raw.json" "$dir/nodes.json" "$cap" "$domain" \
    || fail "$domain: ranking failed -- refusing to publish"
  rm -f "$dir/nodes.raw.json"

  local n; n=$(count "$dir/nodes.json")

  # Two checks, because a fixed floor alone cannot tell a broken run from a
  # degraded one. A floor set high enough to catch a lost-seed run would fail a
  # legitimate crawl-only run, and one set low enough to pass both never fires.
  if [ "$n" -lt "$min" ]; then
    fail "$domain: $n nodes is below the absolute floor of $min -- refusing to publish"
  fi

  # The relative check is the one that matters after the first run: replacing a
  # full tree with a much smaller one is a downgrade for everyone who switched to
  # it, even when the smaller one is a healthy crawl-only result.
  # Compare against the last COMMITTED tree, not the working file, which this
  # run has already overwritten.
  local prev
  prev=$(git show "HEAD:$dir/nodes.json" 2>/dev/null | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)
  if [ "$prev" -gt 0 ]; then
    local floor_rel=$(( prev * SHRINK_TOLERANCE_PCT / 100 ))
    if [ "$n" -lt "$floor_rel" ]; then
      fail "$domain: $n nodes is under $SHRINK_TOLERANCE_PCT% of the $prev last published -- refusing to publish"
    fi
    log "$domain: $n nodes (last published $prev)"
  else
    log "$domain: $n nodes (first publish)"
  fi

  [ "$DRY_RUN" -eq 1 ] && { log "$domain: dry run, not signing or publishing"; return 0; }

  # devp2p's `dns sign` loads an Ethereum keystore JSON and reads its password
  # from stdin -- it does not accept a raw hex key. Both halves are required.
  [ -n "${DNS_SIGNING_KEY_FILE:-}" ] || fail "DNS_SIGNING_KEY_FILE is unset"
  [ -n "${DNS_SIGNING_KEY_PASSWORD_FILE:-}" ] || fail "DNS_SIGNING_KEY_PASSWORD_FILE is unset"
  [ -f "$DNS_SIGNING_KEY_FILE" ] || fail "no signing key at $DNS_SIGNING_KEY_FILE"
  [ -f "$DNS_SIGNING_KEY_PASSWORD_FILE" ] || fail "no key password at $DNS_SIGNING_KEY_PASSWORD_FILE"
  "$DEVP2P" dns sign "$dir" "$DNS_SIGNING_KEY_FILE" -domain "$domain" \
    < "$DNS_SIGNING_KEY_PASSWORD_FILE" \
    || fail "sign failed for $domain"

  case "$publisher" in
    cloudflare) publish_cloudflare "$dir" "$zone" ;;
    desec)      publish_desec "$dir" ;;
    txt)        "$DEVP2P" dns to-txt "$dir" "$dir/records.txt.json" \
                  || fail "to-txt failed for $domain"
                log "$domain: rendered to $dir/records.txt.json, not published" ;;
    *)          fail "unknown publisher '$publisher' for $domain" ;;
  esac
  log "$domain: published via $publisher"
}

log "devp2p: $("$DEVP2P" --version 2>/dev/null || echo unknown)"

# Resolve every Cloudflare zone ID before the crawl rather than after it. A
# missing ID is a configuration error that cannot fix itself, and discovering it
# an hour into a run throws the crawl away -- on the nightly schedule that costs
# a full day. Dry runs never publish, so they do not need one.
if [ "$DRY_RUN" -eq 0 ]; then
  for entry in $DOMAINS; do
    case "${entry##*:}" in
      cloudflare)
        zone_id_for "${entry%%:*}" >/dev/null \
          || fail "no Cloudflare zone ID for ${entry%%:*}: set CLOUDFLARE_ZONE_IDS" ;;
    esac
  done
fi

# Seed first, so the crawl revalidates the seeded nodes rather than ignoring them.
seed_from_trees all.json

crawl classic "$BOOT_CLASSIC" all.json
crawl mordor  "$BOOT_MORDOR"  all.json
log "crawl set: $(count all.json) nodes total (both networks, unfiltered)"

# Before the checks below, so a refused run still reports its bootnodes.
bootnode_status "$BOOTNODE_STATUS" \
  || log "WARNING: could not read the bootnodes' answers from the crawl; the status issue will show them as not checked"

# Before any tree is published, so a refusal never leaves one domain updated and
# the others not. A refused run commits nothing, so the scores this crawl cut on
# nodes it could not reach are discarded with it.
check_reach || fail "the crawl did not reach the network -- refusing to publish anything"

# Once per network, from core-geth's config -- not per tree, and not from the
# crawl. Warn only; it never refuses or switches the filter -- see
# check_fork_schedule.
for net in classic mordor; do
  check_fork_schedule "$net" \
    || log "WARNING: $net: core-geth fork schedule could not be read"
done

for entry in $DOMAINS; do
  domain="${entry%%:*}"
  for net in classic mordor; do
    check_retention "all.$net.$domain" \
      || log "WARNING: all.$net.$domain: retention could not be read"
  done
done

# After the checks, which read the crawl as it came back, and before the trees
# are ranked, which read the scores this leaves -- see carry_over.
carry_over all.json || fail "could not carry scores across key rotations -- refusing to publish anything"

# Only `all.` trees are published. No core-geth path points snap discovery at a
# `snap.*` tree on any network -- SnapDiscoveryURLs is set equal to
# EthDiscoveryURLs at every assignment site, and SetDNSDiscoveryDefaults
# hardcodes protocol "all" -- and neither fukuii client reads them either. They
# would cost roughly 45% of the zone's record budget for nothing, which on a
# 200-record budget is the difference between 120 published classic nodes and 65.
for entry in $DOMAINS; do
  domain="${entry%%:*}"
  publisher="${entry##*:}"
  zone=""
  [ "$publisher" = cloudflare ] && zone=$(zone_id_for "$domain")
  publish_tree "all.classic.$domain" "$publisher" all.json classic "$MIN_NODES_CLASSIC" "$zone"
  publish_tree "all.mordor.$domain"  "$publisher" all.json mordor  "$MIN_NODES_MORDOR"  "$zone"
done

log "done"
