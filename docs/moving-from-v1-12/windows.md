# Moving a v1.12 node on Windows

These steps move a node on Windows from Core-Geth `v1.12.17` or later to the
latest release of the `v1.13` line. The node keeps its data directory and its
chain data, and gets a new P2P node key.
[Moving a v1.12 node](../moving-from-v1-12.md) says why each step is there.

The commands are for PowerShell, run from the folder that holds `geth.exe`. They
use the default data directory, `%LOCALAPPDATA%\Ethereum\classic`. The node uses
`%USERPROFILE%\AppData\Roaming\Ethereum\classic` instead if an older
`AppData\Roaming\Ethereum` folder exists and is not empty. For Mordor, use
`mordor` in place of `classic`; if the node runs with `--datadir`, use that
path. `geth attach` reaches the node on a named pipe, `\\.\pipe\geth.ipc`.

## Before you start

With the node running, record what it is and where it is:

```powershell
.\geth.exe version
.\geth.exe attach --exec 'eth.blockNumber'      \\.\pipe\geth.ipc
.\geth.exe attach --exec 'admin.nodeInfo.enode' \\.\pipe\geth.ipc
```

Keep the last line's output. It is the node's enode ID, which step 4 changes.

## 1. Download the release and check it

The node can keep running for this step. To build from source instead, build
now, while the node runs, with [Building from source](#building-from-source): it
replaces this step's download and step 3's install.

```powershell
$VERSION = (Invoke-RestMethod "https://api.github.com/repos/ethereumclassic/core-geth/releases/latest").tag_name
$BASE = "https://github.com/ethereumclassic/core-geth/releases/download/$VERSION"
Invoke-WebRequest "$BASE/core-geth-win64-$VERSION.zip" -OutFile "core-geth-win64-$VERSION.zip"
Invoke-WebRequest "$BASE/core-geth-win64-$VERSION.zip.sha256" -OutFile "core-geth-win64-$VERSION.zip.sha256"
(Get-FileHash "core-geth-win64-$VERSION.zip" -Algorithm SHA256).Hash
Get-Content "core-geth-win64-$VERSION.zip.sha256"
```

The last two lines of output are the file's hash, then the published hash
followed by the file name. The 64 characters before the file name must match the
file's hash; case does not matter. If they differ, delete the file and download
it again rather than running it.
[coregeth.com/downloads](https://coregeth.com/downloads/#upgrade)
lists every file the release carries.

Then check where the file came from. It matters most on a node that holds
account keys or that an exchange, pool or service relies on. This needs the
[GitHub CLI](https://cli.github.com/), signed in with `gh auth login`:

```powershell
gh attestation verify "core-geth-win64-$VERSION.zip" --repo ethereumclassic/core-geth
```

It must print `Verification succeeded`. If it does not, do not run the file.

## 2. Stop the node cleanly

- **In a console window:** press Ctrl+C once and wait. A window opened from the
  Startup folder then asks `Terminate batch job (Y/N)?`; type `Y`.
- **Under a service wrapper:** stop it with that tool.

Wait until the log prints `Blockchain stopped` and the process exits. If the
process exits without that line, the stop was not clean, for example because a
service manager's stop timeout ended it. You can go on: the node recovers at its
next start, and its block number may start below the one you recorded.

## 3. Install the release

In the window you used for step 1, keep the old binary and unpack the new one in
its place:

```powershell
Rename-Item .\geth.exe geth-v1.12.exe
Expand-Archive "core-geth-win64-$VERSION.zip" -DestinationPath . -Force
.\geth.exe version
```

Go on only if `.\geth.exe version` reports `1.13` on its first line:
`Core-Geth 1.13.0-stable` for a release, or a version ending in `-unstable` for
a build of `main`. `geth-v1.12.exe` is the old binary, kept so you can roll
back.

If you built from source in step 1, install that build as
[Building from source](#building-from-source) says instead.

## 4. Rotate the P2P node key

```powershell
$key = "$env:LOCALAPPDATA\Ethereum\classic\geth\nodekey"
Rename-Item $key "nodekey.old-rotated-$(Get-Date -Format yyyy-MM-dd)"
```

If the node uses the `AppData\Roaming` folder, put `$env:APPDATA` in place of
`$env:LOCALAPPDATA`. The renamed file keeps the old key, and the next start
writes a new one. If the node starts with `--nodekey` or `--nodekeyhex`, or with
`GETH_NODEKEY` or `GETH_NODEKEYHEX` set, take that out too, because it overrides
the file. If the rename prints an error, check the data directory:
`geth\nodekey` must not be there when the node starts.

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

Whenever you edit the config file, here or in step 5, save it as UTF-8 with no
byte order mark. A byte order mark, or UTF-16, stops the start with
`invalid TOML syntax`.

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
  **MESS** below. To check, run `.\geth.exe` as the user the node runs as, with
  the node's flags and `dumpconfig` at the end: the `EthDiscoveryURLs` and
  `SnapDiscoveryURLs` it prints should each list the three trees for the node's
  network in [Using the trees](../using-the-trees.md#the-trees). It writes the
  new node key file if there is none, which is why it has to be that user.
- **Discovery flags:** take out any `--discovery.dns` or `--bootnodes` you added
  on the `v1.12` line. The `v1.13` line has both built in; `--bootnodes` would
  hold the node to the nodes it names, and `--discovery.dns` would leave its
  snap list empty.
- **MESS:** add `--mess` or `--mess=false`, the same on every node you run
  ([MESS](../moving-from-v1-12.md#mess)).
- **RPC exposure:** go through the four
  [RPC exposure](../moving-from-v1-12.md#rpc-exposure) checks, in the flags, any
  `GETH_` variables and the config file.

## 6. Start the node and confirm the move

Start the node the way you always do, on the same data directory. Then:

```powershell
.\geth.exe attach --exec 'admin.nodeInfo.name'  \\.\pipe\geth.ipc
.\geth.exe attach --exec 'admin.nodeInfo.enode' \\.\pipe\geth.ipc
.\geth.exe attach --exec 'net.peerCount'        \\.\pipe\geth.ipc
.\geth.exe attach --exec 'eth.blockNumber'      \\.\pipe\geth.ipc
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

```powershell
.\geth.exe attach --exec "admin.removePeer('enode://<old ID>@<IP>:30303')" \\.\pipe\geth.ipc
.\geth.exe attach --exec "admin.addPeer('enode://<new ID>@<IP>:30303')" \\.\pipe\geth.ipc
.\geth.exe attach --exec "admin.peers.map(function(p){return p.enode})" \\.\pipe\geth.ipc
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

```powershell
Remove-Item .\geth.exe
Rename-Item .\geth-v1.12.exe geth.exe
```

Keep the new key: rolling back does not make the old one safe, and a release
before `v1.12.21` leaks the new key as it did the old one. Once the cause is
fixed, move to the `v1.13` line again with these steps, rotating the key again
in step 4. A second rename on the same day finds its target name taken, so add
`-2` after `$(Get-Date -Format yyyy-MM-dd)` in it. If the node has to stay on
`v1.12` longer, point it at this repository's trees and the `v1.13` line's
bootnodes, as [Using the trees](../using-the-trees.md#core-geth-v112-line) shows.

## Once the node is stable, delete the v1.12 binary

Once the node has caught up, holds peers, and has run on the `v1.13` line long
enough that you will not roll back, in the folder that holds the node's
`geth.exe`:

```powershell
Remove-Item .\geth-v1.12.exe
```

Every `v1.12` release carries the flaws the audits found, so a copy left on the
machine is one a later mistake can start.

## Building from source

Building needs Go 1.26 or later and a C compiler on `PATH`, such as MinGW-w64.
Build `main`, where fixes and dependency updates land through reviewed pull
requests before they reach a release. Run these one line at a time:

```powershell
git clone https://github.com/ethereumclassic/core-geth.git
cd core-geth
go run build/ci.go install ./cmd/geth
.\build\bin\geth.exe version
```

If a `core-geth` folder is already there, the clone stops on it: remove that
folder first.

`.\build\bin\geth.exe version` prints the version on its first line, such as
`Core-Geth 1.13.1-unstable`, where `unstable` marks a build that is not a
release. `main` keeps moving, so note the `Git Commit` line: it names the code
you built.

Do not clone with `--recursive`: the submodules are several gigabytes, and the
build does not read them. At step 3, instead of unpacking the release, rename
the node's `geth.exe` to `geth-v1.12.exe`, copy `build\bin\geth.exe` into the
folder that holds it, and `cd` back to that folder: the later steps run
`.\geth.exe` from there. Go on only if `.\geth.exe version` then reports `1.13`
on its first line, ending in `-unstable` for a build of `main`.
