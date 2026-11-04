# Moving a v1.12 node

This page is for a node on the Core-Geth `v1.12` line. Every such node should
move to the [`v1.13`](https://github.com/ethereumclassic/core-geth/releases/latest)
line, which reads the trees this repository publishes by default and closes the
flaws [the audits](https://coregeth.com/security/) found in `v1.12`. A node that
cannot move yet can [switch to these trees with one flag](#if-a-node-cannot-move-yet),
a small step that closes none of those flaws.

## Choose your guide

| The node runs on | Guide |
|---|---|
| Linux | [Moving a v1.12 node on Linux](moving-from-v1-12/linux.md) |
| macOS | [Moving a v1.12 node on macOS](moving-from-v1-12/macos.md) |
| Windows | [Moving a v1.12 node on Windows](moving-from-v1-12/windows.md) |
| Docker | [Moving a v1.12 node in Docker](moving-from-v1-12/docker.md) |

Each guide takes the same steps, in an order that keeps the node running until
the new release is downloaded and checked: record the node's block number and
ID, download the release, stop the node cleanly, install the release, rotate the
P2P node key, check the flags and the config file, start the node and confirm
the move, and roll back if you need to.
[coregeth.com/downloads](https://coregeth.com/downloads/#upgrade) lists every
file a release carries, with its checksum.

## What the move keeps, and what it changes

**The chain data stays where it is.** The `v1.12` and `v1.13` lines use the same
data directory for each network, so the new release opens the chain the old one
wrote. Nothing is copied and nothing resyncs. The node is down only between the
stop and the start, usually seconds, although the steps around them take about
twenty minutes. The account keystore is not touched.

**The P2P node key changes, and that is required.** One of the flaws in
`v1.12`, CVE-2026-26315, leaks bits of the node key across repeated handshakes,
and no fix can take back what has already leaked.
[coregeth.com/security](https://coregeth.com/security/) explains it. Each guide
renames the old key file aside, so it is kept, and the first start on the
`v1.13` line writes a new one.

**The enode ID changes with the key.** Anything that names the node by its enode
ID needs the new one: other nodes that list it as a static or trusted peer,
anyone else who peers with it deliberately, and monitoring or allowlists. Each
guide ends with the commands for the nodes.

**These trees follow by themselves.** The nightly crawl stops publishing the old
ID once it stops answering, and lists the new one once it finds it, if the node
is on its network's current fork and makes the tree's cap
([How nodes are chosen](node-selection.md)).

## A trial node first, if you are new to the v1.13 line

Before moving a node you depend on, you can set up one new node on the `v1.13`
line beside it, send it no traffic, and let it sync from the network. Do not
seed it with a copy of a `v1.12` node's data directory: the copy carries that
node's key. The trial node is optional and separate from the move itself, which
keeps the chain data in place.

## A config file that dumpconfig wrote on the v1.12 line

If the node starts with `--config` and its file came from `geth dumpconfig` on a
`v1.12` release, delete these three lines before the first start on the `v1.13`
line:

- `BootstrapNodes`
- `EthDiscoveryURLs`
- `SnapDiscoveryURLs`

The file holds that release's bootnodes and discovery trees, and the `v1.13`
line keeps them in place of its own, with no message. With the lines gone, it
uses the bootnodes it ships and the trees published here. `BootstrapNodesV5` can
stay, because the `v1.13` line replaces it.

A file written by `v1.12.17` or `v1.12.18`, two old releases that few nodes run,
also has `ECBP1100` and `ECBP1100Disable` lines. Delete those as well: a `v1.13`
release stops at the start on them, with a `Fatal` line that names the key.

## MESS

An upgrade can change whether the node runs MESS, which makes a node resist deep
chain reorganizations, so set it yourself: `--mess` turns it on and
`--mess=false` turns it off. Give every node you run the same setting.
[Which setting fits which operator](https://docs.coregeth.com/operate/mess/#which-setting-fits-which-operator)
sets out the choice. A `v1.12` binary refuses the flag, so take it out before
you roll back.

## RPC exposure

While the node is down, check the flags it starts with:

- `--http.addr` should be `127.0.0.1` unless a trusted proxy terminates in front
  of it.
- `admin`, `debug` and `personal` do not belong in `--http.api` on any reachable
  interface.
- `--http.corsdomain="*"` allows any origin. Name the origins you need.
- The same applies to `--ws.addr` and `--ws.api`.

## If a node cannot move yet

`--discovery.dns` points a `v1.12` node at the trees published here, the ones
the `v1.13` line reads by default, so it keeps finding peers after the trees it
reads by default stop being updated. It is a small step, and the node stays
vulnerable: the flag closes none of the flaws the audits found in `v1.12`.
[Using the trees](using-the-trees.md#core-geth-v112-line) gives the flag for each
network, the config-file form, and how to add it to a service or a container.
