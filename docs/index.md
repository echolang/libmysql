---
layout: home
hero:
  name: libmysql
  text: MySQL for Echo
  tagline: MySQL for Echo, in Echo. No C underneath. A session with a server, named placeholders, rows you can read in place, and a pool that ages connections out.
  actions:
    - theme: brand
      text: Get started
      link: /guide/
    - text: API reference
      link: /api/
features:
  - title: Pure Echo
    details: The handshake, the plugins, the text and binary protocols. Hashes from libcrypto, sockets from libtcp. Open a URL and you have a session.
    link: /guide/connect
  - title: Placeholders you can read
    details: An array for ?, a map for :name. The SQL scanner leaves quotes, comments, := and :: alone, so the names in the query are the names you bind.
    link: /guide/params
  - title: Rows without copies
    details: stream plus step plus view reads a column from the packet it arrived in. Decode what you ask for. The rest costs a pass that finds where each value starts.
    link: /guide/rowview
  - title: A pool that ages connections
    details: Idle ones get pinged. Old ones get closed. A lease dropped mid-transaction rolls back, so the next borrower does not inherit it.
    link: /guide/pool
---

You want a MySQL session from Echo. This is that session: open, `exec`, `query`, close. Failures are values. A URL is enough.

```echo
mysql::Connection $db = guard mysql::Connection::open(
    'mysql://root@127.0.0.1/shop',
) else ($e) {
    die("connect: {$e}");
}

mysql::Outcome $lamp = guard $db->exec(
    'INSERT INTO products (name, price, stock) VALUES (:name, :price, :stock)',
    ['name' => 'Lamp', 'price' => .decimal('49.90'), 'stock' => 12],
) else ($e) {
    die("insert: {$e}");
}
echo "inserted lamp as #{$lamp->lastInsertId}";

mysql::ResultSet $rows = guard $db->query(
    'SELECT name, stock FROM products WHERE name = ?',
    ['Lamp'],
);
foreach ($rows as $row) {
    int64 $stock = $row['stock']->int() ?? 0;
    echo "{$row['name']}: {$stock} in stock";
}

$db->close();
```

That `guard` is the error handling. Omit `else` and the crash hook stops. Write `else` when you recover, match on the [reason](/guide/errors), or name the failure. [Getting started](/guide/) builds from there.

```bash
epm add echolang/libmysql --git https://github.com/echolang/libmysql --range ^0.1
```

It's all Echo. libtcp and libcrypto come along as requires. There is no C of its own.
