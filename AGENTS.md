# discv4-dns-lists

Publishes the Ethereum Classic [EIP-1459](https://eips.ethereum.org/EIPS/eip-1459)
DNS discovery trees. A crawl of the discv4 DHT is filtered per network, capped,
signed with the project key and written to DNS; the resulting node sets are
committed here as the public audit trail.

These trees continue the discovery service the ETC Cooperative maintained through
`etclabscore/discv4-dns-lists`, and core-geth `v1.13.x` reads them by default. The
note at the top of `README.md` is the migration guidance for operators; keep it
consistent with core-geth's own ETC Cooperative transition page.

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
| `jq` | sorting and capping node sets | system |
| `python3` | seed merge and prune, node counts, fork check, shrink and retention baselines | system |
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
- **Floors** — `MIN_NODES_CLASSIC=40`, `MIN_NODES_MORDOR=5`. These are floors
  against a broken run, **not targets**. `MIN_NODES_MORDOR` is 5, well below a
  normal night's Mordor count, deliberately: Mordor's ceiling is the network, not
  the crawl, and a floor scaled from classic's numbers would refuse every
  legitimate Mordor publish. Each night's counts are in its commit message.
- **Shrink tolerance** — 50% of the last *committed* tree. This is the only
  guard against a crawl that lost its seed trees and would otherwise replace a
  full 120-node tree with a healthy-looking 44-node one. It reads its baseline
  from `git show HEAD:<dir>/nodes.json`, **so the commit step is
  load-bearing**: if trees are never committed there is no baseline and the
  check cannot fire.
- **Retention** — `RETENTION_MIN_PCT=50`. Before anything is published, the run
  refuses if fewer than half of the last committed tree's nodes answered it. This
  is the guard against the runner's own connectivity failing: a crawl that cannot
  reach the network marks every node as failing but does not shrink any tree,
  because the cap fills it from earlier runs. Measured over the first sixteen
  nightlies: 111 to 119 of 120 classic nodes answered the next night, and
  mordor's worst night was 8 of 13.
- **Fork hashes** — `FORK_HASH_CLASSIC=be46d57c`, `FORK_HASH_MORDOR=3a6b00d7`. A
  published tree keeps only nodes on its network's current fork hash, because
  `-eth-network` admits every stage of the fork schedule, including the genesis
  stage that unsynced and non-ETC nodes advertise. Once nodes appear on the hash
  that follows a pin, the run refuses and names the new value. Change a pin only
  when that network has passed a fork, and take the value from core-geth's
  `core/forkid/forkid_test.go`, never from the refusal alone.

Every one of these checks refuses rather than publishes. A client reading a tree
cannot tell a broken crawl from a quiet network, so refusing is always the
correct direction.

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
- **A failed run is reported on one status issue.** GitHub's own notification
  for a scheduled run reaches only whoever last edited its schedule, so the
  workflow also keeps a single issue labeled `pipeline-status`, rewrites it
  after every scheduled run, and comments on it only when the state changes.
  GitHub sends no notification for an edit, so subscribing to that issue is how
  to hear of a failure and of the recovery. Do not close it or remove its label;
  the workflow finds it by label and author, never by title.
- **Only `all.*` trees are published.** No `snap.*` — no core-geth path points
  snap discovery at one on any network. No `les.*` — core-geth `v1.13.x` reads
  the `all.*` trees in every sync mode, light included. Adding either spends the
  record budget on trees nothing reads.
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
- **Changing a cap, a floor, the shrink tolerance, the retention threshold or a
  fork hash.** See above.
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
- **Publish a tree that failed a check.** Every check refuses deliberately.

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
