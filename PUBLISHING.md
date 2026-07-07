# Publishing `nombaone` to RubyGems

Releases are **automated and merge‑triggered**. You never build, test, tag, or
upload by hand — a GitHub Actions workflow
([`.github/workflows/release.yml`](.github/workflows/release.yml)) runs on every
merge to `main`, and publishes to RubyGems **only when the version number is
new**. Your only jobs are the few one‑time setup items below, then a one‑line
change per release.

---

## One‑time setup (~15 min, do these once ever)

- [ ] **Confirm the name is free.** Open <https://rubygems.org/gems/nombaone>. If
      it says *Page not found*, you're good. If a gem page loads, the name is
      taken — tell engineering before going further.
- [ ] **Make a RubyGems account** at <https://rubygems.org/sign_up> and turn on
      MFA (multi‑factor auth) under *Settings → Multi‑factor authentication*. This
      gem requires MFA to publish.
- [ ] **Put the code on GitHub.** Create an empty repo named **`nombaone-ruby`**
      under the `nombaone` org at
      <https://github.com/organizations/nombaone/repositories/new> (don't add a
      README/license — the repo already has them), then push the existing code to
      it.
- [ ] **Turn on tokenless publishing (Trusted Publishing).** At
      <https://rubygems.org/profile/oidc/pending_trusted_publishers/new>, create a
      *pending* trusted publisher and enter exactly:
      - RubyGems gem name: `nombaone`
      - GitHub repository owner: `nombaone`
      - GitHub repository name: `nombaone-ruby`
      - Workflow filename: `release.yml`
      - Environment: *(leave blank)*

That's it. No API tokens are ever created or stored.

> **Prefer not to use Trusted Publishing?** Instead, create an API key at
> <https://rubygems.org/profile/api_keys> with the *push rubygem* scope, and add
> it to the GitHub repo as a secret named **`RUBYGEMS_API_KEY`**
> (*Settings → Secrets and variables → Actions*). The workflow uses it as a
> fallback. Until either the trusted publisher **or** this secret exists, release
> runs stay green and simply skip the upload.

---

## To ship a release (every time)

- In [`lib/nombaone/version.rb`](lib/nombaone/version.rb), change the one line
  `VERSION = "0.1.0"` to the new number (`0.1.1` for a fix, `0.2.0` for
  features), and merge it to `main` (directly or via PR).

That's the whole release. On merge, GitHub runs the linter, the type check, and
the tests, builds the gem, and uploads the new version to RubyGems automatically.
Watch the **Release** run go green under *Actions* (~2 min); within a minute of
green, `gem install nombaone` serves it.

Merges that don't change the version publish nothing — the workflow sees the
version already exists on RubyGems and skips the upload. And if any check fails,
nothing is published.

---

## Before a release, you can prove it works (optional but recommended)

Run the full‑surface live check against the sandbox — it calls **every** SDK
method against the real API and prints a plain per‑method result plus a verdict:

```bash
NOMBAONE_API_KEY=nbo_sandbox_… ruby -Ilib scripts/verify.rb
```

You want the last line to read `… | DEFECTS 0` and `VERDICT: PASS`. A typed API
error (e.g. `404 …_NOT_FOUND`) is fine — it means the SDK parsed a real error
correctly. `infra` lines (e.g. a backend `504` on `mandates.create`) are backend
outages, not SDK bugs.

---

## If a release run fails (rare)

Open the failed **Release** run under *Actions* and read the red step:

- **A failing lint/type/test step** — the code is red; send the run link to
  engineering. Nothing was published.
- **Publish step skipped with a notice** — the one‑time Trusted Publishing setup
  (or the `RUBYGEMS_API_KEY` secret) isn't in place yet. Do the setup step above,
  then re‑run the workflow.

> Note: you can't overwrite a version on RubyGems. To fix a bad release, bump to
> the next number and merge again — never reuse a number.
