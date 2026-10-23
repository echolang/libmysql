---
description: step and view, typed reads by position, zero-copy view(i), and when the in-place path is worth it.
---

# Reading in place

`foreach` on a stream decodes every column of every row into a `Row`. Fine, until the result is wide, or long, or you only wanted three of the columns. [](api:mysql::RowView) is the lazy reader: one pass per row finds where each value starts, and each read decodes just its own column, straight from the packet. No `array<Value>` is built for the row. A column nobody reads costs nothing past that pass.

Built for code that maps rows onto its own types: resolve each column's position once per result, then read every row by position.

```echo
mysql::Rows $raw = guard $db->stream(
    'SELECT name, stock FROM products ORDER BY id',
);
usize $stockAt = $raw->columns()->find('stock') ?? 0;
int64 $units = 0;
while (true) {
    bool $more = guard $raw->step();
    if (!$more) {
        break;
    }
    $units = $units + ($raw->view()->int($stockAt) ?? 0);
}
echo "{$units} units in stock";
```

`step()` moves to the next row: true when there is one, false at the end. `view()` is the [](api:mysql::RowView) that last step stood on. It holds until the next move.

## Positions

`$raw->columns()->find('stock')` is the position, or null. Do this once per result, not once per row. A join can return one name twice: the first one answers.

A position past the last column stops the program, in a release build too: it is a mistake in the code, not in the data. Same as `$row['nope']` on a `Row`. There is no `get` on a view. You already resolved the name.

## Typed reads

The same reads [](api:mysql::Value) has, by position: `int`, `uint`, `float`, `bool`, `text`, `bytes`, `date`, `datetime`, `time`, `isNull`. They answer null for a NULL and for a value that is not that type, the same crossover rules [Values](./values.md) spells out. `isNull($at)` tells the two apart.

```echo
const mysql::RowView& $v = $raw->view();
int64 $n = $v->int($stockAt) ?? 0;
if ($v->isNull($stockAt)) {
    $n = 0;
}
```

`value($at)` reads any column and is the one read that reports a value the server sent malformed. The typed reads swallow that as null; `value` hands you the `.malformed`.

## Zero-copy text

`view($at)` is text, a decimal or bytes, read in place: no copy, valid until the next `step()`, like the view itself. For code that looks at the bytes and moves on. `text($at)` is the copy that outlives the row.

```echo
string::view? $name = $raw->view()->view(0);
if ($name != null) {
    echo string::from(guard $name);
}
```

The view holds until the next move. After the last row, and after a `next()` (which decodes its row without the view), it has no values. `$v->count()` is 0 then. `row()` copies the whole row out as the same `Row` `next()` hands out, and with no row to stand on it stops the program.

## When it is worth it

Three ways to read a result, cheapest last:

1. **`query`.** The whole result, every column, every row, in memory. The simple path. Use it until it hurts.
2. **`stream` plus `foreach` / `next`.** One row at a time, still decoded whole. `foreach` reuses one `Row`. Use it when the result does not fit and you still want `$row['name']`.
3. **`stream` plus `step` plus `view`.** The packet as the server sent it. Decode what you ask for, by position. Use it when you map onto your own types, skip columns, or look at a string and move on.

The in-place path is more typing. That is the trade. I still prefer it for the loop that runs over a lot of rows, because the cost you do not pay is the `Value` array you never build.

[Transactions](./transactions.md) is the other kind of state a connection holds: an open transaction, and the rollback you get for free if you leave early.
