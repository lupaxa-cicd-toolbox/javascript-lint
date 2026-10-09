<p align="center">
    <a href="https://github.com/lupaxa-cicd-toolbox">
        <img src="https://raw.githubusercontent.com/the-lupaxa-project/brand-assets/master/logos/organisations/cicd-toolbox/readme-logo.png" alt="Organisation Logo" />
    </a>
</p>

<h1 align="center">JavaScript Lint</h1>

## Overview

A tool to lint your JavaScript files using [standard](https://github.com/standard/standard).

This tool has been tested against the following:

1. GitHub Actions
2. Travis CI
3. CircleCI
4. BitBucket pipelines
5. Local command line

Because it is a plain Bash script, it should work on most CI platforms where you can run arbitrary commands.

## Basic Usage

### GitHub Actions

```yaml
on: [push, pull_request]

jobs:
  build:
    name: JavaScript Lint
    runs-on: ubuntu-latest

    steps:
      - name: Checkout the Repository
        uses: actions/checkout@v4
      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: "22"
      - name: Run JavaScript Lint
        run: bash <(curl -s https://raw.githubusercontent.com/lupaxa-cicd-toolbox/javascript-lint/master/src/pipeline.sh)
```

### Local

```bash
./src/pipeline.sh
```

Or without cloning:

```bash
bash <(curl -s https://raw.githubusercontent.com/lupaxa-cicd-toolbox/javascript-lint/master/src/pipeline.sh)
```

## Configuration Options

The following environment variables customise the script:

| Variable         | Default                                    | Purpose                                            |
| ---------------- | ------------------------------------------ | -------------------------------------------------- |
| `INCLUDE_FILES`  | `(empty)`                                  | Comma-separated path regexes to force-include      |
| `EXCLUDE_FILES`  | `node_modules/.*\|dist/.*\|coverage/.*`    | Comma-separated path regexes to skip               |
| `NO_COLOR`       | `false`                                    | Disable colour output                              |
| `REPORT_ONLY`    | `false`                                    | Report results but always exit 0                   |
| `SHOW_ERRORS`    | `true`                                     | Show detailed errors for failed files              |
| `SHOW_FILTERED`  | `false`                                    | Show files skipped by exclude rules                |
| `SHOW_UNMATCHED` | `false`                                    | Show files that matched neither pattern            |
| `SCAN_ROOT`      | script default                             | Override scan directory without editing the script |

> **Note:** If you set `INCLUDE_FILES`, only matching paths are scanned (everything else is skipped, including paths that would match `EXCLUDE_FILES`). Set `EXCLUDE_FILES` to empty to scan `node_modules`, `dist`, and `coverage`.

You can combine any of the settings above:

```yaml
on: [push, pull_request]

jobs:
  build:
    name: JavaScript Lint
    runs-on: ubuntu-latest

    steps:
      - name: Checkout the Repository
        uses: actions/checkout@v4
      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: "22"
      - name: Run JavaScript Lint
        env:
          REPORT_ONLY: true
          SHOW_ERRORS: true
        run: bash <(curl -s https://raw.githubusercontent.com/lupaxa-cicd-toolbox/javascript-lint/master/src/pipeline.sh)
```

## Example Output

```text
--------------------------------------------------------------------- Stage 1: Parameters --
 EXCLUDE_FILES: node_modules/.*|dist/.*|coverage/.*
---------------------------------------------------------- Stage 2: Install Prerequisites --
 [ OK ] standard is already installed
--------------------------------------------------------- Stage 3: Run standard (v17.1.2) --
 [ ✅ ] src/app.js
------------------------------------------------------------------------- Stage 4: Report --
 Total: 1 Passed: 1 Failed: 0 Filtered: 0 Unmatched: 0
----------------------------------------------------------------------- Stage 5: Complete --
```

## File Identification

JavaScript files are identified using the following code:

```shell
file -b "${filename}" | grep -qE 'node script'

AND

[[ ${filename} =~ \.(js|mjs|cjs|jsx)$ ]]
```

> **Note:** `file -b` has no JavaScript type. A Node shebang is reported as a node script. Other JavaScript sources are plain text, so `.js`, `.mjs`, `.cjs`, and `.jsx` are selected by name.

<a href="https://github.com/the-lupaxa-project">
    <img src="https://raw.githubusercontent.com/the-lupaxa-project/brand-assets/master/logos/components/footer-for-child-orgs.svg" alt="The Lupaxa Project Footer" width="100%" />
</a>
