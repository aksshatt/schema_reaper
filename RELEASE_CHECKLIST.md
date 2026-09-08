# Release checklist

Run top to bottom for every release. Nothing here is optional — each item has
burned us at least once.

---

## 1. History & attribution hygiene

Do this **before** committing, and again before force-pushing anything.

- [ ] **No AI / wrong-author trailers.** Commit messages must not contain
      `Co-Authored-By: Claude`, `Claude-Session:`, or any `Co-Authored-By` for
      someone who did not write the change.

  ```sh
  git log --all --format='%B' | grep -iE 'co-authored|claude-session|claude' && echo "DIRTY" || echo "clean"
  ```

- [ ] **Authors are only the real people.** Expect `aksshatt` and `mitkush`
      only (GitHub's merge-commit `GitHub <noreply@github.com>` committer is
      fine).

  ```sh
  git log --all --format='%an <%ae>%n%cn <%ce>' | sort -u
  ```

- [ ] **Working tree identity is right** (so new commits are attributed
      correctly):

  ```sh
  git config user.name   # aksshatt
  git config user.email  # akshatpegwar5@gmail.com
  ```

- [ ] If a bad trailer or author already landed: strip it, then force-push
      `main` **and** move the affected tag.

  ```sh
  FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch -f \
    --msg-filter 'grep -v -iE "^(Co-Authored-By: Claude|Claude-Session:)"' \
    --tag-name-filter cat -- <range>
  git tag -f -a vX.Y.Z -m "schema_reaper X.Y.Z"
  git push --force <remote> main
  git push --force <remote> refs/tags/vX.Y.Z
  ```

- [ ] After any force-push, re-verify with a **fresh full clone** (not
      `--depth 1` — shallow only checks HEAD):

  ```sh
  git clone <url> /tmp/verify && cd /tmp/verify
  git log --all --format='%an <%ae>' | sort -u
  git log --all --format='%B' | grep -iE 'claude|rahul' || echo clean
  ```

---

## 2. Code checks

- [ ] Full CI locally — must be **0 failures**, **no offenses**:

  ```sh
  bundle exec rake          # rspec + rubocop
  ```

- [ ] **Ruby 2.7 floor holds** (the gem supports `>= 2.7`; endless methods and
      3.0+ syntax are a syntax error there):

  ```sh
  for f in $(find lib spec exe -name '*.rb'); do ruby2.7 -c "$f" >/dev/null || echo "FAIL $f"; done
  ```

  RuboCop's `TargetRubyVersion: 2.7` also catches this via `Lint/Syntax`.

- [ ] `gem build schema_reaper.gemspec` — **no warnings**, correct version.

- [ ] Packaged file list is complete (every `lib/**` file present):

  ```sh
  tar -xf schema_reaper-X.Y.Z.gem -C /tmp/g && tar -tzf /tmp/g/data.tar.gz | grep '^lib/'
  ```

---

## 3. Live database smoke test

Static-only unit specs do not exercise the real introspection SQL. Run against
a throwaway PostgreSQL with a deliberately dirty schema.

- [ ] Seed a DB with: a dead column, an always-NULL FK column, a single-value
      column, a dead (0-row) table, a composite-PK table, a polymorphic
      `(_type, _id)` pair, a duplicate/prefix index, an unindexed FK **that has
      data**.

- [ ] Run every command and eyeball the output:

  ```sh
  schema_reaper scan                     # grouped report, no duplicate rows per column/index
  schema_reaper scan --format json  | ruby -rjson -e 'JSON.parse(STDIN.read)'   # valid
  schema_reaper scan --format sarif | ruby -rjson -e 'p JSON.parse(STDIN.read)["version"]'  # "2.1.0"
  schema_reaper scan --format markdown
  schema_reaper scan --no-color          # plain output, no ANSI
  schema_reaper baseline && schema_reaper scan --ci ; echo $?   # 0 when nothing new
  # add a dead column, then:
  schema_reaper scan --ci ; echo $?      # 1, names the new finding
  schema_reaper generate-migration <table> <col>   # two files, both `ruby -c` clean
  schema_reaper trend
  ```

