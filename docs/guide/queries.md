---
description: query, exec and batch, the two protocols, ResultSet, Row, Outcome, and multi-results.
---

# Queries and results

Three verbs, one connection. `query` reads the whole result into a [](api:mysql::ResultSet). `exec` is the same command when you only care what it did. `stream` is the one that does not buffer, and [Streaming](./streaming.md) owns that.

```echo
mysql::ResultSet $rows = guard $db->query(
    'SELECT name, price FROM products',
);

mysql::Outcome $sold = guard $db->exec(
    'UPDATE products SET stock = stock - 1 WHERE name = ?',
    ['Lamp'],
);
echo "touched {$sold->affectedRows}";
```

Values in the call mean a prepared statement. No values means the text protocol. [Parameters](./params.md) is how those values are written; this page is what comes back.

## Text versus binary

A query with no [](api:mysql::Params) (or with an empty chain) is `COM_QUERY`. Every value comes back as text, and this library parses it into a [](api:mysql::Value) by what the column says it is.

A query with values is prepare-then-execute. The connection [caches](./statements.md) the statement it has seen, so the next `exec` of the same SQL is just an execute. Rows come back in the binary protocol: a NULL bitmap, then each value in its own shape. The [](api:mysql::Value) you read is the same either way. [Values and types](./values.md) is the mapping.

`exec` still goes through a result. A statement that returns no rows just happens to have an empty `ResultSet`, and `exec` hands you its [](api:mysql::Outcome).

## ResultSet

A whole result, in memory: its columns, its rows, and how it ended.

```echo
echo $rows->count();           // 1
echo $rows->empty();           // false
mysql::Row $row = guard $rows->first() else {
    die('no rows');
};
echo $rows[0]['name'];         // Lamp
```

`$rows[0]` is the first row. Past the last row stops the program, in a release build too: it is a mistake in the code, not in the data. `first()` answers null when there are none. `foreach ($rows as $row)` walks them.

## Row

[](api:mysql::Row) is one row: its values, and the columns it shares with every other row of the result. `$row['name']` and `$row[0]` read a [](api:mysql::Value). `foreach ($row as $name => $value)` walks them.

```echo
foreach ($rows as $row) {
    int64 $stock = $row['stock']->int() ?? 0;
    echo "{$row['name']}: {$stock} in stock";
}
```

A name the result does not have stops the program, in a release build too. Same for a position past the last column. `get` is the lookup that cannot stop: it answers null when the result has no such column.

`$row['price']` interpolates as the server sent it. A DECIMAL stays a string of digits.

## Outcome

What a statement that returns no rows did:

- `affectedRows` is how many it touched.
- `lastInsertId` is the id an `AUTO_INCREMENT` column handed out, or 0.
- `warnings` is the server's warning count.
- `info` is the info line the server sent with the OK, often empty.
- `inTransaction()` is true when the server reported an open transaction after this statement.

`query` and `exec` of a statement that also produces rows still have an outcome. `$rs->outcome` is it.

## Columns

`$rs->columns` is the [](api:mysql::Columns) of the result, shared by every row. `$columns->find('stock')` is the position, or null. `$columns->at($i)` is the [](api:mysql::Column): name, table, database, type, flags, charset, length, decimals. `unsigned()`, `nullable()`, `binary()` are the flags a program actually branches on.

You rarely need this on a `ResultSet`. The place it pays off is [reading in place](./rowview.md), where you resolve each name once and then read every row by position.

## Multi-results

A `CALL`, or a query string with more than one statement, can produce several results. `query` and `exec` read the first one and drop the rest, so the connection is ready again.

`batch` keeps every result, in order:

```echo
$options->multiStatements = true;
mysql::Connection $db = guard mysql::Connection::open($options);

array<mysql::ResultSet> $sets = guard $db->batch(
    'SELECT 1 AS a; SELECT 2 AS b',
);
```

`multiStatements` is off by default. It is what turns an injection into a second statement. Turn it on when you mean it. A `CALL` that returns several results does not need the flag; `batch` still collects them.

[Parameters](./params.md) is how the SQL gets its values, including the `:name` form the server itself does not speak.
