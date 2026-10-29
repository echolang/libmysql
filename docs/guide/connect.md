---
description: The MySQL URL, Options fields, a unix socket, and what a live session can still do.
---

# Connecting

A [](api:mysql::Connection) is one session with a server. You open it from a URL or from [](api:mysql::Options), you talk, you close it. One thread at a time. `#[atomic]` so a [pool](./pool.md) can hand it from one thread to the next.

```echo
mysql::Connection $db = guard mysql::Connection::open(
    'mysql://app:secret@127.0.0.1/shop',
);
```

`$db->server` is the version string. `$db->id` is what `KILL` takes.

## The URL

`Options::parse` reads `mysql://user:password@host:port/database?...`. User, password, and database are percent-decoded. The last `@` ends the user info, so a password written without escaping its `@` still works:

```plain
mysql://app:p@ss@db:3307/shop
// user app, password p@ss, host db, port 3307, database shop
```

An IPv6 host goes in brackets, the way a URL always does:

```plain
mysql://u@[::1]:3310/db
// host ::1, port 3310
```

No scheme other than `mysql://` parses. A broken percent-escape, a port of 0, a port past 65535, an IPv6 host without its `]`: all `.invalid`.

### Query keys

Every key `parse` knows, and the format it wants:

| Key | Format | Default |
|:--|:--|:--|
| `socket` | a path, percent-decoded | unset, so TCP |
| `timeout` | `250ms`, `5s`, `2m`, or a bare number of seconds | none, wait as long as it takes |
| `connectTimeout` | the same duration grammar | 10 seconds |
| `multiStatements` | `true` / `false` / `1` / `0` | `false` |
| `foundRows` | the same flag grammar | `false` |
| `fetchServerKey` | the same flag grammar | `false` |
| `statementCache` | a number | 64 |
| `maxPacket` | a number, not 0 | 64 MiB |
| `collation` | 0..255 | 45 (`utf8mb4_general_ci`) |

Unknown keys, a duration that is not one of those, `maxPacket=0`, `collation=256`: `.invalid`. Empty pairs (`&&`) are skipped. `serverKey` is not a URL key; it is an [](api:mysql::Options) field you set after parsing.

## Options

[](api:mysql::Options) is plain data. Fields with defaults, set by name at construction or by assignment:

```echo
mysql::Options $o = mysql::Options(
    $user: 'app',
    $password: 'secret',
    $database: 'shop',
);
$o->socket = '/tmp/mysql.sock';
$o->timeout = time::duration::secs(10);

mysql::Connection $db = guard mysql::Connection::open($o);
```

The fields, with the defaults `parse` leaves alone when the URL does not name them:

- `host` is `127.0.0.1`, `port` is 3306, `user` is `root`, `password` is empty, `database` is unset.
- `socket`, when set, is the path. `host` and `port` are then not used. That is the local path: the password never crosses the network.
- `connectTimeout` (10 seconds) bounds connecting and logging in, together. [Deadlines](./deadlines.md) has how the rest of the calls pick theirs.
- `timeout` is how long one command may take when the call names no deadline of its own. Null waits as long as it takes.
- `collation` is 45, `utf8mb4_general_ci`, which MySQL 5.7, 8 and 9 and MariaDB all know.
- `maxPacket` is 64 MiB, the largest payload accepted from the server or sent to it.
- `multiStatements` is off. Turn it on when you mean it: it is what turns an injection into a second statement.
- `serverKey` and `fetchServerKey` belong to [authentication](./auth.md).
- `statementCache` is 64. [Prepared statements](./statements.md) is where that number matters.

## After login

`$db->alive()` is whether the socket is still open. It does not talk to the server. `ping` does:

```echo
guard $db->ping() else ($e) {
    die("gone: {$e}");
}
```

`reset` rolls back, drops temporary tables, user variables and prepared statements, as if newly connected, without logging in again. The statement cache goes with them, because the server dropped every statement.

`database($name)` is what `USE` does: make `$name` the default schema.

`close` says goodbye and closes. Safe to call twice. Dropping a connection that is still alive sends `COM_QUIT` first, unless a stream is still open on it.

## One thread at a time

A connection is `#[atomic]`, so a pool can move it between threads. It is still one session: two threads talking on it at once will mix their packets. The pool's job is to not hand it out twice. Yours, if you hold it yourself, is to use it from one thread at a time.

[Authentication](./auth.md) is what happens inside `open`, and why a unix socket is the local default I would pick.
