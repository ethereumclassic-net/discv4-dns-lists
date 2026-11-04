# Using the trees

This page lists the six discovery trees this repository publishes and shows how
to point a Core-Geth node at them.

## The trees

```
enrtree://APDLRZ2T7ERXPWXX4D5USB32NIFYHXMFVZQ3DZALK6JJJ5L4VSYIQ@all.classic.ethereumclassic.net
enrtree://APDLRZ2T7ERXPWXX4D5USB32NIFYHXMFVZQ3DZALK6JJJ5L4VSYIQ@all.classic.ethclassic.net
enrtree://APDLRZ2T7ERXPWXX4D5USB32NIFYHXMFVZQ3DZALK6JJJ5L4VSYIQ@all.classic.ethereumclassic.network
enrtree://APDLRZ2T7ERXPWXX4D5USB32NIFYHXMFVZQ3DZALK6JJJ5L4VSYIQ@all.mordor.ethereumclassic.net
enrtree://APDLRZ2T7ERXPWXX4D5USB32NIFYHXMFVZQ3DZALK6JJJ5L4VSYIQ@all.mordor.ethclassic.net
enrtree://APDLRZ2T7ERXPWXX4D5USB32NIFYHXMFVZQ3DZALK6JJJ5L4VSYIQ@all.mordor.ethereumclassic.network
```

`all.classic.` is Ethereum Classic and `all.mordor.` is its Mordor test network.
Each network's list is published under three domain names, and all six trees are
signed by one key, the text between `enrtree://` and `@`.

The same six URLs are compiled into Core-Geth, in
[`params/bootnodes_classic.go`](https://github.com/ethereumclassic/core-geth/blob/main/params/bootnodes_classic.go)
and
[`params/bootnodes_mordor.go`](https://github.com/ethereumclassic/core-geth/blob/main/params/bootnodes_mordor.go),
and each tree's directory in this repository records the one it serves in its
`enrtree-info.json`, so any copy of a URL can be checked against the others.

## Core-Geth v1.13 line

There is nothing to configure. Both networks read their three trees by default,
in every sync mode. Releases are published at
[`ethereumclassic/core-geth`](https://github.com/ethereumclassic/core-geth/releases/latest),
and [coregeth.com/downloads](https://coregeth.com/downloads/#install) lists every
file a release carries, with its checksum.

A config file that `geth dumpconfig` wrote on a `v1.12` release holds that
release's bootnodes and trees, and the `v1.13` line uses them in place of its
own, with no message.
[Moving a v1.12 node](moving-from-v1-12.md#a-config-file-that-dumpconfig-wrote-on-the-v112-line)
says which lines to delete.

## Core-Geth v1.12 line

Move the node to the `v1.13` line, which reads these trees by default and closes
the flaws [the audits](https://coregeth.com/security/) found in `v1.12`.
[Moving a v1.12 node](moving-from-v1-12.md) has the steps for each platform.

Until a node can move, `--discovery.dns` points it at these trees. Every `v1.12`
release has it, and so does any build of that code. The flag is a small step,
and the node stays vulnerable: it closes none of those flaws. Stop the node
cleanly, as step 2 of each [platform guide](moving-from-v1-12.md#choose-your-guide)
shows, then add the flag to the command or unit you start it with:

```sh
geth --classic --discovery.dns "enrtree://APDLRZ2T7ERXPWXX4D5USB32NIFYHXMFVZQ3DZALK6JJJ5L4VSYIQ@all.classic.ethereumclassic.net,enrtree://APDLRZ2T7ERXPWXX4D5USB32NIFYHXMFVZQ3DZALK6JJJ5L4VSYIQ@all.classic.ethclassic.net,enrtree://APDLRZ2T7ERXPWXX4D5USB32NIFYHXMFVZQ3DZALK6JJJ5L4VSYIQ@all.classic.ethereumclassic.network"
```

Keep the node's other flags: a node on `--datadir` that runs this line as it
stands starts an empty chain in the default directory. For Mordor, use
`--mordor` and the three `all.mordor.` URLs. On Windows, run
`.\geth.exe` in place of `geth`. Under systemd, add the flag to the unit's
`ExecStart` line and run `sudo systemctl daemon-reload` before you start it. A
container cannot take a new flag: stop it with `docker stop -t 300` and replace
it, on the same data, with one that has the flag after the image name.
[Step 5 of the Docker guide](moving-from-v1-12/docker.md#5-replace-the-container-and-confirm-the-move)
shows the commands.

If the node starts from a config file that names discovery trees, as a file
`geth dumpconfig` wrote does, put these trees in the file instead, under `[Eth]`
in both lists, with the `all.mordor.` URLs for Mordor:

```toml
[Eth]
EthDiscoveryURLs = [
  "enrtree://APDLRZ2T7ERXPWXX4D5USB32NIFYHXMFVZQ3DZALK6JJJ5L4VSYIQ@all.classic.ethereumclassic.net",
  "enrtree://APDLRZ2T7ERXPWXX4D5USB32NIFYHXMFVZQ3DZALK6JJJ5L4VSYIQ@all.classic.ethclassic.net",
  "enrtree://APDLRZ2T7ERXPWXX4D5USB32NIFYHXMFVZQ3DZALK6JJJ5L4VSYIQ@all.classic.ethereumclassic.network",
]
SnapDiscoveryURLs = [
  "enrtree://APDLRZ2T7ERXPWXX4D5USB32NIFYHXMFVZQ3DZALK6JJJ5L4VSYIQ@all.classic.ethereumclassic.net",
  "enrtree://APDLRZ2T7ERXPWXX4D5USB32NIFYHXMFVZQ3DZALK6JJJ5L4VSYIQ@all.classic.ethclassic.net",
  "enrtree://APDLRZ2T7ERXPWXX4D5USB32NIFYHXMFVZQ3DZALK6JJJ5L4VSYIQ@all.classic.ethereumclassic.network",
]
```

The flag replaces only `EthDiscoveryURLs`, so with the flag alone such a node
keeps finding snap peers through the `v1.12` trees left in `SnapDiscoveryURLs`.

The list replaces the tree built into the release instead of adding to it. The
node needs no working bootnode to use it, because it dials the nodes in a tree
directly. To start from the `v1.13` line's bootnodes as well, pass them with
`--bootnodes`, which likewise replaces the built-in list; their addresses are in
the two `params` files linked above.

## If the trees do not resolve

[DNS hosting and outages](dns-outage.md#if-the-trees-stop-resolving) shows how to
start a node from the node records committed in this repository instead.
