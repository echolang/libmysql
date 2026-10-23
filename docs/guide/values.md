---
description: The Value enum, the MySQL to Echo mapping, dates and times, and the typed-read crossover rules.
---

# Values and types

[](api:mysql::Value) is one column, and one parameter. The same shape whether it came over the text protocol or the binary one. The typed reads answer null when the value is not that type, so `guard`, `??` and `?->` do the rest.

```echo
mysql::Value $price = .decimal('49.90');
echo $price->text() ?? '';     // 49.90
echo $price->int();            // (null)
echo "{$price}";               // 49.90
```

A `DECIMAL` stays a decimal, as the server wrote it, so nothing is rounded. `float()` is the read that parses it (and rounds) to a float.

## The mapping

What the server reports, and the [](api:mysql::Value) case it becomes. The same table, both protocols.

| MySQL | Value |
|:--|:--|
| `NULL` | `none` |
| `TINYINT` .. `BIGINT`, `YEAR`, signed | `int` (`int64`) |
| the same, unsigned | `uint` (`uint64`) |
| `FLOAT`, `DOUBLE` | `float` |
| `DECIMAL` | `decimal` (digits, as the server wrote them) |
| `DATE` | `date` |
| `DATETIME`, `TIMESTAMP` | `datetime` |
| `TIME` | `time` |
| `CHAR`, `VARCHAR`, `TEXT`, `ENUM`, `SET`, `JSON` | `text` |
| `BINARY`, `VARBINARY`, `BLOB`, `BIT`, `GEOMETRY` | `bytes` |

JSON comes in the binary charset and is text all the same. `BIT` and `GEOMETRY` are bytes. A `BINARY` / `BLOB` column is bytes because its charset is binary; a `CHAR` / `TEXT` column is text.

On the way in, Echo values convert implicitly:

| Echo | Sent as |
|:--|:--|
| `int32`, `int64` | `int` |
| `uint32`, `uint64` | `uint` |
| `float64` | `float` |
| `bool` | `int`, 0 or 1 |
| `string` | `text` |
| `Date` / `DateTime` / `Time` | the matching case |
| `.decimal('49.90')` | `decimal` |
| `.bytes($blob)` | `bytes` |
| a nullable of any of the above, holding null | `none` (SQL NULL) |

A `uint` past `int64`'s range survives the trip: it is sent unsigned. A `bool` is an integer on the wire, which is what MySQL's `TINYINT(1)` already is.

## Dates and times

[](api:mysql::Date) is a DATE. Zero months and days are what MySQL stores for `0000-00-00`. `"{$d}"` is `YYYY-MM-DD`.

[](api:mysql::DateTime) is a DATETIME or a TIMESTAMP, to the microsecond. Zero dates parse. `"{$dt}"` is `YYYY-MM-DD HH:MM:SS`, with `.ffffff` when there are microseconds. `DateTime(midnight: $date)` is midnight on that date. `datetime()` on a `Value` also accepts a DATE, as midnight.

[](api:mysql::Time) is a TIME: a signed span that may pass 24 hours. MySQL allows up to 838:59:59, and a negative TIME is a thing. `"{$t}"` is `[-]HH:MM:SS`, with `.ffffff` when there are microseconds.

```echo
mysql::Date $d = guard Date::parse('0000-00-00');
mysql::Time $t = guard Time::parse('-838:59:59.5');
echo "{$t}";                   // -838:59:59.500000
```

`parse` answers null when the text is not one of those shapes. `10:61:00` is not a TIME. `2024-2-29` is not a DATE (it wants zero-padded months and days).

## Typed reads

Each read answers null for two reasons: the value is SQL NULL, and the value is not that type. `isNull()` tells the two apart.

```echo
mysql::Value $t = .text('12');
echo $t->int();                // (null)
echo $t->isNull();             // false

string? $note = null;
mysql::Value $n = $note;
echo $n->isNull();             // true
echo $n->text();               // (null)
```

The crossovers that do work:

- `int()` accepts a signed integer, or an unsigned one that fits in `int64`.
- `uint()` accepts an unsigned integer, or a signed one that is not negative.
- `float()` accepts a float, or any number: an integer, or a decimal parsed (and rounded) to a float.
- `text()` accepts text, a decimal as the server wrote it, or bytes as they are.
- `bytes()` accepts bytes, or text as its bytes.
- `bool()` accepts an integer: zero is false, anything else true.
- `datetime()` accepts a DATETIME, or a DATE at midnight.

A text `'12'` is not an int. That is the whole point of the typed reads: the column's type is the type, and a mismatch is null, not a conversion. `"{$v}"` is the other direction, the value as MySQL would print it, and `NULL` for NULL. Bytes print as they are.

`$v->kind()` is the case in a word: `null`, `int`, `text`, and so on.

[Streaming](./streaming.md) is how those values arrive when the result does not fit in memory.
