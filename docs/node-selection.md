# How nodes are chosen

This page covers what gets a node into a tree, why a tree holds only nodes on the
network's current fork, how large a tree can be, and which nodes the cap keeps.

## What gets a node listed

A node is published when it:

- answered that night's crawl from a reachable address,
- carries an `eth` entry in its node record with the network's current fork ID,
  and
- is among the first 120 Classic or 15 Mordor such nodes in the ranking that
  [Which nodes the cap keeps](#which-nodes-the-cap-keeps) describes, which
  publishes at most two nodes from any one address and two from any one `/24`.

The criteria are the same for every node, whoever runs it. The lists start a
node's search and do not choose its peers: after its first contacts, a node finds
further peers through the discovery network itself.

## Only nodes on the current fork ID are published

**`-eth-network` admits every stage of the fork schedule, not only the current
one.** It is Core-Geth's `forkid.NewStaticFilter`, which judges
[EIP-2124](https://eips.ethereum.org/EIPS/eip-2124) compatibility from block
zero. From there, every later stage looks like a node that is ahead, so any fork
ID on the network's schedule passes, and only one that is not on it is rejected.

**That admits nodes a new client cannot sync from.** A node that starts from an
empty chain advertises the genesis stage in its record until it imports its first
block, because the record is refreshed only on a new chain head and a snap sync
sets none until it finishes. Such a node answers every discovery ping, so the
ranking cannot tell it from a synced one, but it serves no blocks. That stage is
also the one Ethereum mainnet shares, so the record cannot say which chain such a
node is on.

**So [the script](../scripts/update-lists.sh) keeps only nodes on
`FORK_HASH_CLASSIC` or `FORK_HASH_MORDOR`**, the fork hash a node at the chain
head advertises, and it does so before the cap, so the cap chooses among current
nodes. Moving the filter's vantage point to the chain head would not be enough:
EIP-2124 also accepts a node that is behind when its next fork matches, which is
the genesis-stage case again.

**The values are pinned, and a pin goes stale at the next fork.** Before a
scheduled fork activates, nodes that announce it as their next fork and nodes
that do not yet know of it carry the same hash, and both are kept. A node that
has moved to the hash after the pin is left out of the tree, not a reason to
refuse the whole publish: the nodes still on the current fork are the ones a
syncing client needs. The pin is not read from Core-Geth automatically either,
because a fork is scheduled in Core-Geth's `main` config before its release is
cut and before it activates on the chain, while the current-fork nodes keep
serving until then. Instead the run reads Core-Geth's own
`params/config_classic.go` and `params/config_mordor.go` and warns when their
fork schedule has moved past the pin, leaving the trees on the current fork until
a maintainer bumps it for the release. The last published tree stays in DNS, and
the script never falls back to publishing a stage the network has left.

## How large a tree is, and why

The cap comes from the DNS zone budget rather than from what the crawl happens
to find. A tree of N nodes costs N records, plus one for the root, plus about one
branch record per 11 nodes: 11 nodes take 14 records and 150 take 165.

**Both trees share one budget, and discovery does not get all of it.** A
Cloudflare zone created on or after 2024-09-01 on the free plan holds **200
records** for the whole zone, not per tree. The classic and mordor trees are both
in it, alongside whatever else the domain serves, such as mail records, the apex
site and service subdomains, and all of it counts against the same 200.

```
classic  120 nodes -> ~132 records
mordor    15 nodes ->  ~18 records
                       ~150, leaving room for the domain's other services
```

**A tree's job is to reach the first few peers**, after which the discv4 DHT does
the work. Against three hardcoded bootnodes, 120 nodes is already a large
improvement, and the marginal value of node 300 is close to zero. Mordor's cap of
15 is headroom for a small network: its tree carries every current node the
crawl finds, up to the cap, and each night's count is in that night's commit
message.

**No `snap.*` trees are published.** No Core-Geth path points snap discovery at
one on any network: wherever a release sets its built-in trees, it sets
`SnapDiscoveryURLs` to the same list as `EthDiscoveryURLs`. Given
`--discovery.dns`, a release sets no built-in trees and the flag fills only
`EthDiscoveryURLs`, so `SnapDiscoveryURLs` holds only what a config file puts
there.
Publishing them would spend roughly 45% of the record budget on trees nothing
reads, which on a 200-record budget is the difference between 120 published
classic nodes and 65.

## Which nodes the cap keeps

A tree holds at most 120 Classic or 15 Mordor nodes, chosen from the nodes that
answered the night's crawl. A node that did not answer is not published, even
with seats left over, whether it answered an earlier crawl or never has.

Among the nodes that answered, the higher **score** ranks first: the crawler adds
a point each time a node answers and halves the score each time it does not, so
a high score marks a node that has kept answering. A tie goes to the more recent
answer.

No address publishes more than two nodes, and no `/24` (or `/48` for IPv6) more
than two, even with seats left over.

### At most two seats per address, and per subnet

One machine is one point of failure however many node keys it runs, so no
address publishes more than two nodes, whatever seats are left over. A second
ceiling holds each `/24`, or `/48` for IPv6, to two nodes as well, so a tree
spreads across networks as well as machines. The two compose: a `/24` with two
addresses each running two nodes offers four and publishes two.

A seat that only an address or subnet already at its limit could fill stays
empty, since the zone budget sets the cap as a ceiling rather than a count to
reach. Both limits are ceilings, not a ranking of their own: the nodes an
address or subnet keeps are its best-ranked ones, and nothing else orders the
tree.

**The limits do not fall on operators who only share a provider.** The address
is the one the crawl reached the node at, and a `/24` is far narrower than a
hosting provider, so operators who only share a provider rarely share a limit.

### A key rotation keeps a node's standing

The crawler keys a node by its public key, so a node whose operator rotates its
key, as the move to the `v1.13` line asks, would come back as a new node with no
score, behind every node still running on its old key. So a node that answers at
the same endpoint, IP address and UDP port, as a key that went silent, and that
first answered after that key last did, takes over that key's score as the last
committed crawl recorded it. Ties in the ranking go to the endpoint rather than
the key, so a rotated node takes exactly the place it held before.

Both keys must advertise the same network's current fork ID, and only the
networks published here are considered. A key silent long enough for the crawler
to drop it leaves nothing to carry.

### Score before the last answer

Ranked instead by when each node last answered, to the second, a night's
responders would fall in the order the crawl happened to reach them, and newly
found nodes would displace long-lived ones. Ranked by score, a tree keeps the
nodes that have kept answering and changes fewer of them from night to night.
Where a tree holds fewer nodes than its seats, the ranking decides only which
nodes an address or subnet over its limit keeps.
