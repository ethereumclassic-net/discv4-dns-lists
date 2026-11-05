# Security Policy

## Reporting a vulnerability

**Do not open a public issue for a security vulnerability.**

Report it privately by email to **<security@ethereumclassic.net>**. Include
"SECURITY" in the subject line, and use PGP encryption if possible; the key is
available on request.

For this repository, that covers anything that would let someone put a node into
a tree or keep one out by means other than
[the published criteria](docs/node-selection.md#what-gets-a-node-listed), stop
the trees from being published or served, or reach the signing key or the DNS
credentials. Include what you can: what is affected, what an attacker gains, and
a reproduction if you have one. A report without a reproduction is still worth
sending.

A vulnerability in the client belongs to
[Core-Geth's security policy](https://github.com/ethereumclassic/core-geth/blob/main/SECURITY.md),
which uses the same address.

With the ETC Cooperative's dissolution, Ethereum Classic stakeholders such as
mining pools, exchanges and service providers should use
<security@ethereumclassic.net> as their point of contact. A person answers it:
one of the core developers who maintain this repository and have been with the
network since its inception.

### What to expect

Reports are acknowledged and triaged privately. Where a fix is warranted, it is
prepared privately and disclosed once it is in place. Reporters are credited
unless they ask not to be.

## Automated and AI-assisted review

Findings from automated or agent-assisted review go through the same private
channel as any other. They do not go in a public issue, or in a pull request
whose diff describes the defect before a fix exists.

## What is reported in public

A refused or failed nightly run is not a vulnerability. Every scheduled run
reports its result on the issue labeled
[`pipeline-status`](https://github.com/ethereumclassic/discv4-dns-lists/issues?q=label%3Apipeline-status),
along with whether each bootnode Core-Geth ships answered the night's crawl.
