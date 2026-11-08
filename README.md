# packages

Central package repository for my projects, served at
**https://packages.alejandro.md**.

One APT repository, one signing key, one source line on the user's machine, no
matter how many of my projects they install. Replaces the per-project
`gh-pages` repositories that each shipped their own key and source file.

## How it fits together

```
          amd989/packages  (this repo)
          holds reprepro conf + R2 credentials
          the only writer of the index
                  ^
                  | repository_dispatch { repo, tag }
                  |
   +--------------+--------------+--------------+
   |              |              |              |
mariner3d/     readout      klipper-connect    ...
 mariner
   each builds its own artifacts and attaches
   them to its own GitHub Release
```

Project repositories never hold R2 credentials and never touch the index. They
build, they publish a GitHub Release, they send one dispatch. This repository
downloads the release assets, folds them into reprepro, and syncs the result to
Cloudflare R2.

Because the artifacts are pulled from GitHub Releases rather than pushed, the
whole repository is reproducible from scratch. R2 is a cache of a derivable
artifact, never the only copy of a binary.

## Layout

| Path | Purpose |
| --- | --- |
| `conf/distributions` | reprepro suites, architectures, signing key |
| `projects/*.json` | the registry of projects allowed to publish here |
| `keyring/` | the `alejandro-md-keyring` bootstrap package |
| `site/` | landing page and `setup.sh`, uploaded to the bucket root |
| `.github/workflows/publish.yaml` | the publisher |

Published layout in the bucket:

```
packages.alejandro.md/
  index.html
  setup.sh
  gpg.key
  deb/dists/{bookworm,trixie}/main/binary-{amd64,arm64,armhf}/
  deb/pool/main/...
```

## Adding a project

1. Add `projects/<name>.json`:

   ```json
   {
     "name": "readout",
     "repo": "amd989/readout",
     "suites": ["bookworm", "trixie"],
     "deb_pattern": "*.deb"
   }
   ```

   A dispatch is rejected unless its `repo` appears here, so this file is the
   access control list, not just configuration.

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

   `PACKAGES_DISPATCH_TOKEN` is a fine-grained PAT whose only grant is
   read and write on `amd989/packages`. The default `GITHUB_TOKEN` cannot
   dispatch across repositories.

3. Make the package `Depends: alejandro-md-keyring` so the source and key are
   configured once, by one package, rather than duplicated per project.

Private project repositories additionally need a token here that can read their
releases; public ones work with the default `GITHUB_TOKEN`.

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

The signing fingerprint is pinned in the workflow. If `GPG_PRIVATE_KEY` is
missing, or imports to any other key, the job fails rather than re-signing the
repository with something existing installs will reject.

## Running it

| Trigger | Effect |
| --- | --- |
| `repository_dispatch` | publish one project at one tag |
| `workflow_dispatch` | publish one project, or every project at its latest release |
| `workflow_dispatch` with `rebuild` | discard the reprepro state and rebuild from every project's releases |
| weekly cron | reconciliation, so a dropped or failed dispatch self-heals |

Publishes are serialized by a `concurrency` group. Two of them writing the same
reprepro database would corrupt it.

Uploads go pool first, then indices, then a pruning pass over the pool. A
client that runs `apt update` partway through a publish sees a consistent set
either way, which is what avoids `Hash Sum mismatch`.

## Recovery

If the state bucket is lost, run the workflow with `rebuild` checked. It starts
from an empty database and re-derives every suite from the projects' GitHub
Releases. The only thing not reproducible from elsewhere is the signing key.
