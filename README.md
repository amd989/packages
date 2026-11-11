# packages

Central package repository for my projects, served at
**https://packages.alejandro.md**.

One repository, one signing key, one source line on the user's machine, no
matter how many of my projects they install. Replaces the per-project
`gh-pages` repositories that each shipped their own key, their own source
file and their own setup scripts.

## How it fits together

```
          amd989/packages  (this repo)
          holds the repo config + R2 credentials
          the only writer of the index
                  ^
                  | repository_dispatch { repo, tag }
                  |
   +--------------+--------------+----------------+
   |              |              |                |
mariner3d/   amd989/        amd989/          amd989/
 mariner     unifi-gateway  lcd4linux-ax206  InfraFi  ...
   each builds its own artifacts and attaches
   them to its own GitHub Release
```

Project repositories never hold R2 credentials and never touch the index.
They build, they publish a GitHub Release, they send one dispatch. This
repository downloads the release assets, folds them into the right channel,
and syncs the result to Cloudflare R2.

Because artifacts are pulled from GitHub Releases rather than pushed, the
whole repository is reproducible from scratch. R2 is a cache of a derivable
artifact, never the only copy of a binary.

## Channels

| Channel | Path | Built with | Signed |
| --- | --- | --- | --- |
| apt | `/deb` | reprepro | yes, OpenPGP |
| dnf / yum | `/rpm` | createrepo_c | yes, OpenPGP |
| FreeBSD pkg | `/pkg` | `pkg repo` in a FreeBSD VM | no |
| OpenWrt opkg | `/openwrt/ipk` | `tools/mkopkg-index.sh` | no |
| OpenWrt apk | `/openwrt/apk` | apk-tools in a container | no |

`pkg` and OpenWrt verify repositories with their own key formats, RSA
fingerprints and usign respectively, neither of which is OpenPGP. Signing
them would mean a second and third key that no existing install trusts, so
they are served unsigned, which is what the per-project repositories did
too. The setup script says so out loud rather than leaving it implicit.

Two notes on what the per-project workflows got wrong and this one does not:

- They wrote a detached `.asc` next to each `.rpm`. `gpgcheck` reads the
  signature embedded in the rpm header, so those packages were effectively
  unsigned while the repo file claimed `gpgcheck=1`. Here `rpm --addsign`
  puts the signature where rpm looks for it, and `repomd.xml` is signed for
  `repo_gpgcheck=1`.
- They copied `.ipk` files into a directory with no `Packages` index, so
  `opkg update` against that feed could not work. The index is generated now.

## Layout

| Path | Purpose |
| --- | --- |
| `conf/distributions` | reprepro suites, architectures, signing key |
| `projects/*.json` | the registry of projects allowed to publish here |
| `keyring/` | the `alejandro-md-keyring` deb, for apt |
| `rpm/` | the `alejandro-md-release` rpm, for dnf |
| `tools/` | the opkg index generator |
| `site/` | landing page and `setup.sh`, uploaded to the bucket root |
| `.github/workflows/publish.yaml` | the publisher |

Published layout:

```
packages.alejandro.md/
  index.html  setup.sh  gpg.key
  deb/dists/{bookworm,trixie,stable}/main/binary-{amd64,arm64,armhf,armel}/
  deb/pool/main/...
  rpm/packages/  rpm/repodata/
  pkg/
  openwrt/ipk/  openwrt/apk/
```

`stable` exists because every per-project channel published its deb indices
under that codename, so every source file already on a user's machine asks
for it. New installs get the release-specific suite.

## Bootstrapping a machine

```
curl -fsSL https://packages.alejandro.md/setup.sh | sudo sh
```

One script, four package managers: it detects apt, dnf/yum, FreeBSD `pkg`,
and OpenWrt `opkg`/`apk`. On apt and dnf it installs a small release package
that then owns the source definition, so later changes to the repository
arrive as a normal package upgrade rather than another curl into a shell.
Those packages also retire the per-project sources and keyrings from the old
channels, which is what makes the migration silent.

## Adding a project

