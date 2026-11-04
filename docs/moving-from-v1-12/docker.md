# Moving a v1.12 node in Docker

These steps move a node running in Docker from a Core-Geth `v1.12` image of
`v1.12.17` or later, `etclabscore/core-geth`, to the latest image of the `v1.13`
line, built from `ethereumclassic/core-geth`. The node keeps its data and its
chain, and gets a new P2P node key.
[Moving a v1.12 node](../moving-from-v1-12.md) says why each step is there.

The commands assume a container named `core-geth` with its data at `/root`, as
the `v1.12` instructions ran it, with `-v <host directory>:/root`. Put your own
container name in place of `core-geth`. For Mordor, use `.ethereum/mordor` in
the paths and `--mordor` in place of `--classic`.

## Before you start

With the node running, record what it is and where it is:

```bash
docker exec core-geth geth version
docker exec core-geth geth attach --exec 'eth.blockNumber'      /root/.ethereum/classic/geth.ipc
docker exec core-geth geth attach --exec 'admin.nodeInfo.enode' /root/.ethereum/classic/geth.ipc
```

Keep the last line's output. It is the node's enode ID, which step 3 changes.

Then check where the container keeps its data:

```bash
docker inspect core-geth --format '{{range .Mounts}}{{.Destination}} {{end}}'
```

