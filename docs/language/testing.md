← [Language guide](README.md)

# Tests

Tests are written next to the code they check, as `test` blocks, and run with `cshiftc test`:

```csharp
namespace Stats;

(int Min, int Max) MinMax(int[] values) { ... }

test "MinMax finds both ends"
{
    var (lo, hi) = MinMax([3, 1, 7]);
    Assert.Equal(1, lo);
    Assert.Equal(7, hi);
}
```

```text
$ cshiftc test
ok    MinMax finds both ends
FAIL  Positive rejects zero  (src/stats.cshift:41)
      panic: Assert.Equal failed: expected 0, got 1
        at <stdlib>/assert.cshift:53:26 in Assert.Equal<int32>
        called from src/stats.cshift:44:12 in test "Positive rejects zero"

1 passed, 1 failed
```

## `test` blocks

`test "name" { ... }` is a declaration at the top level of any source file, beside functions and structs. The name says
what the test checks; the body is code like the body of a function. It sees what a function of its file sees: the functions and types of its namespace and of its `using`s (private
members of structs, `_name`, stay private to their struct).

A test fails when

* a check fails (`Assert.Equal(1, lo)`, see below),
* anything else panics (an index out of range, an overflow, `Dictionary.Get` with a missing key, ...), or
* it ends with an error: the body is an `Error<void>` function, so `try` can be used in it, and an error that reaches
  its end fails the test (the report shows where the error came from).

```csharp
test "the configuration loads"
{
    var config = try LoadConfig("tests/data/config.json");   // an error fails the test
    Assert.Equal("dark", config.Theme);
}
```

`test` is a keyword only there (before a string, at the top level); everywhere else it is an ordinary name.

## `cshiftc test`

`cshiftc test` builds the tests of the project (or of the files it is given) into one program and runs **every test
in a process of its own**, so a panic ends only its test and the others still run. It reports each test with `ok` or
`FAIL`; for a failed test the place of the test, the panic or the error, and what the test wrote to the console. The
exit code is 0 when all tests passed and 1 otherwise, so the command fits a CI script as it is.

```text
cshiftc test                       the project in the current directory (or above)
cshiftc test path/to/project
cshiftc test file.cshift [...]     single files
cshiftc test --filter MinMax       only the tests whose name contains the text
```

The test program is built in `obj/`. A test build leaves the program's `Main` out (the tests are the entry points), so
library projects can have tests too. A normal build (`cshiftc build`, `run`, `publish`) leaves the tests out: they cost
nothing in the program, and code that only the tests use is not compiled. `cshiftc check` and the editor check the
tests like the rest of the code.

Tests run on the computer that builds them; a project for another target (`--target`, the wasm or m68k backend) is
not tested this way.

## Checks: `Assert`

The checks are functions of the namespace `Assert` in the standard library. A failed check panics with what was
expected; the panic shows the line of the test that made the check.

| Check | Fails when |
|---|---|
| `Assert.True(condition)`, `Assert.True(condition, message)` | `condition` is false |
| `Assert.False(condition)`, `Assert.False(condition, message)` | `condition` is true |
| `Assert.Equal(expected, actual)` | `!(expected == actual)`: numbers, strings, enums, [tuples](tuples.md), ... |
| `Assert.NotEqual(notExpected, actual)` | the two are equal |
| `Assert.Near(expected, actual, tolerance)` | two floating-point numbers differ by more than `tolerance` |
| `Assert.Fail(message)` | always (a branch that must not be reached) |

`Assert.Equal` compares with `==` and writes both values into its message (as `$"{value}"` does). Structs have no
`==` (tuples aside), so their fields are compared one by one, or several values at once as a tuple:
`Assert.Equal((1, 7), MinMax(values))`.

The checks are ordinary functions: in a program (outside of tests) a failed check is a panic like any other.
