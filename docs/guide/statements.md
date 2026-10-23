---
description: The implicit statement cache, and the Statement you prepare yourself.
---

# Prepared statements

A query with values is a prepared statement. You do not have to name it. The connection keeps the ones it has seen, and the next `exec` of the same SQL is just an execute.

```echo
guard $db->exec('DO ?', [1]);
guard $db->exec('DO ?', [2]);
// the second call is COM_STMT_EXECUTE of the first prepare
```

`:name` is rewritten to `?` before the server sees the SQL, so `'SELECT :a'` and `'SELECT :a'` again are the same cache key, and `'SELECT ?'` is a different one.

## The cache

`Options->statementCache` is how many the connection keeps. 64 by default. 0 means it prepares every time and does not keep them.

When the cache is full, it is flushed: every cached statement is closed on the server, then the new one is prepared. Simpler than tracking use, and a cache of 64 is already past how many distinct SQL strings a typical connection sends.

`reset` forgets the cache, because the server dropped every statement. Closing the connection does the same.

The cache is per connection. A [pool](./pool.md) does not share it across leases.

## An explicit Statement

`prepare` is when you want the [](api:mysql::Statement) in your hand: to run many times with different params, and to close it yourself.

```echo
mysql::Statement $st = guard $db->prepare(
    'UPDATE products SET stock = :qty WHERE name = :name',
);

guard $st->exec(['qty' => 3, 'name' => 'Lamp']);
$st->close();
```

`$st->params` is how many values each run takes. `$st->names` is the placeholder names, in order, when the SQL used `:name`; empty for `?`. `$st->columns()` is the columns each run returns (empty for a statement that returns no rows).

`query`, `exec` and `stream` on a `Statement` are the same verbs as on a `Connection`, without the SQL: it is already prepared. There is a no-params overload for SQL that was prepared with none.

A `Statement` from `prepare` is never the cache's. Closing it must not pull one out from under a query that is still using the same SQL. Dropping the `Statement` closes it on the server. `close` is safe to call twice.

[Values and types](./values.md) is what those bound values become, on the way in and on the way out.
