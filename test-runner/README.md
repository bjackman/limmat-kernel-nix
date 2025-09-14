Simple single-node test runner. Runs test commands and aggregates results. This
runs locally on the target machine, so if the machine is broken it will just get
stuck. It basically serves to smooth over crap/inconsistent test interfaces, it
doesn't really solve much else about functional kernel testing.

It's configured by a JSON file like:

```json
{
    "suite": {
        "test": {
            "__is_test": true,
            "command": ["echo", "hello world"]
        }
    }
}
```

That is, an arbitrarily nested structure, where the leaves are marked with
`__is_test`. Then you use a dotted notation to identify the tests to run:

```sh
test-runner --test-config tests.json suite.test
```

You can specify multiple test identifiers as positional arguments. Globs are
supported.