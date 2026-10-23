---
description: What this library doesn't do yet, the servers it talks to, how its tests are split, and the example program.
---

# What isn't here

This library covers one session with a MySQL server, done well. A few things that sit next to that are deliberately not built yet. Here's the list, so you don't go looking.

## Not here yet

- **TLS.** Plain TCP, or a unix socket, or a tunnel in front. The [auth catch](./auth.md#caching-sha2-fast-and-full) is why a unix socket is the local default I would pick.
- **`LOAD DATA LOCAL INFILE`.** The server asks, this client sends an empty packet and answers `.localInfile`. It never reads a local file for the server.
- **A query builder.** The SQL is yours. Named placeholders are the help this layer gives you. A builder belongs next to this, not inside it.
- **Record mapping.** `$row['name']` and `view()->int($at)` are the reads. Mapping those onto your types is a data mapper's job, and a data mapper is a separate library.
- **`stream` on the pool.** [Streaming](./streaming.md) holds the connection. [Pool](./pool.md) has `acquire()->db()` for that, and for `prepare` and `batch`.

`multiStatements` exists and is off. Turn it on when you mean it.

## Servers

MySQL 5.7, 8 and 9, and MariaDB. The protocol is 4.1, which all of them speak. CI runs `mysql:8.0`. The live tests also pass against 8.4 and MariaDB 11 when you point `IMAGE=` at them.

MariaDB does not speak `caching_sha2_password`. `mysql_native_password` is the one you get. The rest of the API is the same.

## Running the tests

```bash
echoc test
```

No server. Protocol, params, rows, errors, the pool's queue: a scripted peer on a socket, and a lot of pure Echo. Against a real one:

```bash
scripts/test-live.sh                          # mysql:8.0 in Docker
IMAGE=mysql:8.4 scripts/test-live.sh
IMAGE=mariadb:11 scripts/test-live.sh
```

One container at a time. The script sets `MYSQL_TEST_URL` (an ordinary user, on TCP) and `MYSQL_ROOT_URL` (root, for the tests that need to flush the auth cache, create users or kill a connection), then runs `echoc test --define mysql`.

A fresh server has an empty `caching_sha2_password` cache, so the first login takes the full RSA path. The live tests set `fetchServerKey`.

## The example

`examples/shop.eco` is the tour the [getting started](./index.md) page was cut from. It makes a table, writes to it three ways, reads it back three ways, and cleans up.

```bash
MYSQL_URL=mysql://root@127.0.0.1/shop echoc run -m examples
```
