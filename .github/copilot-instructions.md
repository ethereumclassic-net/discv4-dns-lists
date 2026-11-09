# Copilot Instructions: discv4-dns-lists

<!--
  SELF-CONTAINED, deliberately. This repository is public, so its audience is
  not one person's toolchain, and several Copilot surfaces -- github.com Chat,
  VS Code code review, and the Chat and code-review surfaces of Visual Studio,
  JetBrains, Eclipse and Xcode -- do not read AGENTS.md at all. On those, this
  file is the only instruction the model sees, so a thin pointer would leave it
  with nothing.

  The cost of that choice is duplication with AGENTS.md. Pay it deliberately:
  when either file changes, change both. Do not let the two contradict each
  other -- wherever a surface reads both, both are supplied to the model.
-->

## Project

Publishes the Ethereum Classic [EIP-1459](https://eips.ethereum.org/EIPS/eip-1459)
DNS discovery trees. A crawl of the discv4 DHT is filtered per network, capped,
signed with the project key and written to DNS; the node sets are committed here
as the public audit trail.

These trees continue the discovery service the ETC Cooperative maintained through
`etclabscore/discv4-dns-lists`, and core-geth's `v1.13` line reads them by default.
The note at the top of `README.md` is the migration guidance for operators.

**This is bootstrap infrastructure for a live network.** A bad publish is not a
failing build — it is clients that cannot find peers.

**All three domains are served from one Cloudflare account.** That is one DNS
provider, so do not describe the trees as provider-redundant. The account has no
part in the bootnodes, which clients reach by IP address, and cannot alter a tree,
because every record is signed with the project key.

**Contact addresses are on `ethereumclassic.net`** and match Core-Geth's. Security
reports go to `security@ethereumclassic.net` (`SECURITY.md`), never to a public
issue. Funding mail goes to `donations@ethereumclassic.net` (`docs/support.md`).
Do not move either to another domain, and do not publish a donation address.

**The Ethereum Classic DAO is the legal entity that maintains these public goods
and, today, their funder of last resort.** Credit it in the funders table of
`docs/support.md`, and do not write as though its funding settles the matter:
that page asks the network's stakeholders to sponsor the work. The table is the
operator's record; change an entry only when asked to.

## Stack

There is **no package manifest of any kind** here: no `package.json`, `go.mod`,
`Cargo.toml`, `pyproject.toml` or `Makefile`. Nothing is installed from a
dependency declaration. Do not look for a manifest to update, and do not
suggest adding one.

- `bash` — `scripts/update-lists.sh`, the whole pipeline
- `jq` — record counts in the deSEC publisher and the nightly commit message
- `python3` — everything that reads node records: seed merge and prune, node
  counts, the fork check, ranking, the run's checks, bootnode status
- `gh` — `scripts/report-status.sh`, the status issue; preinstalled on GitHub
  runners
- `devp2p` — **built from `ethereumclassic/core-geth`**, not from upstream
  go-ethereum, whose copy has no `classic` or `mordor` value for `-eth-network`
  and rejects them with exit 1. It is built with core-geth's own
  `go run build/ci.go install -dlgo`, so the Go that compiles it is the one
  core-geth's `build/checksums.txt` pins for its releases; this repository pins
  none

## Commands

Every command below exists. There is **no `test`, `lint`, `build` or `fmt`
target**, because there is no task runner to define one in. Do not invent a call
to one.

```bash
# Build the tool, with the Go core-geth pins, which the first run downloads
git clone https://github.com/ethereumclassic/core-geth.git /tmp/core-geth
cd /tmp/core-geth && go run build/ci.go install -dlgo ./cmd/devp2p

# Dry run: crawls, filters and caps; never signs or publishes; needs no secrets
DEVP2P=/tmp/core-geth/build/bin/devp2p CORE_GETH_SRC=/tmp/core-geth ./scripts/update-lists.sh --dry-run
```

Exit codes: `0` published or dry run clean, `1` refused or failed, `2`
did-not-run.

No linter or formatter is configured and no CI job runs one — match the existing
style by hand. `bash -n` parses the script and `shellcheck -S style` is worth
running, but nothing gates on either.

## Structure

```
scripts/update-lists.sh                 # seed, crawl, filter, cap, sign, publish
scripts/report-status.sh                # rewrites the status issue after every run
.github/workflows/update-dns-lists.yml  # runs it; builds devp2p, handles secrets, commits
.github/FUNDING.yml                     # the Sponsor button, pointing at docs/support.md
SECURITY.md                             # how to report a vulnerability privately
docs/                                   # operator and maintainer docs; README.md routes to them
all.json                                # working node set, unfiltered, cumulative
all.<network>.<domain>/nodes.json       # one published tree per network per domain
```

`all.*` directories are **generated output committed by the workflow**. Never
hand-edit a `nodes.json`.

## The numbers are load-bearing

- **Caps** (`CAP_CLASSIC=120`, `CAP_MORDOR=15`) come from the DNS zone
  budget, not from crawl yield. A Cloudflare free-plan zone holds 200 records and
  discovery does not get all of it — these domains also carry mail records, the
  apex site and service subdomains. Raising a cap eats that headroom.
- **Per-address limit** (`MAX_PER_ADDRESS=2`): no address publishes more than
  two nodes, whatever seats are left, because one machine is one point of failure
  however many node keys it runs. A seat only a host already holding two could
  fill stays empty.
- **Per-subnet limit** (`MAX_PER_SUBNET=2`): no `/24`, or `/48` for IPv6,
  publishes more than two either, so a tree spreads across networks as well as
  machines. A `/24` is far narrower than a hosting provider, so the limit does
  not fall on operators who only share one. Both limits are ceilings on the
  ranking, never a ranking of their own.
- **Floors** (`MIN_NODES_CLASSIC=40`, `MIN_NODES_MORDOR=5`) are guards against a
  broken run, **not targets**. Mordor's 5 is deliberate — its ceiling is the
  network, not the crawl.
- **Shrink tolerance** (50% of the last *committed* tree) refuses a tree that
  would shrink below half of the last one: a crawl that lost its seed trees, or
  a night on which most of a tree's nodes did not answer. It reads its baseline
  with `git show HEAD:<dir>/nodes.json`, so the commit step is load-bearing: with
  nothing committed there is no baseline and the check cannot fire.
- **Reach** (`REACH_MIN_PCT=50`) refuses the whole run, before any tree is
  built, if the crawl reached fewer than half of the nodes that answered an
  earlier run. It guards against the runner's own connectivity failing, which
  marks every node as failing at once. The crawl set is mostly other networks,
  so its answer rate measures the runner, not Ethereum Classic.
- **Retention** (`RETENTION_MIN_PCT=50`) warns on the status issue, without
  refusing, if fewer than half of a tree's last published endpoints answered
  under any key. Operators rotating keys together can silence most of a tree at
  once, and a refusal on that count would repeat every night against the same
  committed tree.
- **Fork hashes** (`FORK_HASH_CLASSIC=be46d57c`, `FORK_HASH_MORDOR=3a6b00d7`)
  restrict a tree to nodes on its network's current fork hash, because
  `-eth-network` admits every stage of the fork schedule, including the genesis
  stage. A node on a later hash is left out, never a refusal: the current-fork
  nodes are the ones serving syncing peers. The pin is not read from core-geth
  automatically, because a fork is scheduled in its `main` config before the
  release is cut and before it activates on chain; `check_fork_schedule` reads
  that config each run and only warns when the schedule has moved past the pin.
  Change a pin only after the network has passed a fork, from
  `ethereumclassic/core-geth`'s `params/config_classic.go` and
  `params/config_mordor.go`, and bump `FORK_SCHEDULE_CLASSIC`/`FORK_SCHEDULE_MORDOR`
  with it.

A node's score follows its endpoint, IP address and UDP port, across a rotation
of its node key: a node answering at the endpoint of a key that went silent, on
the same network's current fork hash, takes over that key's committed score, and
ranking ties go to the endpoint, so rotating a key costs a node nothing in the
ranking. Only the networks published here are considered.

The floors, the shrink tolerance and the reach check refuse rather than publish,
which is always the correct direction: a client cannot tell a broken crawl from a
quiet network. The current-fork filter refuses only when no node carries the pin;
retention and the fork-schedule check only warn.

A refused or failed run is reported on one issue labeled `pipeline-status`,
which the workflow rewrites after every scheduled run and comments on only when
the state changes. A run that publishes can still warn, and the issue shows that
run's warnings. The issue also lists whether each bootnode Core-Geth ships
answered the crawl. A bootnode that misses it does not stop the publish; it gets
one comment, deleted once it answers again. The issue also shows the trees the
run built, one row per network: nodes against seats, how many first answered
that run, how many nodes the per-address and per-subnet limits held back, and
how the nodes that answered spread over addresses and `/24` or `/48` networks.
Subscribe to the issue for alerts; do not close it.

## Ask before

- **Pushing anything.** Public Ethereum Classic organization repository.
- **Committing anything**, documentation included.
- **Changing or disabling the nightly schedule.** It runs daily because the leaf
  records carry a one-day TTL.
- **Changing a cap, floor, the shrink tolerance, the reach or retention
  threshold or a fork hash.**
- **Changing the per-address or per-subnet limit.**
- **Adding a domain, DNS provider or publisher.** `devp2p` automates Cloudflare
  and Route53 only; anything else is published from `to-txt` output.
- **Editing anything under `.github/workflows/`.** These run in the
  organization's CI with the organization's secrets.

## Never

- **Commit a signing key in any form, encrypted or not.** Its public half is
  compiled into every client as the `enrtree://<pubkey>@<domain>` prefix; losing
  the private half means rebuilding every release that shipped it. It lives only
  in the `DNS_SIGNING_KEY` secret.
- **Commit any credential**, DNS API token included.
- **Use `git add .` or `git add -A`.** Stage named paths — a run leaves
  untracked build output beside the trees it should commit.
- **Add, change, or recommend changing `LICENSE`.** That is the operator's call
  and a legal question before a technical one.
- **Publish a tree that failed a check**, or weaken a check so a tree passes.

## Response style

- Code and commands first; explain only what was asked about.
- Concise bullets over paragraphs; tables for comparisons.
- No pleasantries, and do not repeat the prompt back.
- Say what you verified and how.
