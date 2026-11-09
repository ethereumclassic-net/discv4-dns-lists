# Moving a v1.12 node

This page is for a node on the Core-Geth `v1.12` line. Every such node should
move to the [`v1.13`](https://github.com/ethereumclassic/core-geth/releases/latest)
line, which reads the trees this repository publishes by default and closes the
flaws [the audits](https://coregeth.com/security/) found in `v1.12`. A node that
cannot move yet can [switch to these trees and the `v1.13` line's bootnodes](#if-a-node-cannot-move-yet),
a small step that closes none of those flaws.

The steps are for `v1.12.17` and later. A release before `v1.12.17` does not
schedule the Spiral upgrade, so a node on one left Ethereum Classic at block
19,250,000 and cannot move in place. Remove its chain database as
[Resync from scratch](https://docs.coregeth.com/operate/maintenance/#resync-from-scratch)
shows, which keeps the node's P2P node key. Then install the `v1.13` release and
rename that key as your platform's guide does, and start the node, which syncs
the chain again.

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
the move, and delete the `v1.12` binary or container once the node is stable.
Each guide also says how to roll back while you find what went wrong.
[coregeth.com/downloads](https://coregeth.com/downloads/#upgrade) lists every
file a release carries, with its checksum.

## What the move keeps, and what it changes

**From `v1.12.17` on, the chain data stays where it is.** The `v1.12` and
`v1.13` lines use the same data directory for each network, so the new release
opens the chain the old one wrote, and nothing resyncs: only a container that
keeps its data inside itself needs a copy. The node is down from the clean stop
until it has caught up after the start: while you install the release, rename
the key and check its flags and config file, and while it then catches up on the
blocks it missed. Point RPC clients and miners back at it only then. The steps
take about twenty minutes; a build from source, or a copy of a container's data,
takes longer. The account keystore is not touched.

**The P2P node key changes, and that is required.** One of the flaws in
`v1.12`, CVE-2026-26315, leaks bits of the node key across repeated handshakes,
and no fix can take back what has already leaked.
[coregeth.com/security](https://coregeth.com/security/) explains it. Each guide
renames the old key file aside, so it is kept, and the first start on the
`v1.13` line writes a new one.

**The enode ID changes with the key.** Anything that names the node by its enode
ID needs the new one: other nodes that list it as a static or trusted peer,
anyone else who peers with it deliberately, and monitoring or allowlists. Step 6
of each guide, step 5 in Docker, ends with the commands to run on those nodes.

**These trees follow by themselves.** The nightly crawl stops publishing the old
ID once it stops answering, and lists the new one once it finds it, if the node
is on its network's current fork and makes the tree's cap
([How nodes are chosen](node-selection.md)).

## A trial node first, if you are new to the v1.13 line

Before moving a node you depend on, you can set up one new node on the `v1.13`
line, on another machine. Let it peer and sync from the network like any node,
or start it from a copy of a stopped `v1.12` node's data directory without its
`geth/nodekey`, which holds the exposed P2P node key. Point no RPC clients or
miners at it. The trial is done when the new node has caught up to the chain
head and holds peers. It is optional and separate from the move itself, which
keeps the chain data in place.

## A config file from the v1.12 line

If the node starts with `--config`, open the file before the first start on the
`v1.13` line and look for these three lines, whoever wrote it:

- `BootstrapNodes`
- `EthDiscoveryURLs`
- `SnapDiscoveryURLs`

`geth dumpconfig` on the `v1.12` line writes all three, holding that release's
bootnodes and discovery trees, and the `v1.13` line uses them in place of its
own, with no message. Delete each one unless you put it there yourself to name
bootnodes or trees other than the release's own. With the lines gone, the node
uses the bootnodes it ships and the trees published here. `BootstrapNodesV5` can
stay: the `v1.13` line puts its own discovery v5 bootnodes in place of the ones
a `v1.12` file holds.

`v1.12.17` and `v1.12.18`, two old releases that few nodes run, accept
`ECBP1100` and `ECBP1100Disable` in a config file. A `v1.13` release stops at
the start on either key, with a `Fatal` line that names it, so delete those
lines too. If one holds a block number, the file was setting MESS: decide its
setting with `--mess` or `--mess=false`, the same as your other nodes
([MESS](#mess)).

To see what the node will use, run the new `geth` as the user the node runs as,
with the node's flags and `dumpconfig` at the end, while the node is stopped. It
writes the node's new key file if there is none, which is why it has to be that
user. The `EthDiscoveryURLs` and `SnapDiscoveryURLs` it prints should each list
the three trees for the node's network in
[Using the trees](using-the-trees.md#the-trees).

## MESS

An upgrade can change whether the node runs MESS, which makes a node resist deep
chain reorganizations, so set it yourself: `--mess` turns it on and
`--mess=false` turns it off. Give every node you run the same setting.
[Which setting fits which operator](https://docs.coregeth.com/operate/mess/#which-setting-fits-which-operator)
sets out the choice. A `v1.12` binary refuses the flag, so take it out before
you roll back.

## RPC exposure

While the node is down, check how it serves RPC: in its flags, in any `GETH_`
variables it starts with, and, if it starts with `--config`, in the file's
`[Node]` section, where `HTTPHost`, `HTTPModules`, `HTTPCors`, `WSHost`,
`WSModules` and `WSOrigins` hold the same settings.

- `--http.addr` should be `127.0.0.1` unless a trusted proxy terminates in front
  of it. On Docker's default bridge network it stays `0.0.0.0`, so the published
  port can reach the node, and publishing that port on `127.0.0.1` keeps RPC off
  other machines. A container run with `--network host` publishes no ports, so
  there `--http.addr` must be `127.0.0.1`, as on a host.
- `admin`, `debug` and `personal` belong only on IPC or on `127.0.0.1`: never in
  `--http.api` or `--ws.api` on an address another machine can reach, a private
  network included. In a container, keep them off HTTP and WebSocket altogether
  and reach them over IPC with `docker exec`: other containers on its network
  can reach its `0.0.0.0`.
- `--http.corsdomain="*"` allows any origin. Name the origins you need.
- The same checks apply to WebSocket: `--ws.addr`, `--ws.api`, and
  `--ws.origins` in place of `--http.corsdomain`.

## If a node cannot move yet

`--discovery.dns` points a `v1.12` node at the trees published here, the ones
the `v1.13` line reads by default, so it keeps finding peers after the trees it
reads by default stop being updated, and `--bootnodes` points it at the
bootnodes the `v1.13` line ships. Both are a small step, and the node stays
vulnerable: they close none of the flaws the audits found in `v1.12`.
`--discovery.dns` sets only `EthDiscoveryURLs`, so a node started from a config
file that names trees needs them replaced in the file as well.
[Using the trees](using-the-trees.md#core-geth-v112-line) gives the trees for
each network, the config-file form, and how to add the flags to a service or a
container.
[Keep a v1.12 node finding peers](https://coregeth.com/guides/discovery/) on
coregeth.com has the steps for each platform with both flags.
