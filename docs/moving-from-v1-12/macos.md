# Moving a v1.12 node on macOS

These steps move a node on macOS from any Core-Geth `v1.12` release to the
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

The node can keep running for this step. On Apple Silicon, where `uname -m`
prints `arm64`:

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
[coregeth.com/downloads](https://coregeth.com/downloads/#upgrade) lists every
file the release carries.

`curl` leaves no quarantine attribute on the file. If you download through a
browser instead, macOS refuses to run the unsigned binary until you clear it,
after step 3's unzip: `xattr -d com.apple.quarantine geth`.

On a node that holds value, also check where the file came from. This needs the
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

Wait until the log prints `Blockchain stopped` and the process exits.

## 3. Install the release

In the terminal you used for step 1, keep the old binary and install the new
one:

```bash
unzip -o core-geth-osx-arm64-$VERSION.zip &&
  { test -e /usr/local/bin/geth-v1.12 || sudo mv /usr/local/bin/geth /usr/local/bin/geth-v1.12; } &&
  sudo install -m 0755 geth /usr/local/bin/geth &&
  geth version
```

Each line runs only if the one before it worked. Go on only if the first line
`geth version` prints names a `1.13` release, such as `Core-Geth 1.13.0-stable`.
`geth-v1.12` is the old binary, kept so you can roll back.

The lines assume the old binary is `/usr/local/bin/geth`. `command -v geth`
shows where yours is, and a launchd agent names the binary it starts in its
plist. If it is elsewhere, use that path in all three places.

To build the release from source instead, see
[Building from source](#building-from-source).

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

- **A config file from the `v1.12` line:** if `geth dumpconfig` wrote it, delete
  its `BootstrapNodes`, `EthDiscoveryURLs` and `SnapDiscoveryURLs` lines, or the
  node keeps the `v1.12` bootnodes and trees. A file written by `v1.12.17` or
  `v1.12.18` also has `ECBP1100` and `ECBP1100Disable` lines, which stop the new
  release at the start; delete those too.
- **MESS:** add `--mess` or `--mess=false`, the same on every node you run
  ([MESS](../moving-from-v1-12.md#mess)). For a launchd agent, the flags are in
  its plist.
- **RPC exposure:** go through the four
  [RPC exposure](../moving-from-v1-12.md#rpc-exposure) checks.

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
geth attach --exec "admin.removePeer('enode://<old ID>@<IP>:30303')" ~/Library/Ethereum/classic/geth.ipc
geth attach --exec "admin.addPeer('enode://<new ID>@<IP>:30303')" ~/Library/Ethereum/classic/geth.ipc
geth attach --exec "admin.peers.map(function(p){return p.enode})" ~/Library/Ethereum/classic/geth.ipc
```

The first two lines each print `true` and take effect with no restart. The third
lists the new ID once the nodes connect. The change lasts only until that node
restarts, so put the new ID in its config file too. For an entry in
`TrustedNodes`, use `admin.removeTrustedPeer` and `admin.addTrustedPeer`,
which do not open a connection.

## If you need to roll back

The data directory works with both releases, so rolling back swaps the binary.
Stop the node and take any `--mess` flag out of its start command. Then put the
old binary back and start the node:

```bash
sudo mv /usr/local/bin/geth-v1.12 /usr/local/bin/geth
```

Keep the new key: rolling back does not make the old one safe.

## Building from source

Building needs Go 1.26 or later and the Xcode Command Line Tools
(`xcode-select --install`). Build the latest release's tag rather than `main`,
which keeps moving:

```bash
VERSION=$(curl -sLo /dev/null -w '%{url_effective}' https://github.com/ethereumclassic/core-geth/releases/latest | sed 's|.*/||')
git clone --branch $VERSION --single-branch https://github.com/ethereumclassic/core-geth.git core-geth-$VERSION &&
  cd core-geth-$VERSION &&
  make geth &&
  ./build/bin/geth version
```

Do not clone with `--recursive`: the submodules are several gigabytes, and
`make geth` does not read them. Then, in that folder, use this in place of
step 3:

```bash
ls build/bin/geth &&
  { test -e /usr/local/bin/geth-v1.12 || sudo mv /usr/local/bin/geth /usr/local/bin/geth-v1.12; } &&
  sudo install -m 0755 build/bin/geth /usr/local/bin/geth &&
  geth version
```