1. Add `projects/<name>.json`:

   ```json
   {
     "name": "readout",
     "repo": "amd989/readout",
     "suites": ["bookworm", "trixie", "stable"],
     "formats": ["deb", "rpm"]
   }
   ```

   `formats` selects the channels, and the publisher looks for `*.<format>`
   assets on the release. A dispatch is rejected unless its `repo` appears
   here, so this file is the access control list, not just configuration.

2. In that project's release workflow, after the release is published:

   ```yaml
   - name: Publish to packages.alejandro.md
     env:
       GH_TOKEN: ${{ secrets.PACKAGES_DISPATCH_TOKEN }}
     run: |
       gh api repos/amd989/packages/dispatches \
         -f event_type=publish \
         -F 'client_payload[repo]=${{ github.repository }}' \
         -F 'client_payload[tag]=${{ github.ref_name }}'
   ```

   `PACKAGES_DISPATCH_TOKEN` is a fine-grained PAT whose only grant is read
   and write on `amd989/packages`. The default `GITHUB_TOKEN` cannot dispatch
   across repositories.

3. Make the deb `Recommends: alejandro-md-keyring` and the rpm
   `Recommends: alejandro-md-release`, so the source and key are configured
   once by one package rather than duplicated per project. Recommends
   rather than Depends: an upgrade from an old per-project channel pulls
   the package in either way, but a hard dependency would stop someone
   from installing a downloaded `.deb` or `.rpm` on a machine without this
   repository configured.

Private project repositories additionally need a token here that can read
their releases; public ones work with the default `GITHUB_TOKEN`.

## Secrets

Set on this repository only:

| Secret | What it is |
| --- | --- |
| `R2_ACCOUNT_ID` | Cloudflare account id, used to build the S3 endpoint |
| `R2_ACCESS_KEY_ID` | R2 API token id, scoped to the two buckets below |
| `R2_SECRET_ACCESS_KEY` | R2 API token secret |
| `GPG_PRIVATE_KEY` | armored private key for `7802971A833983DD60CD4C1F68A66E3B0EA6F825` |

Buckets:

| Bucket | Visibility | Contents |
| --- | --- | --- |
| `packages` | public, bound to `packages.alejandro.md` | the served repository |
| `packages-state` | private | the reprepro database |

The old channels committed the reprepro database into the published
`gh-pages` branch, which made it public and is why one of those forks grew
to 2.58 GB. Here it lives in a private bucket and never reaches git.

The signing fingerprint is pinned in the workflow. If `GPG_PRIVATE_KEY` is
missing, or imports to any other key, the job fails rather than re-signing
the repository with something existing installs will reject. The
per-project workflows silently generated a throwaway RSA key in that case.

## Running it

| Trigger | Effect |
| --- | --- |
| `repository_dispatch` | publish one project at one tag |
| `workflow_dispatch` | publish one project, or every project at its latest release |
| `workflow_dispatch` with `rebuild` | discard the reprepro state and rebuild from every project's releases |
| weekly cron | reconciliation, so a dropped or failed dispatch self-heals |

Publishes are serialized by a `concurrency` group. Two of them writing the
same reprepro database would corrupt it.

Deb uploads go pool first, then indices, then a pruning pass over the pool,
and rpm the same way with packages before `repodata`. A client that runs
`apt update` or `dnf makecache` partway through a publish sees a consistent
set either way, which is what avoids `Hash Sum mismatch`.

Each suite carries one version of each package per architecture. reprepro's
`Limit` field would keep more, but it needs 5.4.0 and Debian ships
`5.4.6+really5.3.2`, having reverted that feature, so the field is not
available to use. Older versions stay downloadable from the projects'
GitHub Releases.

The FreeBSD and apk steps only run when a target declares those formats, so
an ordinary deb-and-rpm publish does not pay for a VM boot or a container
pull.

## Recovery

If the state bucket is lost, run the workflow with `rebuild` checked. It
starts from an empty database and re-derives every suite from the projects'
GitHub Releases. The rpm, pkg and OpenWrt channels have no database at all
and are rebuilt from the releases on every run.

The only thing not reproducible from elsewhere is the signing key. It expires
2030-01-01.
