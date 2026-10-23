---
description: Pool and PoolOptions, acquire order, Lease, pings and lifetime, and the verbs that take a lease around one call.
---

# Pool

A [](api:mysql::Connection) is one session, one thread at a time. A program with many threads wants many sessions, without opening a new one for every query. [](api:mysql::Pool) is that: connections shared by whoever needs them.

```echo
mysql::Pool $pool = mysql::Pool($options, mysql::PoolOptions($max: 4));
mysql::ResultSet $count = guard $pool->query(
    'SELECT COUNT(*) AS n FROM products',
);
echo "the pool counts {$count[0]['n']} products";
$pool->close();
```

`query`, `exec` and `transaction` take a lease around one call. `acquire` is when you want the [](api:mysql::Connection) in your hand.

## Limits

[](api:mysql::PoolOptions) is plain data, same shape as `Options`:

| Field | Default | Means |
|:--|:--|:--|
| `max` | 10 | Connections open at most, lent and idle together. |
| `maxIdle` | 10 | Idle connections kept at most; one given back beyond this is closed. |
| `idleTimeout` | 10 minutes | An idle connection older than this is closed instead of lent; null keeps them. |
| `maxLifetime` | none | A connection older than this is closed when it comes back; null keeps it for good. |
| `acquireTimeout` | 30 seconds | How long `acquire` waits when the call names no deadline. |
| `pingAfterIdle` | 1 second | A connection idle longer than this is pinged before it is lent. |

`$pool->options` is the [](api:mysql::Options) every new connection is opened with. `$pool->limits` is this struct. `$pool->open()` is how many connections exist now, lent and idle. `$pool->idle()` is how many of them are idle.

## acquire

`acquire` lends one out as a [](api:mysql::Lease). The order it tries:

1. An idle connection that is still alive and not past `idleTimeout` / `maxLifetime`. If it has been idle longer than `pingAfterIdle`, it is pinged first, so a server that dropped it is found out here and not in the caller's first query.
2. A new connection, while `open < max`.
3. Wait. Waiters are served first come, first served, each handed the next connection given back. A slot that opens up (a connection closed rather than returned) lets the first waiter open a new one.
4. `.exhausted` when none came free before the deadline.

```echo
mysql::Lease $lease = guard $pool->acquire();
mysql::Connection $db = $lease->db();
guard $db->exec('DO 1');
$lease->release();
```

The lease goes back when dropped, or at `release()`. Safe to call twice. A lease dropped mid-transaction is rolled back, so the next borrower does not inherit it. A dead, busy, too old, or surplus connection is closed instead of lent.

## Verbs on the pool

`query`, `exec` and `transaction` (both forms) acquire, run, and let the lease go. The whole [transaction](./transactions.md) stays on one connection, which is the point.

What needs `acquire()->db()`, because it holds the connection past one call:

- `stream`, for as long as the [stream](./streaming.md) is open.
- `prepare`, for as long as the [statement](./statements.md) is open (it is tied to that connection).
- `batch`, which is several results of one command.

There is no `stream` / `prepare` / `batch` on the pool. That is deliberate: a stream that outlived its lease would look like a busy connection coming back, and the pool would close it.

## close

`close` closes the idle connections and refuses new leases. Connections still lent are closed as they come back. Waiters wake up and see `.closed` or `.exhausted`, depending on the race.

[Deadlines](./deadlines.md) is how long `acquire` waits, and how long the query it then runs may take. They are two clocks.
