# discv4-dns-lists

Publishes the Ethereum Classic [EIP-1459](https://eips.ethereum.org/EIPS/eip-1459)
DNS discovery trees. A crawl of the discv4 DHT is filtered per network, capped,
signed with the project key and written to DNS; the resulting node sets are
committed here as the public audit trail.

These trees continue the discovery service the ETC Cooperative maintained through
`etclabscore/discv4-dns-lists`, and core-geth's `v1.13` line reads them by default.
The note at the top of `README.md` is the migration guidance for operators; keep
it consistent with core-geth's own ETC Cooperative transition page.

[`docs/`](docs/) explains *why* each design choice was made and is the reference
for the mechanism; [README.md](README.md) is the landing page that routes to it.
This file is what an agent needs in order to work here without breaking
something.

**This repository is bootstrap infrastructure for a live network.** A bad publish
is not a failing build — it is clients that cannot find peers. Every rule below
about refusing, floors and confirmation exists for that reason.

## Stack

There is **no package manifest of any kind** in this repository — no
`package.json`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `Makefile` or
equivalent. Nothing here is installed or built from a dependency declaration.
That absence is real; do not go looking for a manifest to update.

| Tool | Used for | Where it comes from |
|---|---|---|
| `bash` | `scripts/update-lists.sh` | system |
| `jq` | record counts in the deSEC publisher and the nightly commit message | system |
| `python3` | everything that reads node records: seed merge and prune, node counts, the fork check, ranking, the run's checks, bootnode status | system |
| `git` | committing published trees | system |
| `gh` | `scripts/report-status.sh`, the status issue | preinstalled on GitHub runners |
| `devp2p` | crawl, filter, sign, publish | **built from source, see below** |

**`devp2p` must be built from [`ethereumclassic/core-geth`](https://github.com/ethereumclassic/core-geth).**
Upstream go-ethereum's copy has no `classic` or `mordor` value for
`-eth-network` and rejects them with exit 1, so a build from the wrong source
fails the run rather than quietly publishing an empty tree. It is built with
core-geth's own `go run build/ci.go install -dlgo`, which compiles it with the
Go that core-geth's `build/checksums.txt` pins for its releases. The version
moves when core-geth moves that pin, the workflow refuses a binary compiled by
any other Go, and this repository pins none.

## Commands

Every command below exists. There is **no `test`, `lint`, `build` or `fmt`
target of any kind**, because there is no task runner to define one in.

```bash
# Build the tool (required before anything else), with the Go core-geth pins,
# which the first run downloads
git clone https://github.com/ethereumclassic/core-geth.git /tmp/core-geth
cd /tmp/core-geth && go run build/ci.go install -dlgo ./cmd/devp2p

# Dry run: crawls, filters and caps, but never signs or publishes.
# Needs no secrets. This is the safe way to see what a crawl would produce.
DEVP2P=/tmp/core-geth/build/bin/devp2p CORE_GETH_SRC=/tmp/core-geth ./scripts/update-lists.sh --dry-run
```

Exit codes: `0` published or dry run clean, `1` refused or failed, `2`
did-not-run (a required tool is missing).

### Checking the script

No linter or formatter is configured anywhere in this repository, and no CI job
runs one. Match the existing style by hand. If `shellcheck` is available, it is
worth running, but nothing gates on it:

```bash
bash -n scripts/update-lists.sh                     # parse check
shellcheck -S style scripts/update-lists.sh         # optional, not a gate
python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' \
  .github/workflows/update-dns-lists.yml            # workflow parse check
```

### Checking a published tree

`devp2p dns sync` uses the system resolver, fetches one record at a time and
gives each lookup five seconds with no retry, so one slow answer fails the whole
sync (`--timeout` lengthens the limit). A stub resolver such as
`systemd-resolved` at `127.0.0.53` fails it on a large tree while that same tree
resolves fine through a public resolver. **Re-query a
failed lookup with `dig @1.1.1.1` before concluding a tree is dead.** This has
been misread as a network fault more than once.

## Structure

```
scripts/update-lists.sh              # the whole pipeline: seed, crawl, filter, cap, sign, publish
scripts/report-status.sh             # rewrites the status issue after every scheduled run
.github/workflows/update-dns-lists.yml  # runs it; builds devp2p, handles secrets, commits results
.github/FUNDING.yml                  # the Sponsor button, pointing at docs/support.md
SECURITY.md                          # how to report a vulnerability privately
docs/                                # operator and maintainer documentation; README.md routes to it
all.json                             # working node set, unfiltered, cumulative across runs
all.<network>.<domain>/nodes.json    # one published tree per network per domain
```

The `all.*` directories are **generated output committed by the workflow**, not
hand-maintained source. Do not edit a `nodes.json` by hand.

## Domains

Three domains, all served from one Cloudflare account.

| Domain | Provider | Publisher |
|---|---|---|
| `ethereumclassic.net` | Cloudflare | `devp2p dns to-cloudflare` |
| `ethclassic.net` | Cloudflare | `devp2p dns to-cloudflare` |
| `ethereumclassic.network` | Cloudflare | `devp2p dns to-cloudflare` |

**One DNS account is not provider diversity.** A problem with the Cloudflare
account takes all six trees offline at once; three names protect only against a
problem with one name or zone. Do not describe these trees as provider-redundant.
The account has no part in the bootnodes, which clients reach by IP address, and
it cannot alter a tree: every record is signed with the project key, which is
held apart from the account, and clients verify it.

**Each Cloudflare domain needs its zone ID.** `devp2p` resolves a zone by name
only when `--zoneid` is absent, and it passes the *tree* name to that lookup, so
it matches no zone and the publish fails. `CLOUDFLARE_ZONE_IDS` carries
`domain=zoneid` pairs; the script refuses before the crawl if one is missing. A
zone ID is not a credential and belongs in the workflow's env block, not its
secrets.

**Moving a domain to another provider needs no `devp2p` change and no client
release**, since the tree URL stays the same. `devp2p` automates Cloudflare and
Route53 only, so anything else is published from `to-txt` output by a script in
this repository, selected per domain in `DOMAINS`.

**Any such publisher must be incremental.** EIP-1459 records are
content-addressed, so an unchanged node keeps its record name and value and only
genuine churn needs writing. Deleting and recreating every record costs two
operations per record, about 300 a night for a domain carrying both trees, which
exceeds a typical free-tier daily change budget. The `desec` branch is the shape
this takes: it renders with `to-txt` and delegates to `$DESEC_PUBLISHER`. No
publisher is configured, so selecting that branch fails rather than publishing.

## The numbers, and why they are what they are

Change none of these without reading the reasoning in `docs/pipeline.md`,
`docs/node-selection.md` and the script's own comments first.

- **Caps** — `CAP_CLASSIC=120`, `CAP_MORDOR=15`. Derived from the DNS zone
  budget, not from crawl yield. A tree of N nodes costs N + 1 root + ~1 branch
  per 11 nodes, so 120 → ~132 records and 15 → ~18, **~150 together**. A
  Cloudflare free-plan zone holds 200 for the whole zone, not per tree — both
  trees share it, alongside mail records, the apex site and service subdomains,
  and whatever the zone already holds. Raising either cap eats that headroom.
- **Per-address limit** — `MAX_PER_ADDRESS=2`. No address publishes more than two
  nodes, whatever seats are left, because one machine is one point of failure
  however many node keys it runs. On the 2026-11-05 crawl two addresses ran 25 of
  the answering classic keys between them, one with 20 on consecutive ports; a
  key-counting ranking publishes all 25, and the cap holds the two to two seats
  each. A seat only a host already holding two could fill stays empty.
- **Per-subnet limit** — `MAX_PER_SUBNET=2`. No `/24`, or `/48` for IPv6, publishes
  more than two nodes either, so acquiring many addresses in one subnet buys no more
  than acquiring one. The per-address cap holds one machine; this holds one operator
  spreading over addresses in a subnet it controls. It falls on no operator who only
  shares a provider: on the 2026-11-05 crawl 101 of the 103 `/24`s held at most two
  nodes already, and the two that held more were the single-address concentrators the
  per-address cap had itself capped, so the subnet cap removed nothing further. The
  ranking stays network-blind: both limits are ceilings, never a tier that ranks a
  subnet's best node first, which reads as diversity but would hand one node per
  `/24` a tree-worth of seats on its first night.
- **Floors** — `MIN_NODES_CLASSIC=40`, `MIN_NODES_MORDOR=5`. These are floors
  against a broken run, **not targets**. `MIN_NODES_MORDOR` is 5, well below a
  normal night's Mordor count, deliberately: Mordor's ceiling is the network, not
  the crawl, and a floor scaled from classic's numbers would refuse every
  legitimate Mordor publish. Each night's counts are in its commit message.
- **Shrink tolerance** — 50% of the last *committed* tree. A tree that would
  shrink below half of the last one is refused. It is the guard against a crawl
  that lost its seed trees, and, since only nodes that answered are published,
  it also refuses a night on which most of a tree's nodes did not answer, until
  enough of them answer again. It reads its baseline from
  `git show HEAD:<dir>/nodes.json`, **so the commit step is load-bearing**: if
  trees are never committed there is no baseline and the check cannot fire.
- **Reach** — `REACH_MIN_PCT=50`. Before any tree is built, the run refuses if
  the crawl reached fewer than half of the nodes that answered an earlier run.
  This is the guard against the runner's own connectivity failing, which marks
  every node as failing at once: it refuses the whole run and names the cause,
  where the floors and the shrink check would only see a small tree. The crawl
  set holds nodes of every network, so its answer rate measures the runner, not
  Ethereum Classic.
- **Retention** — `RETENTION_MIN_PCT=50`. The run warns on the status issue,
  without refusing, if fewer than half of a tree's last published endpoints
  answered under any key. Operators rotating keys together can silence most of a
  tree at once, as the move to the `v1.13` line asks, and a refusal on that count
  would repeat every night against the same committed tree.
- **Fork hashes** — `FORK_HASH_CLASSIC=be46d57c`, `FORK_HASH_MORDOR=3a6b00d7`. A
  published tree keeps only nodes on its network's current fork hash, because
  `-eth-network` admits every stage of the fork schedule, including the genesis
  stage that unsynced and non-ETC nodes advertise. A node on a later hash is left
  out, never a refusal: one spoofed `eth` entry must not be able to freeze every
  tree, and the nodes still on the current fork are the ones serving syncing
  peers, so they stay published until a human bumps the pin. The pin does not
  follow core-geth automatically, because a fork lands in core-geth's `main`
  config before its release is cut and before it activates on chain, while the
  current-fork nodes keep serving until then. `check_fork_schedule` reads
  core-geth's own config each run and only warns when the schedule has moved past
  the pin. Change a pin only when the network has passed a fork, taking the value
  from `ethereumclassic/core-geth`'s `params/config_classic.go` and
  `params/config_mordor.go` (`core/forkid/forkid_test.go` cross-checks the
  resulting hash), and bump `FORK_SCHEDULE_CLASSIC`/`FORK_SCHEDULE_MORDOR` in the
  same change.

The floors, the shrink tolerance and the reach check refuse rather than publish.
A client reading a tree cannot tell a broken crawl from a quiet network, so
refusing is the correct direction for each of them. The current-fork filter
refuses only when no node carries the pin at all; retention and the fork-schedule
check only warn, for the reasons given above.

## Facts that mislead if you do not know them

- **The node set is cumulative.** `devp2p discv4 crawl` appends to an existing
  set rather than replacing it. One crawl sees one moment — a low cold-start
  yield is not a broken crawl.
- **Seeding is reach, not trust.** The pipeline seeds from published trees, its
  own and the predecessor's for as long as they resolve, then the crawl re-pings
  every seeded node. A node that does not answer is not republished, and it is
  removed: after a few missed checks if it once answered, or, if it never
  answered, once no seed tree carries it. That second prune runs only when every
  seed tree synced, so a resolver fault here is never read as the trees dropping
  those records.
- **A score follows its endpoint across a key rotation.** The crawler keys a node
  by its public key, so a rotated key would start again from zero. A node that
  answers at the endpoint, IP address and UDP port, of a key that went silent,
  on the same network's current fork hash, takes over that key's committed score
  (`carry_over`), and ties in the ranking go to the endpoint, so rotating a key,
  as the move off the `v1.12` line asks, costs a node nothing in the ranking.
  Only the networks published here are considered; the crawl set's other
  networks are left as the crawl wrote them.
- **A failed run is reported on one status issue.** GitHub's own notification
  for a scheduled run reaches only whoever last edited its schedule, so the
  workflow also keeps a single issue labeled `pipeline-status`, rewrites it
  after every scheduled run, and comments on it only when the state changes.
  GitHub sends no notification for an edit, so subscribing to that issue is how
  to hear of a failure and of the recovery. The issue also lists whether each
  bootnode Core-Geth ships answered the crawl. A bootnode that misses it does
  not stop the publish; it gets one comment, which the first run it answers
  again deletes. Do not close the issue or remove its label; the workflow finds
  it by label and author, never by title, and finds its bootnode comments by
  marker and author. A run that publishes can still warn, as when most of a
  tree's endpoints did not answer, and the issue shows that run's warnings.
- **The issue also carries a concentration gauge.** Whenever a cap bound a tree,
  the issue shows, per network, the most nodes any one address or subnet offered
  and how many the caps held back. It is aggregate and names no address: the
  concentrated IPs are already public in the trees, and an operator's intent is
  unknown, so a figure that climbs from night to night is a prompt to look, never
  an accusation to publish. A night that bound no cap shows nothing.
- **Only `all.*` trees are published.** No `snap.*` — no core-geth path points
  snap discovery at one on any network. No `les.*` — core-geth's `v1.13` line
  reads the `all.*` trees in every sync mode, light included. Adding either spends
  the record budget on trees nothing reads.
- **Contact addresses are on `ethereumclassic.net`**, the domain for the public
  goods the `ethereumclassic` organization maintains, and they match Core-Geth's.
  Security reports go to `security@ethereumclassic.net` (`SECURITY.md`), never to
  a public issue. Funding mail goes to `donations@ethereumclassic.net`
  (`docs/support.md`). Do not move either to another domain, and do not publish a
  donation address: one is provided on request from that mailbox.
- **The Ethereum Classic DAO is the legal entity that maintains these public
  goods and, today, their funder of last resort.** Credit it in the funders table
  of `docs/support.md`, and do not write as though its funding settles the
  matter: that page asks the network's stakeholders to sponsor the work so that
  it no longer rests on one backer. The table is the operator's record: add or
  change an entry only when asked to.

## Dependency updates

**`.github/dependabot.yml` exists and version updates are deliberately off**
(`open-pull-requests-limit: 0`). Recorded 2026-08-31.

- **No ecosystem key can name a manifest here, because there is no manifest.**
  The only `package-ecosystem` that names something this repository actually
  holds is `github-actions`, for the SHA-pinned actions in the workflow.
- **The limit is zero because nobody is triaging a standing pull-request
  queue.** Two pinned actions is not a dependency surface that needs one.
- **Dependabot *security* updates are a repository setting with no key in that
  file.** Nothing in `dependabot.yml` turns them on or off, and a limit of zero
  does not withhold them. Confirm the repository setting's state rather than
  inferring it from the config.
- **What would change this:** the repository gaining a real manifest, or someone
  taking ownership of the queue. Raising the limit brings a `cooldown:` block
  with it; while the limit is zero a cooldown gates nothing and would read as a
  control that is operating.

Do not "fix" the disabled config into an active one. Its state is a decision.

## Boundaries

### Ask first

- **Any push, to any remote.** This is a public repository of the Ethereum
  Classic organization and it becomes bootstrap infrastructure for a live
  network. Nothing leaves the machine without explicit confirmation.
- **Any commit.** Including a commit that only touches documentation.
- **Changing or disabling the nightly schedule.** It runs daily because the
  leaf records carry a one-day TTL; the reasoning is on the `schedule:` block in
  the workflow.
- **Changing a cap, a floor, the shrink tolerance, the reach or retention
  threshold or a fork hash.** See above.
- **Changing the per-address or per-subnet limit.** See above.
- **Adding a domain, a DNS provider or a publisher.**
- **Changing anything under `.github/workflows/`.** These run in the
  organization's CI with the organization's secrets.

### Never

- **Commit a signing key, in any form, encrypted or not.** The key's public half
  is compiled into every client as the `enrtree://<pubkey>@<domain>` prefix;
  losing the private half means every release that shipped it must be rebuilt.
  It is a long-lived project key, not a CI credential. It lives only in the
  `DNS_SIGNING_KEY` secret and is written to runner temp, then removed in a step
  that runs even when the job fails.
- **Commit any credential**, DNS API token included.
- **Use `git add .` or `git add -A`.** Stage named paths. A run leaves untracked
  build output beside the trees it should commit.
- **Hand-edit a generated `nodes.json`.**
- **Add, change, or recommend changing `LICENSE`.** Licensing is the operator's
  and is a legal question before it is a technical one.
- **Publish a tree that failed a check.** Every check that refuses does so
  deliberately.

### Secrets the workflow expects

| Secret | Purpose |
|---|---|
| `DNS_SIGNING_KEY` | Ethereum **keystore JSON** for the tree-signing key |
| `DNS_SIGNING_KEY_PASSWORD` | password for that keystore |
| `CLOUDFLARE_API_TOKEN` | token scoped to DNS edit on the Cloudflare zones |

`devp2p dns sign` loads a keystore JSON with `keystore.DecryptKey` and reads the
password from **stdin**. A raw hex key fails with `error decrypting key`. That is
why there are two secrets and not one.

## Conventions

- **Verify by effect, and calibrate the check so it can fail.** A check that
  cannot report a negative proves nothing. This applies to gitignore coverage
  (`git check-ignore --no-index -q -- <path>`, never `-v` as the condition), to
  DNS lookups, and to any claim that something works.
- **Comments carry reasoning, not description.** The existing code explains why a
  number is what it is and what breaks if it changes. Match that.
- **Prefer refusing to guessing.** Every failure path in the pipeline exits
  rather than continuing with a degraded result.
- **Branching:** work lands on `main`. Inferred from history — the repository has
  a single branch and no recorded policy. Confirm before assuming it is settled.
