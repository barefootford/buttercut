#!/usr/bin/env bash
#
# Upload ButterCut's large test fixtures (spec/assets/) to a public Cloudflare R2
# bucket so CI and fresh clones can fetch them. See spec/assets_manifest.yml and
# spec/support/fixtures.rb for how they're consumed.
#
# Prerequisites:
#   - An R2 bucket (default name: buttercut-test-assets) with PUBLIC read access
#     enabled — either the bucket's r2.dev URL or a custom domain.
#   - Wrangler authenticated, one of:
#       npx wrangler login                      # interactive browser OAuth
#       export CLOUDFLARE_API_TOKEN=...          # token with "R2 Storage: Edit"
#
# Usage:
#   scripts/upload_test_assets.sh [bucket-name]
#
# After uploading, expose the bucket's public URL base via the
# BUTTERCUT_FIXTURES_BASE_URL env var (e.g. https://pub-xxxx.r2.dev or
# https://fixtures.example.com) — that's what spec/support/fixtures.rb reads.
# Locally: `export BUTTERCUT_FIXTURES_BASE_URL=...`. In CI: set it as a repo
# Actions variable (`gh variable set BUTTERCUT_FIXTURES_BASE_URL --body "..."`).
# The manifest's base_url stays as the ${BUTTERCUT_FIXTURES_BASE_URL} reference,
# so the URL is never committed to source.
set -euo pipefail

bucket="${1:-buttercut-test-assets}"
assets_dir="$(cd "$(dirname "$0")/.." && pwd)/spec/assets"

# Wrangler's single-request `r2 object put` buffers the whole file; anything much
# larger than this should be uploaded via the R2 dashboard or rclone instead.
max_single_put=$((300 * 1024 * 1024))

if [ ! -d "$assets_dir" ]; then
  echo "No $assets_dir — nothing to upload." >&2
  exit 1
fi

shopt -s nullglob
files=("$assets_dir"/*)
if [ ${#files[@]} -eq 0 ]; then
  echo "No files in $assets_dir." >&2
  exit 1
fi

echo "Uploading fixtures to r2://$bucket ..."
skipped=0
for f in "${files[@]}"; do
  name="$(basename "$f")"
  size="$(stat -f%z "$f")"
  if [ "$size" -gt "$max_single_put" ]; then
    echo "  ⚠ skipping $name ($((size / 1024 / 1024)) MB) — exceeds wrangler's single-put limit."
    echo "    Upload it via the R2 dashboard or rclone if you need the :benchmark fixtures."
    skipped=$((skipped + 1))
    continue
  fi
  echo "  → $name ($((size / 1024 / 1024)) MB)"
  npx --yes wrangler r2 object put "$bucket/$name" --file "$f" --remote
done

echo "Done${skipped:+ ($skipped skipped)}."
echo "Now expose the bucket's public URL via BUTTERCUT_FIXTURES_BASE_URL"
echo "(export it locally, or 'gh variable set BUTTERCUT_FIXTURES_BASE_URL --body <url>' for CI)."
