# Markus

## Cursor Cloud specific instructions

### Current repository state

As of this writing, `Markus` is an empty scaffold: the only tracked files are
`README.md` (which contains just the title `# Markus`) and an MIT `LICENSE`.
There is **no application code, no dependency manifest, no build system, and no
tests** in the repository yet.

Because of this, there is currently:

- **Nothing to install** — no `package.json`, `requirements.txt`, `Package.swift`,
  lockfiles, or other dependency manifests exist. The environment update script
  is intentionally a no-op until real dependencies are added.
- **Nothing to lint / build / test / run** — no source code or scripts exist yet.

### Environment toolchains available

The base Cloud image already provides (no install needed):

- Node.js `v22.14.0` / npm `10.9.7`
- Python `3.12.3`
- git `2.43.0`

### What future agents should do once code lands

When application code and a dependency manifest are added, update the Cloud
environment accordingly:

- Set the environment **update script** to the project's dependency-install
  command (for example `npm ci` for a Node app with a lockfile, or
  `pip install -r requirements.txt` for Python). Keep it minimal and idempotent.
- Record the real lint / test / build / run (dev) commands here, or point to the
  canonical source once it exists (`package.json` scripts, a `Makefile`, etc.).

> Note: this project's owner works primarily on macOS, iOS, and web apps for
> photo imaging and metadata. A native macOS/iOS (Swift) target cannot be built
> or run inside this Linux Cloud VM; only web/backend components (e.g. Node,
> Python) can be exercised here.
