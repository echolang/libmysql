---
description: stream, foreach with one reused Row, next, more, finish, and the busy connection.
---

# Streaming

A result too big to hold: rows one at a time. [](api:mysql::Connection::stream) starts it. While it is open the connection answers `.busy`. Reaching the end, `finish()`, or dropping the [](api:mysql::Rows) frees the connection again.

```echo
mysql::Rows $stream = guard $db->stream(
    'SELECT id, name, note FROM products ORDER BY id',
);
foreach ($stream as $row) {
    string $note = $row['note']->text() ?? '-';
    echo "#{$row['id']} {$row['name']} {$note}";
}
guard $stream->finish();
```

`foreach` (or `next()`) hands out each row decoded whole. `step` with `view` reads the row in place, and [Reading in place](./rowview.md) is that path.

## foreach, one Row

What `foreach` walks `Rows` with is one [](api:mysql::Row), loaded with each row in turn. A loop that does not keep its rows allocates nothing for them: the last row's storage is reused. A row you copied out (`$keep = $row`) is left alone, and the next iteration gets a new one.

A failure stops the loop. Iteration cannot hand an error back, so `finish` is where it shows up:

```echo
foreach ($stream as $row) {
    echo $row['name'];
}
guard $stream->finish() else ($e) {
    die("stream: {$e}");
}
```

Skip `finish` and you still find out, because dropping the `Rows` calls it. Calling it yourself is the place a `die` or a `return` can name the failure.

## next

`$stream->next()` is the same decoded row, one at a time, as a `result<Row?, Error>`. Null at the end of the current result. Use it when the loop has to be a `while` (you want to stop early, or you are not in a `foreach`).

```echo
while (true) {
    mysql::Row? $row = guard $stream->next();
    mysql::Row $r = guard $row else {
        break;
    };
    echo $r['name'];
}
```

`next` decodes its row without the view. After it, `view()` has no values. Pick one way through a result.

## more

A `CALL`, or a multi-statement query, can produce several results. `more()` steps to the next one, dropping what is left of this one: true when there is one, false when that was the last.

```echo
mysql::Rows $rs = guard $db->stream('CALL stats()');
while (true) {
    foreach ($rs as $row) {
        echo $row[0];
    }
    bool $another = guard $rs->more();
    if (!$another) {
        break;
    }
}
```

`$rs->columns()` and `$rs->outcome()` follow the current result. After the last row of a result that has no more after it, the connection is free.

## busy

Until the stream ends, this connection answers `.busy` to anything else: another `query`, `exec`, `ping`, `begin`. Finish it first. A [pool](./pool.md) will not take a busy connection back onto the idle list; it closes it. That is why `stream` is not a verb on the pool: you need the [lease](./pool.md) in your hand for as long as the stream is open.

A failure ends the stream, and the command with it. The rest of the result is not read, so unless the server ended the command with an error packet the connection is closed: what is left on the wire would otherwise be read as the answer to the next command. [Errors](./errors.md) has that `abandon` rule.

[Reading in place](./rowview.md) is the other way through a stream: no `Row` is built, and a column nobody reads costs nothing past the pass that finds it.
