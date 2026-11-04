# Moving a v1.12 node on Windows

These steps move a node on Windows from any Core-Geth `v1.12` release to the
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

Compare the last two lines of output: the letters must match, and case does not
matter. If they differ, delete the file and download it again rather than
running it. [coregeth.com/downloads](https://coregeth.com/downloads/#upgrade)
lists every file the release carries.

On a node that holds value, also check where the file came from. This needs the
[GitHub CLI](https://cli.github.com/), signed in with `gh auth login`:

```powershell
gh attestation verify "core-geth-win64-$VERSION.zip" --repo ethereumclassic/core-geth
```

It must print `Verification succeeded`. If it does not, do not run the file.

## 2. Stop the node cleanly

- **In a console window:** press Ctrl+C once and wait. A window opened from the
  Startup folder then asks `Terminate batch job (Y/N)?`; type `Y`.
- **Under a service wrapper:** stop it with that tool.

Wait until the log prints `Blockchain stopped` and the process exits.

## 3. Install the release

In the window you used for step 1, keep the old binary and unpack the new one in
its place:

```powershell
Rename-Item .\geth.exe geth-v1.12.exe
Expand-Archive "core-geth-win64-$VERSION.zip" -DestinationPath . -Force
.\geth.exe version
```

Go on only if the first line `.\geth.exe version` prints names a `1.13`
release, such as `Core-Geth 1.13.0-stable`. `geth-v1.12.exe` is the old binary,
kept so you can roll back.

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

Save the file as UTF-8 with no byte order mark. A byte order mark, or UTF-16,
stops the start with `invalid TOML syntax`.

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

Start the node the way you always do, on the same data directory. Then:

```powershell
.\geth.exe attach --exec 'admin.nodeInfo.name'  \\.\pipe\geth.ipc
.\geth.exe attach --exec 'admin.nodeInfo.enode' \\.\pipe\geth.ipc
.\geth.exe attach --exec 'net.peerCount'        \\.\pipe\geth.ipc
.\geth.exe attach --exec 'eth.blockNumber'      \\.\pipe\geth.ipc
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

```powershell
.\geth.exe attach --exec "admin.removePeer('enode://<old ID>@<IP>:30303')" \\.\pipe\geth.ipc
.\geth.exe attach --exec "admin.addPeer('enode://<new ID>@<IP>:30303')" \\.\pipe\geth.ipc
.\geth.exe attach --exec "admin.peers.map(function(p){return p.enode})" \\.\pipe\geth.ipc
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

```powershell
Remove-Item .\geth.exe
Rename-Item .\geth-v1.12.exe geth.exe
```

Keep the new key: rolling back does not make the old one safe.

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
