---
description: begin and Transaction, the transaction(fn) helpers, inTransaction, and retrying a deadlock.
---

# Transactions

A transaction is a connection with extra state. `commit` makes it stick. Dropping it without a commit rolls it back, so a `guard ... else { return ... }` cannot leave one half done.

```echo
mysql::Transaction $tx = guard $db->begin();
guard $tx->commit();
```

You almost never want that shape. You want the work in a function, and the commit or rollback to follow from what the function answered.

## transaction(fn)

`$db->transaction(...)` runs the work, commits on `.ok`, rolls back on `.error` (and hands that error on):

```echo
guard $db->transaction(function(mysql::Connection $tx) : status<mysql::Error> {
    guard $tx->exec(
        'UPDATE products SET stock = stock - 1 WHERE name = ?',
        ['Chair'],
    ) else ($e) {
        return .error($e);
    }
    guard $tx->exec(
        'UPDATE products SET note = ? WHERE name = ?',
        ['last one soon', 'Chair'],
    ) else ($e) {
        return .error($e);
    }
    return .ok;
}) else ($e) {
    die("transaction: {$e}");
}
```

The generic form hands back a value: `transaction<T>(function(Connection) : result<T, Error>)`. Commit when it answers ok, roll back when it answers an error.

```echo
int64 $id = guard $db->transaction<int64>(
    function(mysql::Connection $tx) : result<int64, mysql::Error> {
        mysql::Outcome $o = guard $tx->exec(
            'INSERT INTO products (name, price, stock) VALUES (?, 1, 1)',
            ['Mug'],
        ) else ($e) {
            return .error($e);
        }
        return .ok($o->lastInsertId as int64);
    },
);
```

The work runs on the same [](api:mysql::Connection). There is no second handle. Nested `transaction` calls are just nested `START TRANSACTION` / `COMMIT`, which MySQL will not do the way you hope; don't nest them.

## begin, when you want the handle

[](api:mysql::Transaction) is the handle `begin` gives you. `commit()` makes it stick. `rollback()` undoes it. Dropping it without a commit rolls it back. `open()` is whether it still needs one of those.

Use this when the work cannot be one function: it spans a callback, or a loop that also talks to something else. For everything else, `transaction(fn)` is the one I would pick, because the rollback is in the type.

## inTransaction

`$db->inTransaction()` is the server's own account after the last command, not this library's. After `begin` it is true. After `commit` or `rollback` it is false. After a statement the server rolled back on its own (a deadlock, a lock wait timeout) it depends on whether that statement was the whole transaction.

## Retrying

`$e->retryable()` is a deadlock or a lock wait timeout, where the server rolled the statement (or the transaction) back. Running the same work again may succeed:

```echo
usize $attempt = 0;
while (true) {
    status<mysql::Error> $done = $db->transaction($work);
    if ($done->ok()) {
        break;
    }
    mysql::Error $e = $done->failure();
    $attempt = $attempt + 1;
    if (!$e->retryable() || $attempt == 3) {
        die("{$e}");
    }
}
```

This library does not retry for you. A retry is your loop, because only you know whether `$work` is safe to run twice.

A [pool](./pool.md) runs `transaction` around one lease, so the whole transaction stays on one connection. A lease dropped mid-transaction is rolled back, so the next borrower does not inherit it.