If it prints `/root` or `/root/.ethereum`, the data is in a host directory or a
named volume, which the steps below carry to the new container. If it prints
other paths, the steps carry what is mounted at them: if the node's data
directory is under one of them, change the paths in the commands to match. If it
prints nothing, or only paths that do not hold the data directory, such as a
config file's, the data is inside the container itself, and neither image
declares a volume to catch it. Then follow
[If the data is inside the container](#if-the-data-is-inside-the-container) at
step 3, or the new container starts with no chain and resyncs.

## 1. Get the latest image

The node can keep running for this step.

```bash
IMAGE=ghcr.io/ethereumclassic/core-geth:latest
docker pull $IMAGE
gh attestation verify oci://$IMAGE --repo ethereumclassic/core-geth
```

The last line checks where the image came from. It needs the
[GitHub CLI](https://cli.github.com/), signed in with `gh auth login`, although
the pull does not. In a terminal it must print `✓ Verification succeeded!`; if
it does not, do not run the image.
[coregeth.com/downloads](https://coregeth.com/downloads/#install) has the other
ways to get the image, such as loading the image file the release carries. Keep
the old image: rolling back uses it.

## 2. Stop the node cleanly

```bash
docker stop -t 300 core-geth
docker logs --tail 50 core-geth 2>&1 | grep 'Blockchain stopped'
```

The second command should print `Blockchain stopped`. If it prints nothing,
either the stop was not clean or `docker logs` cannot read this container's log
driver. You can go on in both cases: after an unclean stop the node recovers at
its next start, and its block number may start below the one you recorded. Use
`-t 300`: a plain `docker stop` kills the node if it has not stopped within 10
seconds, and a node killed while importing blocks moves its head back on its
next start and imports them again.

## 3. Rotate the P2P node key

This runs in a throwaway container from the new image, which reaches the data
through the old container's mounts:

```bash
docker run --rm --volumes-from core-geth --entrypoint sh $IMAGE \
  -c "mv -n /root/.ethereum/classic/geth/nodekey /root/.ethereum/classic/geth/nodekey.old-rotated-$(date +%F)"
```

The renamed file keeps the old key, and the next start writes a new one. If the
old container starts the node with `--nodekey` or `--nodekeyhex`, or sets
`GETH_NODEKEY` or `GETH_NODEKEYHEX`, leave that out of the `docker run` in
step 5, because it overrides the file. If the rename prints
`No such file or directory`, the data is not where the command looks: check the
path, and check
[If the data is inside the container](#if-the-data-is-inside-the-container).

### If the data is inside the container

When the check before step 1 printed nothing, copy the data out of the stopped
container, rename the key in the copy, and run the new container on the copy.
The copy needs as much free space as the chain takes:

```bash
mkdir -p $HOME/core-geth-data
docker cp core-geth:/root/. $HOME/core-geth-data/
docker run --rm -v $HOME/core-geth-data:/root --entrypoint sh $IMAGE \
  -c "mv -n /root/.ethereum/classic/geth/nodekey /root/.ethereum/classic/geth/nodekey.old-rotated-$(date +%F)"
```

In step 5, give the new container `-v $HOME/core-geth-data:/root` in place of
`--volumes-from core-geth-v1.12`. The chain carries over with the copy, so the
node does not resync.

### If this node lists static peers

Static peers are listed under `[Node.P2P]` in the file passed with `--config`.
Edit it while the node is down:

```toml
[Node.P2P]
StaticNodes = ["enode://<node ID>@<IP>:30303"]
```

A peer that has already moved has a new ID, so use that. Separate entries with
commas. `TrustedNodes` takes the same form. The client ignores
`static-nodes.json`, so move its entries here. With no file yet, save these two
lines. To give the new container the file, add
`-v <path>/config.toml:/config.toml:ro` to the `docker run` in step 5, and
`--config /config.toml` after the image name.

## 4. Check the flags and the config file

While the node is down:

- **A config file:** if the node starts with `--config`, open the file and
  delete any `BootstrapNodes`, `EthDiscoveryURLs` and `SnapDiscoveryURLs` lines,
  unless you put them there yourself to name bootnodes or trees other than the
  release's own: the values `geth dumpconfig` writes are the `v1.12` release's,
  and the new release keeps them with no message. A file a `v1.12.17` or
  `v1.12.18` node starts from can also set `ECBP1100` or `ECBP1100Disable`,
  which stop the new release at the start: delete those lines, and if one holds
  a block number, the file was setting MESS, so decide its setting under
  **MESS** below. To check, run
  `docker run --rm --volumes-from core-geth $IMAGE <flags> dumpconfig` with the
  options and flags you will give the new container, including any `-v` for a
  config file: the `EthDiscoveryURLs` and `SnapDiscoveryURLs` it prints should
  each list the three trees for the node's network in
  [Using the trees](../using-the-trees.md#the-trees). It writes the new node key
  file if there is none, which the new container then uses.
- **Discovery flags:** take out any `--discovery.dns` or `--bootnodes` you added
  on the `v1.12` line from the flags after the image name. The `v1.13` line has
  both built in; `--bootnodes` would hold the node to the nodes it names, and
  `--discovery.dns` would leave its snap list empty.
- **MESS:** add `--mess` or `--mess=false` after the image name, the same on
  every node you run ([MESS](../moving-from-v1-12.md#mess)).
- **RPC exposure:** go through the four
  [RPC exposure](../moving-from-v1-12.md#rpc-exposure) checks, in the flags, any
  `GETH_` variables and the config file. On Docker's default bridge network
  `--http.addr` stays `0.0.0.0`, as the `docker run` below has it, so the
  published port can reach the node: publish the RPC port on `127.0.0.1` only,
  as it does. A container run with `--network host` publishes no ports, so there
  `--http.addr` must be `127.0.0.1`.

## 5. Replace the container and confirm the move

Keep the old container, stopped, and start a new one from the new image on the
same data. First note the old container's restart policy, which a rollback puts
back: `docker inspect core-geth --format '{{.HostConfig.RestartPolicy.Name}}'`.

Before you run the block below, put the old container's flags in place of the
ones after the image name, as step 4 changed them:
`docker inspect core-geth --format '{{json .Args}}'` prints them, and
`docker inspect core-geth --format '{{json .Config.Env}}'` prints any `GETH_`
variables, which go in as `-e` options. If the old container published P2P on
other ports, change the two `30303` mappings to match. Keep RPC published as
`-p 127.0.0.1:8545:8545`, even if the old container published it on every
interface.

Then run it:

```bash
docker rename core-geth core-geth-v1.12
docker update --restart no core-geth-v1.12
docker run -d --name core-geth \
  --restart unless-stopped --stop-timeout 300 \
  --volumes-from core-geth-v1.12 \
  -p 30303:30303 -p 30303:30303/udp -p 127.0.0.1:8545:8545 \
  $IMAGE \
  --classic --http --http.addr 0.0.0.0 --http.port 8545
```

Then check the move:

```bash
docker exec core-geth geth version
docker exec core-geth geth attach --exec 'admin.nodeInfo.enode' /root/.ethereum/classic/geth.ipc
docker exec core-geth geth attach --exec 'net.peerCount'        /root/.ethereum/classic/geth.ipc
docker exec core-geth geth attach --exec 'eth.blockNumber'      /root/.ethereum/classic/geth.ipc
```

If a line cannot connect, wait a minute and run it again.

- **`geth version`** must report a `1.13` release on its first line, such as
  `Core-Geth 1.13.0-stable`.
- **The enode ID** must differ from the one you recorded. If it is the same, the
  node is still on the old key: stop it and redo step 3.
- **The peer count** climbs within minutes. If it stays at zero, see
  [Why does the node have no peers?](https://docs.coregeth.com/operate/troubleshooting/#why-does-the-node-have-no-peers)
- **The block number** starts at or above the one you recorded, because the node
  kept syncing until you stopped it, or below it after an unclean stop. Then it
  climbs. Compare it with a block explorer or another node you run: it should
  reach the chain head and follow it. If it stops climbing short of the head,
  stop and investigate rather than resync.

These checks do not show which trees the node reads: the `dumpconfig` check in
step 4 does.

### Give the new ID to the nodes that list this one

They can no longer connect to this node, and neither side logs it at the default
verbosity. On each one, `v1.12` or `v1.13`, run these lines with the old ID
you recorded, the new one, and the address and port the entry already has. For
a node in another container, put its name in place of `<other container>`; for
a node outside Docker, run the `geth attach` part on its host:

```bash
docker exec <other container> geth attach --exec "admin.removePeer('enode://<old ID>@<IP>:30303')" /root/.ethereum/classic/geth.ipc
docker exec <other container> geth attach --exec "admin.addPeer('enode://<new ID>@<IP>:30303')" /root/.ethereum/classic/geth.ipc
docker exec <other container> geth attach --exec "admin.peers.map(function(p){return p.enode})" /root/.ethereum/classic/geth.ipc
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

**If you copied the data out**, do not start the old container: its own copy of
the data still holds the old key. Stop and remove the new container, then run
the image the old one used,
`docker inspect core-geth-v1.12 --format '{{.Config.Image}}'`, on the copy,
with `-v $HOME/core-geth-data:/root` and the old container's ports and flags.
Leave out `--mess`, which a `v1.12` binary refuses.

**Otherwise**, the data works with both releases, so rolling back swaps the new
container for the old one:

```bash
docker stop -t 300 core-geth &&
  docker rm core-geth &&
  docker rename core-geth-v1.12 core-geth &&
  docker update --restart unless-stopped core-geth &&
  docker start core-geth
```

Put the restart policy you noted in step 5 in place of `unless-stopped`. The old
container starts with the flags it always had.

Keep the new key either way: rolling back does not make the old one safe, and a
release before `v1.12.21` leaks the new key as it did the old one: move to the
`v1.13` line again as soon as you can, rotating the key again in step 3.
