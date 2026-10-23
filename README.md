# libmysql

MySQL for Echo, in Echo. A session with a server, named placeholders, rows you can read in place, and a pool.

- `query` when you want the rows. `exec` when you want `affectedRows`. `stream` when you cannot hold the result.
- `?` positional, `:name` in a map.
- Read a row in place. Nothing is decoded until you ask for the column.
- Prepared SQL stays on the connection. Same SQL next time is execute only.
- A transaction rolls back if you drop it.
- A `Pool` shares connections across threads. A lease goes back when dropped.
- `batch` when `CALL` or several statements return more than one result.
- MySQL 8 login works, RSA-OAEP included. Clear-text passwords only on a unix socket.

The [guide](https://echolang.github.io/libmysql/guide/) is the same walk with more of the catches. The [API](https://echolang.github.io/libmysql/api/) is generated from the public comments.

## Installation

From your project directory:

```bash
epm add echolang/libmysql --git https://github.com/echolang/libmysql --range ^0.1
```

That writes a `#[requires:]` line and vendors the sources. libtcp and libcrypto come along as requires. Echo sees the `mysql` namespace as soon as the module loads. There is no C of its own.

## Quick start

Open, `exec`, `query`, close:

```echo
mysql::Options $options = guard mysql::Options::parse('mysql://root@127.0.0.1/shop') else ($e) {
    die("{$e}");
}
$options->fetchServerKey = true;

mysql::Connection $db = guard mysql::Connection::open($options) else ($e) {
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
) else ($e) {
    die("{$e}");
}
foreach ($rows as $row) {
    int64 $stock = $row['stock']->int() ?? 0;
    echo "{$row['name']}: {$stock} in stock";
}

$db->close();
```

`exec` is the statement that returns no rows. `query` buffers the result. A URL is enough for `Connection::open` too; `Options` is the same thing when you want to set a field after parsing.

Here is the catch: a fresh MySQL 8 over TCP has an empty `caching_sha2_password` cache, so the first login takes the full RSA path. `fetchServerKey` asks the server for its public key. Off by default, same as MySQL's own clients: over plain TCP the key itself could be swapped by someone in between. A unix socket does not need this.

## Connecting

A URL names the server: `mysql://user:password@host:port/database?...`. User, password, and database are percent-decoded. Query keys: `socket`, `timeout`, `connectTimeout` (`250ms`, `5s`, `2m`), `multiStatements`, `fetchServerKey`, `statementCache`, `maxPacket`, `collation`.

```echo
mysql::Connection $db = guard mysql::Connection::open('mysql://app:secret@127.0.0.1/shop') else ($e) {
    die("{$e}");
}
```

`Options` is plain data. Fields with defaults, set by name at construction or by assignment:

```echo
mysql::Options $o = mysql::Options($user: 'app', $password: 'secret', $database: 'shop');
$o->socket = '/tmp/mysql.sock';
$o->timeout = time::duration::secs(10);

mysql::Connection $db = guard mysql::Connection::open($o) else ($e) {
    die("{$e}");
}
```

When `socket` is set, `host` and `port` are not used. That is the local path: no TLS, and the password never crosses the network.

Clear-text only over a unix socket. Full caching_sha2 or sha256 over TCP needs `Options->serverKey` (PEM), or `fetchServerKey`.

`$db->server` is the version string. `$db->id` is what `KILL` takes. One thread at a time. It is `#[atomic]` so a pool can hand it from one thread to the next.

## Queries

`query` reads the whole result into a `ResultSet`. `exec` is the same command when you only care what it did: `affectedRows`, `lastInsertId`, `warnings`. `stream` is the one that does not buffer.

```echo
mysql::ResultSet $rows = guard $db->query('SELECT name, price FROM products') else ($e) {
    die("{$e}");
}

mysql::Outcome $sold = guard $db->exec('UPDATE products SET stock = stock - 1 WHERE name = ?', ['Lamp']) else ($e) {
    die("{$e}");
}
echo "touched {$sold->affectedRows}";
```

Values in the call mean a prepared statement. The connection keeps the ones it has seen (`Options->statementCache`, 64 by default) so the next `exec` of the same SQL is just an execute. `prepare` is when you want the `Statement` in your hand, to run many times with different params and close it yourself.

`batch` is every result of a multi-statement query, or a `CALL` that returns several. It needs `Options->multiStatements` for more than one statement, and that flag is off by default: it is what turns an injection into a second statement.

## Params

Write them as a literal where the params go. An array for `?`, a map for `:name`. A literal holds one value just as well: `['Lamp']`.

```echo
$db->exec('INSERT INTO products (name, price, stock) VALUES (?, ?, ?)', ['Desk', .decimal('10.00'), 3]);
$db->exec('INSERT INTO products (name, price, stock) VALUES (:name, :price, :stock)', [
    'name'  => 'Lamp',
    'price' => .decimal('49.90'),
    'stock' => 12,
]);
```

To keep going after the literal, start a chain with `.of([...])` or `.named([...])` and add to it. Code that builds params in a loop starts from an empty one:

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

A `DECIMAL` stays a decimal, as the server wrote it, so nothing is rounded. Integers, floats, bools, strings, and dates convert on the way in. An Echo `null` is SQL NULL:

```echo
string? $note = null;
$db->exec('UPDATE products SET note = :note WHERE name = :name', ['note' => $note, 'name' => 'Rug']);
```

Mixing `add` and `set` on one `Params` is `.invalid`. A value with no placeholder, or a placeholder with no value, is too. The count has to match.

## Rows

`$row['name']` and `$row[0]` read a value. `foreach ($row as $name => $value)` walks them. Typed reads answer null when the value is not that type, so `??` does the rest:

```echo
foreach ($rows as $row) {
    int64 $stock = $row['stock']->int() ?? 0;
    echo "{$row['name']}: {$row['price']} ({$stock} in stock)";
}
```

`$row['price']` interpolates as the server sent it. A DECIMAL stays a string of digits. `int()`, `uint()`, `float()`, `text()` are the typed reads. `isNull()` is SQL NULL.

A name the result does not have stops the program, in a release build too: it is a mistake in the code, not in the data. `get` is the lookup that cannot stop.

`$rows[0]` is the first row of a `ResultSet`. Past the last row stops the same way. `first()` answers null when there are none.

## Stream

A result too big to hold: rows one at a time. While it is open the connection answers `.busy`. Reaching the end, `finish()`, or dropping it frees the connection again.

`foreach` (or `next()`) hands out each row decoded whole:

```echo
mysql::Rows $stream = guard $db->stream('SELECT id, name, note FROM products ORDER BY id') else ($e) {
    die("{$e}");
}
foreach ($stream as $row) {
    string $note = $row['note']->text() ?? '-';
    echo "#{$row['id']} {$row['name']} {$note}";
}
guard $stream->finish() else ($e) {
    die("{$e}");
}
```

`finish` is also where a `foreach` error shows up: iteration cannot hand one back, so you ask after.

`step` with `view` reads the row in place, column by column. Nothing is decoded until it is asked for. Code that maps rows onto its own types finds each column once, then reads by position:

```echo
mysql::Rows $raw = guard $db->stream('SELECT name, stock FROM products ORDER BY id') else ($e) {
    die("{$e}");
}
usize $stockAt = $raw->columns()->find('stock') ?? 0;
int64 $units = 0;
while (true) {
    bool $more = guard $raw->step() else ($e) {
        die("{$e}");
    }
    if (!$more) {
        break;
    }
    $units = $units + ($raw->view()->int($stockAt) ?? 0);
}
```

The view holds until the next move. A position past the last column stops the program.

## Transactions

`$db->transaction(...)` runs the work, commits on `.ok`, rolls back on `.error` (and hands that error on):

```echo
guard $db->transaction(function(mysql::Connection $tx) : status<mysql::Error> {
    guard $tx->exec('UPDATE products SET stock = stock - 1 WHERE name = ?', ['Chair']) else ($e) {
        return .error($e);
    }
    guard $tx->exec('UPDATE products SET note = ? WHERE name = ?', ['last one soon', 'Chair']) else ($e) {
        return .error($e);
    }
    return .ok;
}) else ($e) {
    die("transaction: {$e}");
}
```

The generic form hands back a value: `transaction<T>(function(Connection) : result<T, Error>)`.

`begin()` if you want the handle. `commit()` makes it stick. Dropping a `Transaction` without a commit rolls it back, so a `guard ... else { return ... }` cannot leave one half done.

## Pool

Connections shared by many threads. `query`, `exec`, and `transaction` take a lease around one call:

```echo
mysql::Pool $pool = mysql::Pool($options, mysql::PoolOptions($max: 4));
mysql::ResultSet $count = guard $pool->query('SELECT COUNT(*) AS n FROM products') else ($e) {
    die("{$e}");
}
echo "the pool counts {$count[0]['n']} products";
$pool->close();
```

`acquire` lends one out as a `Lease`. It goes back when dropped, or at `release()`. A thread that finds every connection lent out waits its turn: first come, first served.

A lease dropped mid-transaction is rolled back, so the next borrower does not inherit it. A dead, busy, too old, or surplus connection is closed instead of lent. An idle one older than `pingAfterIdle` is pinged first.

`.exhausted` when none came free before the deadline. `PoolOptions` defaults: 10 connections, 10 idle, 10 minutes idle, 30 seconds to acquire.

## Errors

Every call that can fail returns `result<T, Error>` or `status<Error>`. `guard` is the short way through. `"{$e}"` is the sentence. `name()` is the case without a match: `'server'`, `'timeout'`, and so on.

```echo
result<mysql::Outcome, mysql::Error> $again = $db->exec(
    'INSERT INTO products (name, price, stock) VALUES (?, 1, 1)',
    ['Lamp'],
);
if ($again->failed() && $again->failure()->is(.dupEntry)) {
    echo 'Lamp is already there';
}
```

`$e->is(.dupEntry)` is the server's code. `$e->retryable()` is a deadlock or a lock wait timeout, where the server rolled the statement (or the transaction) back. `$e->state()` is the five-character SQLSTATE (`23000`, `40001`), or null when the error did not come from the server.

| Case | Means |
|---|---|
| `server` | the server refused the command, with its code and message |
| `transport` | the socket failed: refused, reset, closed by the peer |
| `timeout` | the deadline passed first |
| `closed` | the connection is closed, or an earlier failure left it unusable |
| `busy` | a streaming result is still open on this connection |
| `auth` | login failed on this side (unsupported plugin, needs a key, ...) |
| `malformed` | the server sent something that does not parse |
| `tooLarge` | a packet over `Options->maxPacket` |
| `localInfile` | the server asked for a local file, which this client never sends |
| `invalid` | the call could not be made as written |
| `exhausted` | no pooled connection came free in time |

A timeout in the middle of a command closes the connection. What the server still sends could not be told apart from the next answer. An error packet from the server, or a refused local file, ends the command and the connection is ready again.

## Timeouts

Every call takes `by:`. The one it named, else `Options->timeout` from now, else never. `connectTimeout` (10 seconds) bounds connecting and logging in, together.

```echo
mysql::ResultSet $rows = guard $db->query('SELECT 1', by: tcp::Deadline(ms: 500)) else ($e) {
    die("{$e}");
}
```

## What is not here

These are deliberate.

- **TLS.** Plain TCP, or a unix socket, or a tunnel in front. The auth catch above is why a unix socket is the local default I would pick.
- **`LOAD DATA LOCAL INFILE`.** The server asks, this client sends an empty packet and answers `.localInfile`. It never reads a local file for the server.
- **`multiStatements`.** Off. Turn it on when you mean it.
- **libmysqlclient.** The protocol is Echo over libtcp.

## Working here

```bash
echoc test
```

No server. Protocol, params, rows, errors, the pool's queue. Against a real one:

```bash
scripts/test-live.sh                          # mysql:8.0 in Docker
IMAGE=mysql:8.4 scripts/test-live.sh
IMAGE=mariadb:11 scripts/test-live.sh
```

`examples/shop.eco` is the tour this page was cut from. `MYSQL_URL` overrides the default:

```bash
MYSQL_URL=mysql://root@127.0.0.1/shop echoc run -m examples
```

## License

MIT. Copyright Mario Döring.
