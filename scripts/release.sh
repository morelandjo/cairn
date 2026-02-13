#!/usr/bin/env bash
set -euo pipefail

# Cairn local release script — replaces GitHub Actions CI + release pipeline
# Usage: scripts/release.sh <version>       e.g. scripts/release.sh 0.2.0
#        scripts/release.sh --dry-run       validate + test + build only, no push/release

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRY_RUN=false
VERSION=""

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${BLUE}==>${NC} ${BOLD}$*${NC}"; }
ok()    { echo -e "${GREEN} ✓${NC} $*"; }
warn()  { echo -e "${YELLOW} ⚠${NC} $*"; }
err()   { echo -e "${RED} ✗${NC} $*" >&2; }
fatal() { err "$@"; exit 1; }

# --- Argument parsing ---
case "${1:-}" in
  --dry-run)
    DRY_RUN=true
    info "Dry-run mode — will validate, test, and build only"
    ;;
  --help|-h|"")
    echo "Usage: scripts/release.sh <version>    e.g. scripts/release.sh 0.2.0"
    echo "       scripts/release.sh --dry-run    validate + test + build only"
    exit 0
    ;;
  *)
    VERSION="$1"
    # Strip leading 'v' if provided
    VERSION="${VERSION#v}"
    TAG="v${VERSION}"
    ;;
esac

confirm() {
  local prompt="$1"
  if [[ "$DRY_RUN" == true ]]; then
    return 0
  fi
  echo -en "${YELLOW}  → ${prompt} [Y/n] ${NC}"
  read -r answer
  case "$answer" in
    n|N|no|No) return 1 ;;
    *) return 0 ;;
  esac
}

# ============================================================
# Step 1: Validate tools
# ============================================================
step_validate() {
  info "Step 1: Validating tools"

  local missing=()
  command -v mix      >/dev/null || missing+=(mix)
  command -v node     >/dev/null || missing+=(node)
  command -v npm      >/dev/null || missing+=(npm)
  command -v cargo    >/dev/null || missing+=(cargo)
  command -v docker   >/dev/null || missing+=(docker)

  if [[ "$DRY_RUN" == false ]]; then
    command -v gh     >/dev/null || missing+=(gh)
  fi

  if (( ${#missing[@]} > 0 )); then
    fatal "Missing required tools: ${missing[*]}"
  fi

  ok "mix $(mix --version 2>/dev/null | tail -1)"
  ok "node $(node --version)"
  ok "cargo $(cargo --version | awk '{print $2}')"
  ok "docker $(docker --version | awk '{print $3}' | tr -d ',')"

  if [[ "$DRY_RUN" == false ]]; then
    ok "gh $(gh --version | head -1 | awk '{print $3}')"
  fi

  # Optional tools (warn but don't fail)
  if command -v mdbook >/dev/null; then
    ok "mdbook $(mdbook --version | awk '{print $2}')"
  else
    warn "mdbook not found — docs step will be skipped"
  fi

  if command -v wasm-bindgen >/dev/null; then
    ok "wasm-bindgen found"
  else
    warn "wasm-bindgen not found — proto WASM build may fail"
  fi

  echo ""
}

# ============================================================
# Step 2: Run tests
# ============================================================
step_test() {
  info "Step 2: Running tests"

  # Server
  info "  Server: format + compile + test"
  (cd "$ROOT/server" && mix format --check-formatted)
  ok "format check"
  (cd "$ROOT/server" && mix compile --warnings-as-errors)
  ok "compile (warnings-as-errors)"
  (cd "$ROOT/server" && mix test)
  ok "server tests"

  # Proto
  info "  Proto: build + test"
  (cd "$ROOT/proto" && npm run build)
  ok "proto build"
  (cd "$ROOT/proto" && npm test)
  ok "proto tests"

  # SFU
  info "  SFU: build + test"
  (cd "$ROOT/sfu" && npm run build)
  ok "sfu build"
  (cd "$ROOT/sfu" && npm test)
  ok "sfu tests"

  # Web client
  info "  Web: build"
  (cd "$ROOT/client/web" && npm run build)
  ok "web build"

  # Mobile type check
  info "  Mobile: type check"
  (cd "$ROOT/client/mobile" && npx tsc --noEmit)
  ok "mobile type check"

  echo ""
}

# ============================================================
# Step 3: Build Docker images
# ============================================================
step_docker() {
  local ver="${VERSION:-dev}"
  info "Step 3: Building Docker images (tag: $ver)"

  docker build \
    -t "ghcr.io/morelandjo/cairn-server:${ver}" \
    -t "ghcr.io/morelandjo/cairn-server:latest" \
    "$ROOT/server/"
  ok "cairn-server image"

  docker build \
    -t "ghcr.io/morelandjo/cairn-sfu:${ver}" \
    -t "ghcr.io/morelandjo/cairn-sfu:latest" \
    "$ROOT/sfu/"
  ok "cairn-sfu image"

  if [[ "$DRY_RUN" == false ]]; then
    if confirm "Push Docker images to ghcr.io?"; then
      docker push "ghcr.io/morelandjo/cairn-server:${ver}"
      docker push "ghcr.io/morelandjo/cairn-server:latest"
      docker push "ghcr.io/morelandjo/cairn-sfu:${ver}"
      docker push "ghcr.io/morelandjo/cairn-sfu:latest"
      ok "images pushed"
    else
      warn "skipped docker push"
    fi
  fi

  echo ""
}

# ============================================================
# Step 4: Build desktop app
# ============================================================
step_desktop() {
  info "Step 4: Building desktop app"

  # Proto + web must be built first (done in step_test, but ensure freshness)
  if [[ ! -d "$ROOT/client/web/dist" ]]; then
    info "  Building proto + web (dependencies)"
    (cd "$ROOT/proto" && npm run build)
    (cd "$ROOT/client/web" && npm run build)
  fi

  local os bundles
  case "$(uname -s)" in
    Darwin) os="macOS";  bundles="app" ;;
    Linux)  os="Linux";  bundles="appimage,deb" ;;
    *)      os="Windows"; bundles="msi" ;;
  esac

  info "  Detected OS: $os — bundles: $bundles"
  (cd "$ROOT/client/desktop" && cargo tauri build --bundles "$bundles")
  ok "desktop build complete"

  # Print artifact paths
  info "  Artifacts:"
  case "$os" in
    macOS)
      find "$ROOT/client/desktop/target/release/bundle" -name "*.app" -o -name "*.dmg" 2>/dev/null | while read -r f; do
        echo "    $f"
      done
      ;;
    Linux)
      find "$ROOT/client/desktop/target/release/bundle" -name "*.AppImage" -o -name "*.deb" 2>/dev/null | while read -r f; do
        echo "    $f"
      done
      ;;
  esac

  echo ""
}

