---
description: Install libmysql, open a session, write a row, and read it back.
---

# Getting started

You want a MySQL session from Echo, and you don't want to write the protocol to get one. This library is that session: the handshake, the plugins, the text and binary protocols, written in Echo over libtcp. Hashes and randomness come from libcrypto.

The namespace is `mysql`. Echo sees it as soon as the module loads.

## Install it

From your project directory:

```bash
epm add echolang/libmysql --git https://github.com/echolang/libmysql --range ^0.1
```

That writes a `#[requires:]` line and vendors the sources. libtcp and libcrypto come along as requires. There is no C of its own.

## A complete pass

Let's talk to a server, so the rest of the page has somewhere to sit. [](api:mysql::Options::parse) reads a URL. [](api:mysql::Connection::open) logs in. `exec` is the statement that returns no rows. `query` buffers the ones that do.

```echo
mysql::Options $options = guard mysql::Options::parse(
    'mysql://root@127.0.0.1/shop',
);
$options->fetchServerKey = true;

mysql::Connection $db = guard mysql::Connection::open($options)
    else ($e) {
    die("connect: {$e}");
}
```

A URL is enough for `Connection::open` too. `Options` is the same thing when you want to set a field after parsing. `fetchServerKey` is the catch a fresh MySQL 8 over TCP hits: the `caching_sha2_password` cache is empty, so the first login takes the full RSA path. [Authentication](./auth.md) has why it defaults to false.

Now a table, then a row:

```echo
guard $db->exec('DROP TABLE IF EXISTS products');
guard $db->exec('CREATE TABLE products (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    note VARCHAR(200) NULL,
    price DECIMAL(10,2) NOT NULL,
    stock INT NOT NULL,
    added DATETIME DEFAULT CURRENT_TIMESTAMP
)');
```

`exec` with a map literal binds `:name` placeholders. The [](api:mysql::Outcome) is what the statement did: how many rows it touched, and the id an `AUTO_INCREMENT` column handed out.

```echo
mysql::Outcome $lamp = guard $db->exec(
    'INSERT INTO products (name, price, stock) VALUES (:name, :price, :stock)',
    [
        'name'  => 'Lamp',
        'price' => .decimal('49.90'),
        'stock' => 12,
    ],
) else ($e) {
    die("insert: {$e}");
}
echo "inserted lamp as #{$lamp->lastInsertId}";
```

A `DECIMAL` stays a decimal, as the server wrote it, so nothing is rounded. [Values and types](./values.md) has the rest of that mapping.

`query` answers a [](api:mysql::ResultSet). `$row['col']` reads a [](api:mysql::Value). Typed reads answer null when the value is not that type, so `??` does the rest:

```echo
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

So, what happens if this fails? `query` and `exec` answer `result<T, Error>`. Omit `else` and the crash hook stops. Write `else` to recover, to match, or to name the failure: `die("connect: {$e}")`. A duplicate key is an error you can name, `$e->is(.dupEntry)`, and [Errors](./errors.md) has the rest.

The same program is `examples/shop.eco`. It also writes a multi-row insert, streams the table, reads a column in place, and runs a transaction. `MYSQL_URL` overrides the default:

```bash
MYSQL_URL=mysql://root@127.0.0.1/shop echoc run -m examples
```

## Where to go next

- **Connecting** is the URL, [](api:mysql::Options), a unix socket, and what the session can still do after login.
- **Queries** is `query`, `exec`, `batch`, and the [rows](./queries.md) that come back.
- **Parameters** is `?` and `:name`, and [prepared statements](./statements.md) sit on top of that.
- **Streaming** is the result that does not fit in memory, and [reading in place](./rowview.md) is the cheap path through it.
