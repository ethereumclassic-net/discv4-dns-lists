# Ethereum Classic DNS discovery lists

Signed lists of Ethereum Classic and Mordor nodes, published in DNS so that
clients find their first peers through
[EIP-1459](https://eips.ethereum.org/EIPS/eip-1459) discovery. The lists are
rebuilt every night from a crawl of the discv4 network, and every published list
is committed to this repository, so the record of what clients were given is
public. They are maintained in the
[`ethereumclassic`](https://github.com/ethereumclassic) organization by its core
developers and community contributors.

> [!IMPORTANT]
> **Move `v1.12` nodes to the `v1.13` line, which reads the
> community-maintained trees.** The Core-Geth `v1.12` line finds its first peers
> through the bootnodes built into it and the DNS trees published from
> [`etclabscore/discv4-dns-lists`](https://github.com/etclabscore/discv4-dns-lists),
> which the ETC Cooperative maintained. The Cooperative entered maintenance mode at
> the end of 2024. Its board has communicated that the Cooperative will dissolve
> and that those trees will stop being updated when it does. From
> then on they will serve an aging list of nodes until their domains lapse and
> they stop resolving. The trees published here take their place. The Core-Geth
> [`v1.13` line](https://github.com/ethereumclassic/core-geth/releases/latest), released
> from [`ethereumclassic/core-geth`](https://github.com/ethereumclassic/core-geth),
> reads them by default.
> [The ETC Cooperative transition](https://docs.coregeth.com/etc-cooperative-transition/)
> lists where the Cooperative's other services continue.
>
> Every node on the `v1.12` line should move to the `v1.13` line, which also
> closes the flaws [the audits](https://coregeth.com/security/) found in `v1.12`.
> The node keeps its chain data and gets a new P2P node key, which the move
> requires: one of those flaws leaks bits of the old key.
> [Moving a v1.12 node](docs/moving-from-v1-12.md) has the steps for Linux,
> macOS, Windows and Docker. A node that cannot move yet can switch to these trees
> and the `v1.13` line's bootnodes, a [small step](#quick-start) that closes none
> of those flaws.

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
All six are signed by one key, the text between `enrtree://` and `@`, and the
same URLs are compiled into the Core-Geth `v1.13` line. Each directory in this
repository holds one published tree and is named after the DNS name it serves.

## Quick start

**Core-Geth `v1.13` line:** nothing to configure unless the node starts from a
config file, or with a discovery flag added on the `v1.12` line. Both networks
read these trees by default. A file that names bootnodes or trees, as one
`geth dumpconfig` wrote on a `v1.12` release does, takes their place with no
message:
[delete those lines](docs/moving-from-v1-12.md#a-config-file-from-the-v112-line)
from it, and take out any `--discovery.dns` or `--bootnodes` added on the
`v1.12` line.

**Core-Geth `v1.12` line:** move the node to the `v1.13` line.
[Moving a v1.12 node](docs/moving-from-v1-12.md) has the steps, and
[coregeth.com/downloads](https://coregeth.com/downloads/#upgrade) lists the
release files and their checksums. Until the node can move, stop it cleanly and
add `--discovery.dns` with the three trees for its network to the command or
unit it already starts with, keeping its other flags:

```sh
geth --classic --discovery.dns "enrtree://APDLRZ2T7ERXPWXX4D5USB32NIFYHXMFVZQ3DZALK6JJJ5L4VSYIQ@all.classic.ethereumclassic.net,enrtree://APDLRZ2T7ERXPWXX4D5USB32NIFYHXMFVZQ3DZALK6JJJ5L4VSYIQ@all.classic.ethclassic.net,enrtree://APDLRZ2T7ERXPWXX4D5USB32NIFYHXMFVZQ3DZALK6JJJ5L4VSYIQ@all.classic.ethereumclassic.network"
```

Add `--bootnodes` to the same line, with the bootnodes the `v1.13` line ships:
[Keep a v1.12 node finding peers](https://coregeth.com/guides/discovery/#steps)
on coregeth.com gives the start line with both flags for each platform. A node
started from a config file that names trees needs them in place of the file's
own. [Using the trees](docs/using-the-trees.md#core-geth-v112-line) has that
form and the Mordor one.

## Documentation

| Page | What it covers |
|---|---|
| [Using the trees](docs/using-the-trees.md) | Pointing any Core-Geth release at these trees |
| [Moving a v1.12 node](docs/moving-from-v1-12.md) | Moving a node to the `v1.13` line on Linux, macOS, Windows or Docker, keeping its chain data |
| [Verifying a tree](docs/verifying-a-tree.md) | Checking what DNS serves against what this repository recorded |
| [DNS hosting and outages](docs/dns-outage.md) | What a DNS outage affects, and starting a node without the trees |
| [How nodes are chosen](docs/node-selection.md) | What gets a node listed, the current fork ID, and tree size |
| [How the lists are built](docs/pipeline.md) | The nightly pipeline, its safety checks, and running it by hand |
| [Why this repository exists](docs/history.md) | The ETC Cooperative transition and the predecessor trees |

## Status

Every scheduled run reports its result on one issue labeled
[`pipeline-status`](https://github.com/ethereumclassic/discv4-dns-lists/issues?q=label%3Apipeline-status),
along with whether each bootnode Core-Geth ships answered the night's crawl, the
size of each tree it built, and any warning the run raised.
Subscribe to it to be notified when a run fails, when it recovers, and when a
bootnode stops answering.

## Security

**To report a security issue privately**, email <security@ethereumclassic.net>.
[`SECURITY.md`](SECURITY.md) has the details. Security issues are never reported
as public issues.

## Support this work

These trees are a public good. The
[Ethereum Classic DAO](https://ethereumclassicdao.org) is the legal entity that
maintains them, together with Ethereum Classic's core developers and community
contributors, and today it also pays for that work, as its funder of last resort.
The repositories stay in the `ethereumclassic` organization no matter who
maintains or funds them. Earlier, this work moved between ETCDEV, ETC Labs and
the ETC Cooperative as each one closed or left. With the ETC Cooperative's
dissolution, Ethereum Classic stakeholders such as mining pools, exchanges and
service providers should use <security@ethereumclassic.net> as their point of
contact.

If you are a stakeholder of Ethereum Classic, you rely on this infrastructure,
and Ethereum Classic has no protocol-layer funding mechanism for its critical
infrastructure or its core developers. Please consider sponsoring it.
[Support this work](docs/support.md) lists who has funded it, explains how
sponsors are credited, and gives the routes: an invoiced maintenance agreement for
organizations, or a direct transfer to an address provided on request.

## License

MIT. See [LICENSE](LICENSE).