# ============================================================
# Step 5: Build docs
# ============================================================
step_docs() {
  if ! command -v mdbook >/dev/null; then
    warn "Step 5: Skipping docs (mdbook not installed)"
    echo ""
    return
  fi

  info "Step 5: Building docs"
  mdbook build "$ROOT/docs"
  ok "docs built at docs/book/"
  echo ""
}

# ============================================================
# Step 6: Git tag + push
# ============================================================
step_git() {
  if [[ "$DRY_RUN" == true ]]; then
    return
  fi

  info "Step 6: Git tag + push"

  # Check for uncommitted changes
  if ! git -C "$ROOT" diff --quiet HEAD; then
    fatal "Working tree has uncommitted changes — commit or stash first"
  fi

  # Tag
  if git -C "$ROOT" tag -l "$TAG" | grep -q "$TAG"; then
    warn "Tag $TAG already exists"
  else
    git -C "$ROOT" tag "$TAG"
    ok "created tag $TAG"
  fi

  # Push to origin (private)
  if confirm "Push to origin (private)?"; then
    git -C "$ROOT" push origin main
    git -C "$ROOT" push origin "$TAG"
    ok "pushed to origin"
  fi

  # Squash-push to public
  if confirm "Squash-push to public?"; then
    git -C "$ROOT" fetch public
    git -C "$ROOT" checkout -b temp-public public/main
    git -C "$ROOT" merge --squash main --allow-unrelated-histories || true
    # Resolve any conflicts by taking main's version
    git -C "$ROOT" checkout main -- .
    git -C "$ROOT" add -A
    git -C "$ROOT" commit -m "Release ${TAG}" || true
    git -C "$ROOT" push public temp-public:main
    git -C "$ROOT" push public "$TAG"
    git -C "$ROOT" checkout main
    git -C "$ROOT" branch -D temp-public
    ok "squash-pushed to public"
  fi

  echo ""
}

