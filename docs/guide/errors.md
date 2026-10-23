---
description: The Error cases, ServerError, ErrorCode, SQLSTATE, retryable, and which failures close the connection.
---

# Errors

Echo has no exceptions, so a failed call comes back as a value. `query` answers `result<ResultSet, Error>`, `exec` answers `result<Outcome, Error>`, `ping` answers `status<Error>`. [](api:mysql::Error) is the reason nothing came back.

```echo
mysql::ResultSet $rows = guard $db->query($sql) else ($e) {
    die("query failed: {$e}");
}
```

`"{$e}"` is the sentence. `$e->message()` is the same string. `$e->name()` is the case without a match: `'server'`, `'timeout'`, and so on.

## guard and match

Omit `else` and the crash hook stops. Write `else` to name the failure, as above, or to `match` on it. `Error` is an enum, so the cases read like any other:

```echo
guard $db->exec($sql) else ($e) {
    match ($e) {
        .timeout => {
            die('too slow');
        },
        .server($s) => {
            die("{$s->code->value()}: {$s->message}");
        },
        else => {
            die("{$e}");
        },
    }
}
```

Without the `guard`, the `result` has the usual methods. `$e->is(.dupEntry)` is the one I actually write for a duplicate key:

```echo
result<mysql::Outcome, mysql::Error> $again = $db->exec(
    'INSERT INTO products (name, price, stock) VALUES (?, 1, 1)',
    ['Lamp'],
);
if ($again->failed() && $again->failure()->is(.dupEntry)) {
    echo 'Lamp is already there';
}
```

## What each case means

| Case | Means |
|:--|:--|
| `server` | The server refused the command, with its code and message. |
| `transport` | The socket failed: refused, reset, closed by the peer. |
| `timeout` | The deadline passed first. |
| `closed` | The connection is closed, or an earlier failure left it unusable. |
| `busy` | A streaming result is still open on this connection. |
| `auth` | Login failed on this side (unsupported plugin, needs a key, ...). |
| `malformed` | The server sent something that does not parse. |
| `tooLarge` | A packet over `Options->maxPacket`. |
| `localInfile` | The server asked for a local file, which this client never sends. |
| `invalid` | The call could not be made as written: a value without a placeholder, a URL that does not parse. |
| `exhausted` | No pooled connection came free in time. |

[Authentication](./auth.md) owns the `auth` cases. [Pool](./pool.md) owns `exhausted`. `invalid` is yours: the SQL and the params do not match, or the URL is not one.

## ServerError

`.server` carries a [](api:mysql::ServerError): the [](api:mysql::ErrorCode), the five character SQLSTATE, and the message. `$e->code()` and `$e->state()` read those, or null when the error did not come from the server.

`$e->is(.dupEntry)` is the named code. The codes a program branches on have names (`dupEntry`, `deadlock`, `lockWaitTimeout`, `noSuchTable`, ...). Every other one is `other` and still carries its number in `value()`.

`$e->state()` is `23000` for a duplicate key, `40001` for a deadlock, `HY000` for a lot of the rest. The same classes other servers use, so code that works with more than one can branch on it.

`$e->retryable()` is a deadlock or a lock wait timeout, where the server rolled the statement (or the transaction) back. [Transactions](./transactions.md) has the retry loop.

## Which failures close the connection

A command that failed partway through its answer has a leftover: the rest of the answer may still be on its way, and would be read as the answer to the next command. So the connection is closed.

Two failures do not have that leftover:

- An error packet from the server. The command is over. The connection is ready for the next one. This is how a duplicate key, a missing table, a deadlock look.
- A refused `LOAD DATA LOCAL INFILE`. This client sends an empty packet, reads the server's answer, and reports `.localInfile`. The command is over.

Everything else closes the connection: `timeout`, `transport`, `malformed`, `tooLarge`, a stream that stops in the middle of the rows. The next call on that handle fails `.closed`. A pool will not take it back onto the idle list.

That is the `abandon` rule. You do not call it. You see it as "a duplicate key is recoverable on this connection, a timeout is not."

[What isn't here](./limits.md) is the rest of the deliberate no's, the servers this is tested against, and the examples.
