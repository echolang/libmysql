---
description: by: on every call, Options.timeout as the fallback, connectTimeout, and that a timeout closes the connection.
---

# Deadlines

Every call that talks to the server takes `by: tcp::Deadline?`. The one it named, else `Options->timeout` from now, else never.

```echo
mysql::ResultSet $rows = guard $db->query(
    'SELECT 1',
    by: tcp::Deadline(ms: 500),
);
```

That is one command, 500 milliseconds, from the moment `query` starts. Running out is `.timeout`.

## The fallback

`Options->timeout` is the default for every command on that connection that did not name its own deadline. Null (the default) waits as long as it takes. A pool uses the same `Options` for every connection it opens, so setting it there is how every query through the pool gets a budget.

```echo
$options->timeout = time::duration::secs(10);
```

`by:` on the call always wins.

## Connecting

`connectTimeout` (10 seconds) bounds connecting and logging in, together. It is not `timeout`. A slow handshake should not inherit a query budget of "as long as it takes", and a query should not inherit a 10-second connect budget you picked for a distant host.

`Connection::open` uses `connectTimeout`. It does not take `by:`.

## acquire

`Pool::acquire` uses `by:` the same way, with `PoolOptions->acquireTimeout` (30 seconds) as its fallback. The `query` it then runs on the leased connection has its own clock: the `by:` you passed to `pool->query`, else `Options->timeout`. They are two deadlines. Passing `by:` to `pool->query` feeds both, which is usually what you want.

## A timeout closes the connection

Here is the catch: a timeout in the middle of a command closes the connection. What the server still sends could not be told apart from the next answer. The next call on that handle fails `.closed`. A pool will not take it back onto the idle list; it opens another.

A timeout *before* the command starts (the connection was already in a bad state, or `acquire` ran out) does not have leftover bytes, but `.timeout` still means "this call did not happen."

[Errors](./errors.md) is the rest of the cases, and the rule for which failures leave the connection usable.
