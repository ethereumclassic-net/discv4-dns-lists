# Moving a v1.12 node on Linux

These steps move a node on Linux from any Core-Geth `v1.12` release to the
latest release of the `v1.13` line. The node keeps its data directory and its
chain data, and gets a new P2P node key.
[Moving a v1.12 node](../moving-from-v1-12.md) says why each step is there.

The commands use the default data directory, `~/.ethereum/classic`. For Mordor,
use `~/.ethereum/mordor`; if the node runs with `--datadir`, use that path.

## Before you start

With the node running, record what it is and where it is:

```bash
geth version
geth attach --exec 'eth.blockNumber'      ~/.ethereum/classic/geth.ipc
geth attach --exec 'admin.nodeInfo.enode' ~/.ethereum/classic/geth.ipc
```

Keep the last line's output. It is the node's enode ID, which step 4 changes.

If the node runs as a systemd service under its own user, as in Core-Geth's
[Linux run guide](https://docs.coregeth.com/getting-started/run/linux/#6-keep-it-running-a-systemd-service),
that user owns the data directory, `/var/lib/core-geth` there. Attach as that
user, here and in every later attach line:

```bash
sudo -u geth -H geth --classic attach --exec 'admin.nodeInfo.enode' /var/lib/core-geth/geth.ipc
```

## 1. Download the release and check it

The node can keep running for this step. To build from source instead, build
now, while the node runs, with [Building from source](#building-from-source): it
replaces this step's download and step 3's install.

```bash
VERSION=$(curl -sLo /dev/null -w '%{url_effective}' https://github.com/ethereumclassic/core-geth/releases/latest | sed 's|.*/||')
BASE=https://github.com/ethereumclassic/core-geth/releases/download/$VERSION
curl -LO $BASE/core-geth-linux-$VERSION.zip
curl -LO $BASE/core-geth-linux-$VERSION.zip.sha256
sha256sum -c core-geth-linux-$VERSION.zip.sha256
```

`sha256sum -c` must print `OK`. If it prints `FAILED`, delete the file and
download it again rather than running it.

On an ARM board, put the name for your processor where the file name says
`linux`, here and in step 3: `arm64` if `uname -m` prints `aarch64` or `arm64`,
`arm7` for `armv7l`, `arm6` for `armv6l`, and `arm5` for `armv5tel`.
[coregeth.com/downloads](https://coregeth.com/downloads/#upgrade) lists every
file the release carries.

On a node that holds value, also check where the file came from. This needs the
[GitHub CLI](https://cli.github.com/), signed in with `gh auth login`:

```bash
gh attestation verify core-geth-linux-$VERSION.zip --repo ethereumclassic/core-geth
```

It must print `Verification succeeded`. If it does not, do not run the file.

## 2. Stop the node cleanly

- **In a terminal:** press Ctrl-C once and wait. A second Ctrl-C does not speed
  it up.
- **Under systemd:** stop the unit, for example `sudo systemctl stop core-geth`.
  `journalctl -u core-geth` shows its log.

Wait until the log prints `Blockchain stopped` and the process exits.

## 3. Install the release

In the terminal you used for step 1, keep the old binary and install the new
one:

```bash
unzip -o core-geth-linux-$VERSION.zip &&
  { test -e /usr/local/bin/geth-v1.12 || sudo mv /usr/local/bin/geth /usr/local/bin/geth-v1.12; } &&
  sudo install -m 0755 geth /usr/local/bin/geth &&
  geth version
```

Each line runs only if the one before it worked. Go on only if the first line
`geth version` prints names a `1.13` release, such as `Core-Geth 1.13.0-stable`.
`geth-v1.12` is the old binary, kept so you can roll back.

The lines assume the old binary is `/usr/local/bin/geth`. `command -v geth`
shows where yours is, and a systemd unit names the binary it starts in its
`ExecStart` line. If it is elsewhere, use that path in all three places.

If you built from source in step 1, install that build as
[Building from source](#building-from-source) says instead.

## 4. Rotate the P2P node key

```bash
mv -n ~/.ethereum/classic/geth/nodekey ~/.ethereum/classic/geth/nodekey.old-rotated-$(date +%F)
```

For the systemd unit in the run guide, the key belongs to the service user:

```bash
sudo -u geth mv -n /var/lib/core-geth/geth/nodekey /var/lib/core-geth/geth/nodekey.old-rotated-$(date +%F)
```

The renamed file keeps the old key, and the next start writes a new one. If the
node starts with `--nodekey` or `--nodekeyhex`, or with `GETH_NODEKEY` or
`GETH_NODEKEYHEX` set, take that out too, because it overrides the file. If the
rename prints an error, check the data directory: `geth/nodekey` must not be
there when the node starts.

### If this node lists static peers

Static peers are listed under `[Node.P2P]` in the file passed with `--config`.
Edit it while the node is down:

```toml
[Node.P2P]
StaticNodes = ["enode://<node ID>@<IP>:30303"]
```

A peer that has already moved has a new ID, so use that. Separate entries with
commas. `TrustedNodes` takes the same form. With no file yet, save these two
lines and add `--config` and the file's path to the start command. The client
ignores `static-nodes.json`, so move its entries here.

## 5. Check the flags and the config file

While the node is down:

- **A config file from the `v1.12` line:** if `geth dumpconfig` wrote it, delete
  its `BootstrapNodes`, `EthDiscoveryURLs` and `SnapDiscoveryURLs` lines, or the
  node keeps the `v1.12` bootnodes and trees. A file written by `v1.12.17` or
  `v1.12.18` also has `ECBP1100` and `ECBP1100Disable` lines, which stop the new
  release at the start; delete those too.
- **MESS:** add `--mess` or `--mess=false`, the same on every node you run
  ([MESS](../moving-from-v1-12.md#mess)).
- **RPC exposure:** go through the four
  [RPC exposure](../moving-from-v1-12.md#rpc-exposure) checks.

## 6. Start the node and confirm the move

Start the node the way you always do, on the same data directory. Under systemd,
the reload picks up any flag you changed in the unit:

```bash
sudo systemctl daemon-reload && sudo systemctl start core-geth
```

Then:

```bash
geth attach --exec 'admin.nodeInfo.name'  ~/.ethereum/classic/geth.ipc
geth attach --exec 'admin.nodeInfo.enode' ~/.ethereum/classic/geth.ipc
geth attach --exec 'net.peerCount'        ~/.ethereum/classic/geth.ipc
geth attach --exec 'eth.blockNumber'      ~/.ethereum/classic/geth.ipc
```

If a line cannot connect, wait a minute and run it again.

- **The name** must be a `v1.13` release.
- **The enode ID** must differ from the one you recorded. If it is the same, the
  node is still on the old key: stop it and redo step 4.
- **The peer count** climbs within minutes. If it stays at zero, see
  [Why does the node have no peers?](https://docs.coregeth.com/operate/troubleshooting/#why-does-the-node-have-no-peers)
- **The block number** resumes where the node stopped, then catches up. If it
  settles somewhere else, stop and investigate rather than resync.

### Give the new ID to the nodes that list this one

They can no longer connect to this node, and neither side logs it at the default
verbosity. On each one, `v1.12` or `v1.13`, run these lines with the old ID
you recorded, the new one, and the address and port the entry already has:

```bash
geth attach --exec "admin.removePeer('enode://<old ID>@<IP>:30303')" ~/.ethereum/classic/geth.ipc
geth attach --exec "admin.addPeer('enode://<new ID>@<IP>:30303')" ~/.ethereum/classic/geth.ipc
geth attach --exec "admin.peers.map(function(p){return p.enode})" ~/.ethereum/classic/geth.ipc
```

The first two lines each print `true` and take effect with no restart. The third
lists the new ID once the nodes connect. The change lasts only until that node
restarts, so put the new ID in its config file too. For an entry in
`TrustedNodes`, use `admin.removeTrustedPeer` and `admin.addTrustedPeer`,
which do not open a connection.

## If you need to roll back

The data directory works with both releases, so rolling back swaps the binary.
Stop the node, take any `--mess` flag out of its start command, and under
systemd run `sudo systemctl daemon-reload`. Then put the old binary back and
start the node:

```bash
sudo mv /usr/local/bin/geth-v1.12 /usr/local/bin/geth
```

Keep the new key: rolling back does not make the old one safe.

## Building from source

Building needs Go 1.26 or later and a C compiler. Build `main`, where fixes and
dependency updates land through reviewed pull requests before they reach a
release:

```bash
git clone https://github.com/ethereumclassic/core-geth.git &&
  cd core-geth &&
  make geth &&
  ./build/bin/geth version
```

If a `core-geth` folder is already there, the clone stops on it: remove that
folder first.

`geth version` prints the version on its first line, such as
`Core-Geth 1.13.1-unstable`, where `unstable` marks a build that is not a
release. `main` keeps moving, so note the `Git Commit` line: it names the code
you built.

Do not clone with `--recursive`: the submodules are several gigabytes, and
`make geth` does not read them. At step 3, run these lines in that folder in
place of the ones there:

```bash
ls build/bin/geth &&
  { test -e /usr/local/bin/geth-v1.12 || sudo mv /usr/local/bin/geth /usr/local/bin/geth-v1.12; } &&
  sudo install -m 0755 build/bin/geth /usr/local/bin/geth &&
  geth version
```

Go on only if `geth version` reports `1.13` on its first line, ending in
`-unstable` for a build of `main`.
