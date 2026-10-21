# Maintaining Zymfonix IDE

The goal is minutes per month. Everything heavy runs on GitHub Actions.

## The routine

1. **An "Update upstream" pull request appears** (opened by `check-upstream.yml`, daily at 05:17 UTC, or on demand: Actions > Check upstream > Run workflow). It bumps `upstream.json` to the newest stable VSCodium release and the Code - OSS version it builds.
2. **Wait for CI on the PR to pass.** CI applies all VSCodium patches and every Zymfonix edit to the new Code - OSS sources (a few minutes). If it fails, see "When something breaks".
3. Glance at the PR's list of changed VSCodium files. If `publish-stable-macos.yml` / `publish-stable-linux.yml` changed, compare their runner and container images and setup steps with `.github/workflows/build.yml`.
4. Optional but cheap insurance: Actions > **Build** > Run workflow, branch = the PR branch (about 2 to 3 hours, no publishing).
5. **Merge the PR.** Nothing is published yet.
6. **Release:** Actions > **Release** > Run workflow on `main`, leave the version empty. It picks the next version (e.g. `1.140.001`, then `1.140.002` for a rebuild of the same Code - OSS), builds macOS arm64 + x64 and Linux x64, verifies every asset, and publishes the GitHub Release only if everything succeeded. Alternatively push a tag: `git tag v1.140.001 && git push origin v1.140.001`.
7. Tell users a new version is on the Releases page. Installed copies do not update themselves.

Releasing is independent of upstream updates: you can release a branding or packaging fix for the same Code - OSS version (next revision), and you can merge several upstream updates before releasing.

## When something breaks

Every step fails loudly with a message saying which file or check is involved. Typical cases:

| Failure | Meaning | Fix |
| --- | --- | --- |
| `edit-text: expected 1 occurrence(s) in <file>` | VSCodium or Code - OSS reworded text we replace | Look at the file in `.build/vscodium/` (run `scripts/dry-run-prepare.sh`), update the matching line in `scripts/apply-overlay.sh` or `scripts/post-prepare.sh` |
| `failed to apply patch` during the dry run | VSCodium's own patches do not apply; should not happen for a VSCodium release | Wait for the next VSCodium release, or pin the previous one |
| `upstream has a document icon we did not regenerate` | Code - OSS added a file type icon | Run `branding/build-icons.sh` on a Mac and commit `overlay/` |
| `check-product: ... FAILED` | Final product.json lost a Zymfonix identifier, or gained an update URL / Marketplace / VSCodium reference | Find which upstream change caused it; fix `branding/product.json` or the edits |
| A build job fails in npm/gulp/compile | Usually a runner/toolchain change | Compare `build.yml` with VSCodium's workflows at the pinned tag; re-run once in case it was transient |
| `verify-*.sh` reports `FAIL` | The built app is not what we expect (icon, IDs, launcher, apt repo guard, version) | Treat as a real bug; the release is not published |
| Release job: `release v... already exists` | That version is taken | Use the next revision |

A failed release leaves at most a **draft** release (never a published one). Delete the draft (Releases page) and, if the run was started by a tag, the tag (`git push --delete origin v<version>`), then fix and release again.

To try things locally without a multi-hour build: `scripts/lint.sh` and `scripts/dry-run-prepare.sh --os osx` (`--os linux` needs GNU sed, e.g. in a Linux container).

## Things to know

- **One place for versions:** `upstream.json`. Do not edit VSCodium or Code - OSS files directly; `.build/` is disposable and recreated by every build.
- **One place for each kind of change:** names and IDs in `branding/product.json`; icons via `branding/build-icons.sh` into `overlay/`; VSCodium settings in `scripts/lib.sh`; text edits in `scripts/apply-overlay.sh` (VSCodium scripts) and `scripts/post-prepare.sh` (Code - OSS tree).
- **Release asset names** are defined once, in `scripts/lib.sh` (`expected_assets`); packaging, verification and the release gate all use them.
- **Third-party build dependencies** (all public, no credentials): VSCodium's Linux build image `vscodium/vscodium-linux-build-agent:focal-x64` and the pkgforge-dev Arch Linux image + `anylinux-setup-action` for the AppImage, exactly as VSCodium's own workflows use them. GitHub Actions are pinned to commit SHAs copied from VSCodium's workflows.
- **No secrets are used.** Workflows only use the automatic `GITHUB_TOKEN`, with read-only permissions except where a job publishes a release or opens the update PR.
- **Repository settings needed once:** Settings > Actions > General > Workflow permissions: allow GitHub Actions to create and approve pull requests (for the update PR). GitHub pauses scheduled workflows in repositories with no activity for 60 days; re-enable "Check upstream" in the Actions tab if that happens.
- **Cost:** on a public repository GitHub-hosted runners are free. On a private repository, a full build uses roughly 5 to 6 hours of runner time, most of it on macOS runners, which are billed at a higher rate.
- **Signing later (optional):** with an Apple Developer ID you could sign and notarize instead of ad-hoc signing (VSCodium's `build/osx/prepare_assets.sh` shows how). Not needed for internal use.
- **In-app auto-update (optional, not implemented):** VSCodium's updater can read a JSON feed (`updateUrl`). Doing this properly means publishing that feed for every release and platform and is deliberately left out; manual updates from GitHub Releases are the supported path.
