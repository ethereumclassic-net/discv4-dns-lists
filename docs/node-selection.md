# How nodes are chosen

This page covers what gets a node into a tree, why a tree holds only nodes on the
network's current fork, how large a tree can be, and which nodes the cap keeps.

## What gets a node listed

A node is published when it:

- answers the crawl's discovery pings from a reachable address,
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
ranking cannot tell it from a synced one.
Measured 2026-09-25:

| classic | current `be46d57c` | genesis stage `fc64ec04` | before Spiral `7fd1bb25` |
|---|---|---|---|
| published tree, before this check | 46 | 73 | 1 |
| crawl set, before the cap | 139 | 279 | 2 |

A new node syncing Ethereum Classic mainnet that day dropped 8 distinct peers on
sync timeouts, and all 8 were in the genesis-stage group. That stage is also the
one Ethereum mainnet shares, so the record cannot say which chain such a node is
on.

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
syncing client needs, and one node advertising a later hash, truthfully or not,
must not be able to take every tree down. The pin is not read from Core-Geth
automatically either, because a fork is scheduled in Core-Geth's `main` config
before its release is cut and before it activates on the chain, while the
current-fork nodes keep serving until then. Instead the run reads Core-Geth's own
`params/config_classic.go` and `params/config_mordor.go` and warns when their
fork schedule has moved past the pin, leaving the trees on the current fork until
a maintainer bumps it for the release. The last published tree stays in DNS, and
the script never falls back to publishing a stage the network has left.

## How large a tree is, and why

The cap comes from the DNS zone budget rather than from what the crawl happens
to find. A tree of N nodes costs N records, plus one for the root, plus about one
branch record per 11 nodes, measured against real signed trees at 11 nodes → 14
records and 150 → 165.

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

A tree holds at most 120 Classic or 15 Mordor nodes, ranked:

1. A node that answered the night's crawl ranks ahead of one that did not.
2. Then the higher **score** ranks first: the crawler adds a point each time a
   node answers and halves the score each time it does not, so a high score
   marks a node that has kept answering. A tie goes to the more recent answer.

No address publishes more than two nodes, and no `/24` (or `/48` for IPv6) more
than two, even with seats left over, and a record that has never answered the
crawl is never published.

### At most two seats per address, and per subnet

One machine is one point of failure however many node keys it runs, and ranked
by node alone a host running many keys would hold a seat for each. So no address
publishes more than two nodes, whatever seats are left over. Measured on the
2026-11-05 crawl, the 134 Classic nodes that answered sat on 102 addresses, two
of which ran 25 of the answering keys between them, one of them with 20 on
consecutive ports. A key-counting ranking publishes all 25; the two-per-address
cap holds the two to four seats. A seat that only a host already holding two
could fill stays empty, since the zone budget sets the cap as a ceiling rather
than a count to reach. On the 2026-11-05 crawl the Classic tree held 114 nodes.

**A second ceiling holds each `/24`**, or `/48` for IPv6, to two nodes as well,
so that acquiring many addresses in one subnet buys no more than acquiring one.
The per-address cap holds one machine; this holds one operator spreading over
addresses in a subnet it controls. The two compose: a `/24` with two addresses
each running two nodes offers four and publishes two. On the 2026-11-05 crawl it
changed nothing — 101 of the 103 `/24`s held at most two nodes already, and the
two that held more were the single-address concentrators the per-address cap had
itself held to two — so the limit constrains any one subnet's share at no present
cost.

**The ranking does not otherwise weigh network diversity, and that is
deliberate.** Both limits are ceilings, not a ranking tier. Ranking each
subnet's best node ahead of every second node reads as diversity, but every
fresh identity is the best in its own `/24`, so one node per subnet
would take a tree-worth of first-tier seats on its first night. The ceilings
resist concentration without that reordering: a new address climbs only on
score, which takes the time a score takes, so it cannot pass an established node
by sitting in an empty subnet.

**The limits do not fall on operators who only share a provider.** The address
is the one the crawl reached the node at, so a node that answered receives
packets there. On the same crawl, the 47 nodes at the three hosting providers
carrying the most of them sat on 45 addresses, and only two `/24`s held more than
two nodes at all, each a single concentrated address rather than several
operators sharing a subnet.

### A key rotation keeps a node's standing

The crawler keys a node by its public key, so a node whose operator rotates its
key, as the move to the `v1.13` line asks, would come back as a new node with no
score, behind every node still running on its old key. So a node that answers at
the same endpoint, IP address and UDP port, as a key that went silent, and that
first answered after that key last did, takes over that key's score as the last
committed crawl recorded it. Ties in the ranking go to the endpoint rather than
the key, so a rotated node takes exactly the place it held before.

Only whoever receives packets at an endpoint can answer there, and the score
moves rather than doubles, so a rotation neither gains nor costs anything.
Downtime still costs what it costs any node: a key silent long enough for the
crawler to drop it leaves nothing to carry.

### Score before the last answer

Ranked instead by when each node last answered, to the second, a night's
responders fall in the order the crawl happened to reach them, and newly found
nodes displace long-lived ones. Replayed over the 57 crawls committed from
2026-09-10 to 2026-11-05, on the nodes where the two rankings disagree:

| | ranked by score | ranked by last answer |
|---|---|---|
| answered the next night's crawl | 97% | 89% |
| answered all of the next seven nights' crawls | 91% | 58% |
| median time since its first answer | 19 days | 2 days |

The two disagree on up to 13 of a tree's 120 nodes a night, so across a whole
tree the gain is small. Ranking by score also changes fewer of a tree's nodes
from night to night: 1.7 a night on average, against 4.3. Mordor's tree has never
reached its cap, so there the ranking decides nothing beyond the limit of two per
address.
