---
description: ? with an array, :name with a map, the builder chains, null as SQL NULL, and what the SQL scanner skips.
---

# Parameters

MySQL on the wire only knows `?`. This library also lets you write `:name` in the SQL, and binds a map of values onto those names. Write the values as a literal where the params go.

An array for `?`. A map for `:name`. A literal holds one value just as well: `['Lamp']`.

```echo
$db->exec(
    'INSERT INTO products (name, price, stock) VALUES (?, ?, ?)',
    ['Desk', .decimal('10.00'), 3],
);
$db->exec(
    'INSERT INTO products (name, price, stock) VALUES (:name, :price, :stock)',
    [
        'name'  => 'Lamp',
        'price' => .decimal('49.90'),
        'stock' => 12,
    ],
);
```

[](api:mysql::Params) is a class, so every call hands back the same builder. The literal is the start. [Values](./values.md) is what each element becomes.

## Chains

To keep going after the literal, start a chain with `.of([...])` or `.named([...])` and add to it:

```echo
mysql::Params $rows = .of(['Lamp', 1])->add(['Rug', 2]);
mysql::Params $range = .named(['min' => 0])->set('max', 100);
```

Code that builds params in a loop starts from an empty one:

```echo
string $sql = 'INSERT INTO products (name, price, stock) VALUES ';
mysql::Params $values = [];
foreach ($names as $i => $name) {
    if ($i > 0) {
        $sql->append(', ');
    }
    $sql->append('(?, ?, ?)');
    $values->add([$name, .decimal('10.00'), $i as int32]);
}
$db->exec($sql, $values);
```

`$p[] = $v` is one value for the next `?`. `$p['name'] = $v` is the value for `:name`. Setting a name again replaces it.

```echo
mysql::Params $p = [];
$p[] = 'Desk';
$p['stock'] = 12;
```

That last snippet mixes the two styles on purpose. Don't. The next section is why.

## The rules

Mixing `add` and `set` on one `Params` is `.invalid`. A map for SQL with `?`, a list for SQL with `:name`: also `.invalid`. A value with no placeholder, a placeholder with no value, a name the statement does not have: too. The count has to match, and every name has to be used.

An Echo `null` is SQL NULL:

```echo
string? $note = null;
$db->exec(
    'UPDATE products SET note = :note WHERE name = :name',
    ['note' => $note, 'name' => 'Rug'],
);
```

A `bool` is sent as the integer 0 or 1. A `uint32` / `uint64` is sent unsigned, so a value past `int64`'s range survives the trip. A signed integer is sent signed. [Values and types](./values.md) is the full mapping, both directions.

## What the scanner skips

`:name` is rewritten to `?` once per SQL string, with the names kept in the order they appear. The scan knows MySQL's quoting and comments, so a `:` inside a string, an identifier or a comment is left alone.

Left alone:

- quoted strings and identifiers: `'...'`, `"..."`, `` `...` ``
- line comments: `-- ` (a dash-dash only counts with a space, the way MySQL does) and `#`, to the end of the line
- block comments: `/* ... */`
- the operators `:=` and `::`

Scanned as code, because the server runs them:

- executable comments `/*! ... */`
- optimizer hints `/*+ ... */`

```plain
SELECT ':no', `:col`, 'it''s :x' -- :c
, :real # :d
/* :e */ FROM t
// one placeholder: :real

SET @x := :v, @y = 1::int
// one placeholder: :v

SELECT /*!50000 :a */ :b
// two placeholders: :a and :b
```

Mixing `?` and `:name` in one string is `.invalid`. A `:` that does not start a name (`a:1`, `x:`) is kept as it is. Names are `[A-Za-z_][A-Za-z0-9_]*`.

[Prepared statements](./statements.md) is what happens to this SQL on the server, whether you asked for a `Statement` or just passed values to `exec`.
