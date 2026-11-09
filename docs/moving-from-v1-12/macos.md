# Moving a v1.12 node on macOS

These steps move a node on macOS from Core-Geth `v1.12.17` or later to the
latest release of the `v1.13` line. The node keeps its data directory and its
chain data, and gets a new P2P node key.
[Moving a v1.12 node](../moving-from-v1-12.md) says why each step is there.

The commands use the default data directory on macOS,
`~/Library/Ethereum/classic`. For Mordor, use `~/Library/Ethereum/mordor`; if
the node runs with `--datadir`, use that path.

## Before you start

With the node running, record what it is and where it is:

```bash
geth version
geth attach --exec 'eth.blockNumber'      ~/Library/Ethereum/classic/geth.ipc
geth attach --exec 'admin.nodeInfo.enode' ~/Library/Ethereum/classic/geth.ipc
```

Keep the last line's output. It is the node's enode ID, which step 4 changes.

## 1. Download the release and check it

The node can keep running for this step. To build from source instead, build
now, while the node runs, with [Building from source](#building-from-source): it
replaces this step's download and step 3's install. On Apple Silicon,
where `uname -m` prints `arm64`:

```bash
VERSION=$(curl -sLo /dev/null -w '%{url_effective}' https://github.com/ethereumclassic/core-geth/releases/latest | sed 's|.*/||')
BASE=https://github.com/ethereumclassic/core-geth/releases/download/$VERSION
curl -LO $BASE/core-geth-osx-arm64-$VERSION.zip
curl -LO $BASE/core-geth-osx-arm64-$VERSION.zip.sha256
shasum -a 256 -c core-geth-osx-arm64-$VERSION.zip.sha256
```

On an Intel Mac, where it prints `x86_64`, put `osx` where the file name says
`osx-arm64`, here and in step 3. `shasum -a 256 -c` must print `OK`. If it
prints `FAILED`, delete the file and download it again rather than running it.
[coregeth.com/downloads](https://coregeth.com/downloads/) lists every
file the release carries.

`curl` leaves no quarantine attribute on the file. If you download through a
browser instead, macOS refuses to run the unsigned binary until you clear it,
after step 3's unzip: `xattr -d com.apple.quarantine geth`.

Then check where the file came from. It matters most on a node that holds
account keys or that an exchange, pool or service relies on. This needs the
[GitHub CLI](https://cli.github.com/), signed in with `gh auth login`:

```bash
gh attestation verify core-geth-osx-arm64-$VERSION.zip --repo ethereumclassic/core-geth
```

It must print `Verification succeeded`. If it does not, do not run the file.

## 2. Stop the node cleanly

- **In a terminal:** press Ctrl-C once and wait. A second Ctrl-C does not speed
  it up.
- **As a launchd agent:** unload it. For the agent in Core-Geth's
  [macOS run guide](https://docs.coregeth.com/getting-started/run/macos/#7-stop-it-cleanly),
  with `NETWORK` set to `classic` or `mordor`:

  ```bash
  launchctl bootout gui/$(id -u)/com.coregeth.$NETWORK
  ```

Wait until the log prints `Blockchain stopped` and the process exits. If the
process exits without that line, the stop was not clean, for example because a
service manager's stop timeout ended it. You can go on: the node recovers at its
next start, and its block number may start below the one you recorded.

## 3. Install the release

In the terminal you used for step 1, keep the old binary and install the new
one:

```bash
unzip -o core-geth-osx-arm64-$VERSION.zip &&
  { test -e /usr/local/bin/geth-v1.12 || sudo mv /usr/local/bin/geth /usr/local/bin/geth-v1.12; } &&
  sudo install -m 0755 geth /usr/local/bin/geth &&
  geth version
```

Each line runs only if the one before it worked. Go on only if `geth version`
reports `1.13` on its first line: `Core-Geth 1.13.0-stable` for a release, or a
version ending in `-unstable` for a build of `main`.
`geth-v1.12` is the old binary, kept so you can roll back.

The lines assume the old binary is `/usr/local/bin/geth`. `command -v geth`
shows where yours is, and a launchd agent names the binary it starts in its
plist. If it is elsewhere, put its folder in place of `/usr/local/bin`
everywhere in the block, and end with `<folder>/geth version`: a bare
`geth version` runs whichever `geth` comes first on `PATH`. Use the same folder
in the rollback and cleanup lines and in the install lines of
[Building from source](#building-from-source).

If you built from source in step 1, install that build as
[Building from source](#building-from-source) says instead.

## 4. Rotate the P2P node key

```bash
mv -n ~/Library/Ethereum/classic/geth/nodekey ~/Library/Ethereum/classic/geth/nodekey.old-rotated-$(date +%F)
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

- **A config file:** if the node starts with `--config`, open the file and
  delete any `BootstrapNodes`, `EthDiscoveryURLs` and `SnapDiscoveryURLs` lines,
  unless you put them there yourself to name bootnodes or trees other than the
  release's own: the values `geth dumpconfig` writes are the `v1.12` release's,
  and the new release keeps them with no message. A file a `v1.12.17` or
  `v1.12.18` node starts from can also set `ECBP1100` or `ECBP1100Disable`,
  which stop the new release at the start: delete those lines, and if one holds
  a block number, the file was setting MESS, so decide its setting under
  **MESS** below. To check, run `geth` as the user the node runs as, with the
  node's flags and `dumpconfig` at the end: the `EthDiscoveryURLs` and
  `SnapDiscoveryURLs` it prints should each list the three trees for the node's
  network in [Using the trees](../using-the-trees.md#the-trees). It writes the
  new node key file if there is none, which is why it has to be that user.
- **Discovery flags:** take out any `--discovery.dns` or `--bootnodes` you added
  on the `v1.12` line. The `v1.13` line has both built in; `--bootnodes` would
  hold the node to the nodes it names, and `--discovery.dns` would leave its
  snap list empty.
- **MESS:** add `--mess` or `--mess=false`, the same on every node you run
  ([MESS](../moving-from-v1-12.md#mess)). For a launchd agent, the flags are in
  its plist.
- **RPC exposure:** go through the four
  [RPC exposure](../moving-from-v1-12.md#rpc-exposure) checks, in the flags, any
  `GETH_` variables and the config file.

## 6. Start the node and confirm the move

Start the node the way you always do, on the same data directory. For the
agent in the run guide:

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.coregeth.$NETWORK.plist
```

Then:

```bash
geth attach --exec 'admin.nodeInfo.name'  ~/Library/Ethereum/classic/geth.ipc
geth attach --exec 'admin.nodeInfo.enode' ~/Library/Ethereum/classic/geth.ipc
geth attach --exec 'net.peerCount'        ~/Library/Ethereum/classic/geth.ipc
geth attach --exec 'eth.blockNumber'      ~/Library/Ethereum/classic/geth.ipc
```

If a line cannot connect, wait a minute and run it again.

- **The name** must show `v1.13`: `-stable` for a release, or `-unstable` for a
  build of `main`.
- **The enode ID** must differ from the one you recorded. If it is the same, the
  node is still on the old key: stop it and redo step 4.
- **The peer count** climbs within minutes. If it stays at zero, see
  [Why does the node have no peers?](https://docs.coregeth.com/operate/troubleshooting/#why-does-the-node-have-no-peers)
- **The block number** starts at or above the one you recorded, because the node
  kept syncing until you stopped it, or below it after an unclean stop. Then it
  climbs. Compare it with a block explorer or another node you run: it should
  reach the chain head and follow it. If it stops climbing short of the head,
  stop and investigate rather than resync.

These checks do not show which trees the node reads: the `dumpconfig` check in
step 5 does.

### Give the new ID to the nodes that list this one

They can no longer connect to this node, and neither side logs it at the default
verbosity. On each one, `v1.12` or `v1.13`, run these lines with the old ID
you recorded, the new one, and the address and port the entry already has:

```bash
geth attach --exec "admin.removePeer('enode://<old ID>@<IP>:30303')" ~/Library/Ethereum/classic/geth.ipc
geth attach --exec "admin.addPeer('enode://<new ID>@<IP>:30303')" ~/Library/Ethereum/classic/geth.ipc
geth attach --exec "admin.peers.map(function(p){return p.enode})" ~/Library/Ethereum/classic/geth.ipc
```

The first two lines each print `true` and take effect with no restart. The third
lists the new ID once the nodes connect. The change lasts only until that node
restarts, so put the new ID in that node's own config file too, in the entry
that names this one. For an entry in `TrustedNodes`, run
`admin.removeTrustedPeer` and `admin.addTrustedPeer` the same way: in place of
the first two lines if the entry is only in `TrustedNodes`, and as well as them
if it is in both. They open no connection, so for an entry only in
`TrustedNodes` the third line shows the new ID only once this node connects.

## If you need to roll back

Roll back only for as long as it takes to find what went wrong: every `v1.12`
release carries the flaws the audits found. The data directory works with both
releases, so rolling back swaps the binary. Stop the node and take any `--mess`
flag out of its start command. Then put the old binary back and start the node:

```bash
sudo mv /usr/local/bin/geth-v1.12 /usr/local/bin/geth
```

Keep the new key: rolling back does not make the old one safe, and a release
before `v1.12.21` leaks the new key as it did the old one. Once the cause is
fixed, move to the `v1.13` line again with these steps, rotating the key again
in step 4. A second rename on the same day finds its target name taken, so add
`-2` after `$(date +%F)` in it. If the node has to stay on `v1.12` longer, point
it at this repository's trees and the `v1.13` line's bootnodes, as
[Using the trees](../using-the-trees.md#core-geth-v112-line) shows.

## Once the node is stable, delete the v1.12 binary

Once the node has caught up, holds peers, and has run on the `v1.13` line long
enough that you will not roll back:

```bash
sudo rm /usr/local/bin/geth-v1.12
```

Every `v1.12` release carries the flaws the audits found, so a copy left on the
machine is one a later mistake can start.

## Building from source

Building needs Go 1.26 or later and the Xcode Command Line Tools
(`xcode-select --install`). Build `main`, where fixes and dependency updates
land through reviewed pull requests before they reach a release:

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
