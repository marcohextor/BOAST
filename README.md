# BOAST

**BOAST** (BOAST Outpost for AppSec Testing) is a server designed to receive
and report Out-of-Band Application Security Testing (OAST) reactions.

```
            ┌─────────────────────────┐
            |          BOAST          ◄──┐
          ┌─┤ (DNS, HTTP, HTTPS, ...) |  |
          │ └─────────────────────────┘  │
          │                              │
Reactions │                              │ Reactions
          │                              │
          │                              │
          │                              │
   ┌──────▼──────────┐   Payloads   ┌────┴────┐
   │ Testing client  ├──────────────► Target  │
   └─────────────────┘              └─────────┘
```

Some application security tests only trigger out-of-band reactions from the
tested applications. These reactions are not sent back to the testing client,
so a separate Internet-reachable server is needed to capture them. BOAST is
that server.

BOAST ships with DNS, HTTP, and HTTPS receivers, each supporting multiple
simultaneous ports. New receivers can be plugged in by implementing against
the shared storage interface.

## Used By

BOAST is used by projects such as:

- [Zed Attack Proxy (ZAP)](https://www.zaproxy.org/)

## Documentation

https://github.com/marcohextor/boast/tree/master/docs