# ============================================================
# Step 7: Create GitHub release
# ============================================================
step_release() {
  if [[ "$DRY_RUN" == true ]]; then
    return
  fi

  info "Step 7: Creating GitHub release"

  if ! confirm "Create release $TAG on public repo?"; then
    warn "skipped release creation"
    echo ""
    return
  fi

  # Collect desktop artifacts
  local artifacts=()
  local bundle_dir="$ROOT/client/desktop/target/release/bundle"
  if [[ -d "$bundle_dir" ]]; then
    while IFS= read -r f; do
      artifacts+=("$f")
    done < <(find "$bundle_dir" \( -name "*.app.tar.gz" -o -name "*.AppImage" -o -name "*.deb" -o -name "*.msi" -o -name "*.dmg" \) 2>/dev/null)
  fi

  local upload_args=()
  for a in "${artifacts[@]}"; do
    upload_args+=("$a")
  done

  if (( ${#upload_args[@]} > 0 )); then
    gh release create "$TAG" "${upload_args[@]}" \
      --repo morelandjo/cairn \
      --title "Cairn ${TAG}" \
      --notes "See the [changelog](https://github.com/morelandjo/cairn/blob/main/CHANGELOG.md) for details." \
      --draft
    ok "draft release created with ${#upload_args[@]} artifact(s)"
  else
    gh release create "$TAG" \
      --repo morelandjo/cairn \
      --title "Cairn ${TAG}" \
      --notes "See the [changelog](https://github.com/morelandjo/cairn/blob/main/CHANGELOG.md) for details." \
      --draft
    ok "draft release created (no desktop artifacts found)"
  fi

  echo ""
}

# ============================================================
# Step 8: Deploy docs
# ============================================================
step_deploy_docs() {
  if [[ "$DRY_RUN" == true ]]; then
    return
  fi

  if [[ ! -d "$ROOT/docs/book" ]]; then
    warn "Step 8: Skipping docs deploy (docs/book not found)"
    echo ""
    return
  fi

  info "Step 8: Deploying docs to gh-pages"

  if ! confirm "Push docs to gh-pages on public repo?"; then
    warn "skipped docs deploy"
    echo ""
    return
  fi

  local tmp_worktree
  tmp_worktree=$(mktemp -d)

  git -C "$ROOT" fetch public

  # Check if gh-pages branch exists on public
  if git -C "$ROOT" ls-remote --heads public gh-pages | grep -q gh-pages; then
    git clone --branch gh-pages --single-branch --depth 1 \
      "$(git -C "$ROOT" remote get-url public)" "$tmp_worktree"
  else
    git init "$tmp_worktree"
    git -C "$tmp_worktree" checkout --orphan gh-pages
    git -C "$tmp_worktree" remote add public "$(git -C "$ROOT" remote get-url public)"
  fi

  # Replace contents with built docs
  rm -rf "${tmp_worktree:?}"/*
  cp -r "$ROOT/docs/book/"* "$tmp_worktree/"
  touch "$tmp_worktree/.nojekyll"

  git -C "$tmp_worktree" add -A
  if git -C "$tmp_worktree" diff --cached --quiet; then
    warn "no docs changes to deploy"
  else
    git -C "$tmp_worktree" commit -m "docs: update for ${TAG:-latest}"
    git -C "$tmp_worktree" push public gh-pages
    ok "docs deployed"
  fi

  rm -rf "$tmp_worktree"
  echo ""
}

# ============================================================
# Main
# ============================================================
main() {
  echo ""
  echo -e "${BOLD}Cairn Release Pipeline${NC}"
  if [[ -n "$VERSION" ]]; then
    echo -e "  Version: ${GREEN}${TAG}${NC}"
  fi
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "  Mode:    ${YELLOW}dry-run${NC}"
  fi
  echo ""

  step_validate
  step_test
  step_docker
  step_desktop
  step_docs
  step_git
  step_release
  step_deploy_docs

  echo -e "${GREEN}${BOLD}Done!${NC}"
  if [[ "$DRY_RUN" == true ]]; then
    echo "  Dry-run complete — no pushes or releases were made."
  fi
}

main
