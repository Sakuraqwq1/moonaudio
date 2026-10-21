# Publishing to mooncakes.io

The repository is ready to publish; the only steps that cannot be automated are
the account-bound ones.

## One-time setup

```bash
moon login            # opens a browser and links your GitHub account
```

`moon login` writes `~/.moon/credentials.json`. The account name must match the
package namespace in `moon.mod` (`Sakuraqwq1/moonaudio`); if your mooncakes
account uses a different login, change the namespace in `moon.mod` **and** in
every `moon.pkg` that imports a local package.

## Publish

```bash
moon check --deny-warn
moon test --deny-warn
moon info                 # make sure pkg.generated.mbti is committed
moon publish              # uploads 0.3.0
```

`moon publish` refuses to overwrite an existing version, so bump `version` in
`moon.mod` for every release.

## Release checklist

1. `CHANGELOG.md` has an entry for the version being published.
2. `moon.mod` `version`, `description`, `keywords`, `repository` and `readme`
   are correct (`readme = "README.md"` points at a real file).
3. `LICENSE` is at the repository root (Apache-2.0).
4. `moon fmt --check`, `moon check --deny-warn`, `moon test --deny-warn` pass.
5. `pkg.generated.mbti` files match the public API (`moon info`).
6. CI on the default branch is green.
7. Tag the commit: `git tag v0.3.0 && git push origin v0.3.0`.

## Preview the package page

`mooncakes.io` renders `README.md` and the generated `.mbti` interfaces. To check
locally what the API surface will look like:

```bash
moon info && cat src/flac/pkg.generated.mbti | head -40
```

## GitHub + Gitlink (competition submissions)

If this repository is submitted to the OSC contests, the same commit must be
visible on both hosts:

```bash
git remote add github  https://github.com/Sakuraqwq1/moonaudio
git remote add gitlink https://gitlink.org.cn/<account>/moonaudio
git push github  main
git push gitlink main
```

Then confirm that the **default branch** on both hosts shows the README, the
license and the recent commits. Work that only exists on a side branch will not
be seen by reviewers.
