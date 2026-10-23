---
description: The four plugins, caching_sha2 fast versus full auth, the server key, and what a failed login looks like.
---

# Authentication

`Connection::open` logs in. You pick the user and the password; the server picks the plugin. This client speaks four of them, by the name the server uses for each:

| Plugin | Server name |
|:--|:--|
| `cachingSha2` | `caching_sha2_password` |
| `native` | `mysql_native_password` |
| `sha256` | `sha256_password` |
| `clear` | `mysql_clear_password` |

`$db->plugin` is the one the login finished with. An unknown plugin at the handshake still gets a `caching_sha2_password` answer: the server switches to the user's real plugin when it differs.

There is no TLS yet. Plain TCP, or a unix socket, or a tunnel in front.

## caching_sha2, fast and full

MySQL 8's default. Two paths.

**Fast auth.** The client sends a scramble. The server has that scramble cached from a recent login, answers "yes", and the OK comes next. Cheap, and it is what a connection that reconnects often sees.

**Full auth.** The cache is empty (a fresh server, a flushed cache, a first login). The server wants the password itself. Over a unix socket it goes as it is. Over TCP it is XOR'd with the scramble and encrypted to the server's RSA public key (OAEP).

A unix socket does not need a key. Over TCP you need one of:

- `Options->serverKey`, the PEM of the server's public key, which you already have.
- `Options->fetchServerKey = true`, which asks the server for that key on the same socket.

`fetchServerKey` is off by default, same as MySQL's own clients: over plain TCP the key itself could be swapped by someone in between. A program that talks to a server on loopback, or through a tunnel, turns it on. `examples/shop.eco` does.

```echo
$options->fetchServerKey = true;
```

`sha256_password` is the same full-auth path without the cache: over TCP it always wants the key.

## Cleartext, sockets only

`mysql_clear_password` sends the password as it is. This client will only do that over a unix socket. Over TCP it fails on this side with `.auth(.needsSecureTransport)`, before the password leaves.

## Plugin switches

The greeting names a default plugin. The user's plugin can be a different one. The server then sends a switch packet with a fresh scramble, and login continues with that plugin. You do not pick this. If the switched-to plugin is one this client does not speak, the failure is `.auth(.unsupported($name))`.

## When login fails on this side

A refused password is a [](api:mysql::Error::server) packet, the same as any other command the server said no to. The cases below are the ones this client decides, as [](api:mysql::AuthError), before the server can say why:

| Case | Means |
|:--|:--|
| `unsupported` | The server asked for a plugin this client does not speak. |
| `needsSecureTransport` | `mysql_clear_password` over TCP. Connect over a unix socket. |
| `needsServerKey` | Full caching_sha2 or sha256 over TCP, and neither `serverKey` nor `fetchServerKey` is set. |
| `badKey` | The PEM could not be read, or the RSA step failed. |

`$e->name()` is `'auth'`. `"{$e}"` is the sentence, which already says what to set.

[Queries and results](./queries.md) is what you do once `open` has handed you a connection.