- [ ] Assertions that have regressed before:
  - `missing_fk_index` does **not** suggest `add_index` on an always-NULL column.
  - polymorphic `*_id` is **not** flagged when a `(*_type, *_id)` index exists.
  - `unused_index` **skips** (with a stderr notice) when the DB has no query
    history — it does not flag every index.
  - a finding for one physical column/index appears **once** (highest
    confidence wins; others listed as `also flagged by:`).
  - `--format json` on stdout is clean JSON — the `unused_index` notice is on
    **stderr**.

- [ ] Live introspection spec:

  ```sh
  SCHEMA_REAPER_TEST_DATABASE_URL=postgres:///throwaway bundle exec rspec spec/introspect/postgres_spec.rb
  ```

- [ ] `dropdb` the throwaway database.

---

## 4. Version & changelog

- [ ] Bump `lib/schema_reaper/version.rb`.
- [ ] `CHANGELOG.md` — new dated section, **Fixed / Changed / Added**, credit
      PRs and their authors.
- [ ] README still accurate (Ruby floor, flags, sample output, analyzer list).

---

## 5. Commit, tag, push

- [ ] Commit message: plain, no AI trailer (see §1).
- [ ] Annotated tag `vX.Y.Z`.

  ```sh
  git tag -a vX.Y.Z -m "schema_reaper X.Y.Z"
  git push <remote> main
  git push <remote> refs/tags/vX.Y.Z
  ```

---

## 6. Publish the gem

RubyGems requires account MFA; `gem push` prompts for an OTP that only the
maintainer can enter.

```sh
gem build schema_reaper.gemspec
gem push schema_reaper-X.Y.Z.gem --otp <6-digit code>
```

- [ ] Confirm it went live (API cache lags ~1 min):

  ```sh
  curl -s https://rubygems.org/api/v1/gems/schema_reaper.json \
    | ruby -rjson -e 'd=JSON.parse(STDIN.read); puts "#{d["version"]} #{d["authors"]}"'
  ```

- [ ] Published versions are **immutable**. A metadata/description typo needs a
      new version — never assume you can edit a live one.

---

## 7. Post-publish

- [ ] **Clean-room install** from RubyGems (not the local checkout):

  ```sh
  gem install schema_reaper -v X.Y.Z --install-dir /tmp/cr --no-document
  GEM_HOME=/tmp/cr /tmp/cr/bin/schema_reaper version
  # then run §3 against a live DB using that binary
  ```

- [ ] **Contributors graph.** GitHub's sidebar/Insights widget caches hard and
      can lag ~24h behind the real data. The source of truth is:

  ```sh
  gh api repos/aksshatt/schema_reaper/contributors --jq '.[].login'
  ```

  If the widget still shows a removed name after the API is clean: it is stale
  cache of force-pushed-away commits, clears on GitHub's next `gc`. A brand-new
  repo populated by `git push --mirror` of the clean history never shows the
  ghost.

- [ ] Rotate any personal access token that was pasted into a chat/log.

---

## Repo-move runbook (only when starting a fresh repo to shed a cache)

```sh
git clone --bare <old-url> /tmp/bare          # --bare, not --mirror: skips refs/pull/*
git -C /tmp/bare branch -D <stale/pr-branches>
gh api --method PATCH repos/aksshatt/schema_reaper -f name=schema_reaper_old
gh repo create aksshatt/schema_reaper --public --description "<desc>"
git -C /tmp/bare push --mirror https://<user>:<token>@github.com/aksshatt/schema_reaper.git
gh api --method PUT repos/aksshatt/schema_reaper/collaborators/mitkush -f permission=push
gh api --method PATCH repos/aksshatt/schema_reaper -f has_issues=true -f has_wiki=true -f has_projects=true
gh api --method PATCH repos/aksshatt/schema_reaper_old -F archived=true
git remote set-url origin https://github.com/aksshatt/schema_reaper.git
```

`push --mirror` copies commit objects **byte-for-byte** — authors, dates and
SHAs are unchanged. It carries branches, tags and deletions; it does **not**
carry issues, PRs, stars, releases text, settings, webhooks or the wiki. Set
those manually on the new repo.
