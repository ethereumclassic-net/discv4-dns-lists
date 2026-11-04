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
Each network's node set is published as three trees, one under each domain name,
and all six are signed by one key, the text between `enrtree://` and `@`.

The same six URLs are compiled into the Core-Geth `v1.13` line, in
[`params/bootnodes_classic.go`](https://github.com/ethereumclassic/core-geth/blob/main/params/bootnodes_classic.go)
and
[`params/bootnodes_mordor.go`](https://github.com/ethereumclassic/core-geth/blob/main/params/bootnodes_mordor.go),
and each tree's directory in this repository records the one it serves in its
`enrtree-info.json`, so any copy of a URL can be checked against the others.

## Core-Geth v1.13 line

There is nothing to configure unless the node starts from a config file, or with
a discovery flag added on the `v1.12` line. Both networks read their three trees
by default, in every sync mode. Releases are published at
[`ethereumclassic/core-geth`](https://github.com/ethereumclassic/core-geth/releases/latest),
and [coregeth.com/downloads](https://coregeth.com/downloads/#install) lists every
file a release carries, with its checksum.

A config file that names bootnodes or trees, as one `geth dumpconfig` wrote on a
`v1.12` release does, takes their place, with no message.
[Moving a v1.12 node](moving-from-v1-12.md#a-config-file-from-the-v112-line)
says which lines to delete and how to check. A `--discovery.dns` or
`--bootnodes` flag added on the `v1.12` line also holds the node to what it
names: take it out.

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
container cannot take a new flag. Stop it with `docker stop -t 300`, then
replace it with a new container from the same `v1.12` image, on the same data,
with its other flags and `--discovery.dns` after the image name;
`docker inspect <container> --format '{{.Config.Image}}'` prints that image.
First check where it keeps its data, as
[Before you start](moving-from-v1-12/docker.md#before-you-start) in the Docker
guide shows: a container that keeps it inside itself loses it to the
replacement.
[Step 5 of the Docker guide](moving-from-v1-12/docker.md#5-replace-the-container-and-confirm-the-move)
shows the rename and the `docker run`: put that image in place of `$IMAGE`, and
leave out `--mess`, which a `v1.12` binary refuses.

If the node starts from a config file that names discovery trees, as a file
`geth dumpconfig` wrote does, put these trees in place of the values of its
`EthDiscoveryURLs` and `SnapDiscoveryURLs` lines, under `[Eth]`, with the
`all.mordor.` URLs for Mordor:

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

The trees you give replace the release's built-in trees instead of adding to
them. The node needs no working bootnode to use them, because it dials the nodes
in a tree directly. To start from the `v1.13` line's bootnodes as well, pass
them with `--bootnodes`, which likewise replaces the built-in list; their
addresses are in that network's `params` file linked above.

## If the trees do not resolve

[DNS hosting and outages](dns-outage.md#if-the-trees-stop-resolving) shows how to
start a node from the node records committed in this repository instead.
