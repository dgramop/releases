#!/usr/bin/env bash
#
# Build the releases flake locally, copy the resulting closure to a
# target host, and pin it as a GC root under /nix/var/nix/gcroots.
#
# Push model: the target never fetches or builds. It doesn't need
# substituter access to your builders or outbound network egress for
# Nix. The tradeoff is that the caller has to be able to build the
# flake, either natively or via a remote builder.
#
# Pinning model: a plain gcroot symlink, not a nix profile. The
# manifest in flake.nix is the sole source of truth for what's kept
# available; profile generations would be redundant history over
# flake.lock. Rollback = git revert + re-push.

set -euo pipefail

flake_ref="github:dgramop/releases"
target_host=""
gcroot_path="/nix/var/nix/gcroots/dgramop-releases"

usage() {
  cat <<EOF
Usage: push-releases --target-host HOST [OPTIONS]

Required:
  --target-host HOST     SSH host to deploy to (user@host form accepted).

Options:
  --flake REF            Flake reference to build.
                         Default: $flake_ref
                         Use "." or "path:..." for a local checkout.
  --gcroot PATH          GC root symlink path on the target.
                         Default: $gcroot_path
  -h, --help             Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-host)
      target_host="${2:?--target-host requires a value}"
      shift 2
      ;;
    --flake)
      flake_ref="${2:?--flake requires a value}"
      shift 2
      ;;
    --gcroot)
      gcroot_path="${2:?--gcroot requires a value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$target_host" ]]; then
  echo "error: --target-host is required" >&2
  usage >&2
  exit 2
fi

echo "==> Building $flake_ref"
out=$(nix build --no-link --print-out-paths "$flake_ref")
printf '    %s\n' "$out"

echo "==> Copying closure to $target_host"
nix copy --to "ssh-ng://$target_host" "$out"

echo "==> Pinning $gcroot_path -> $out"
# Atomic swap: create the symlink under a temp name, then rename(2) it
# into place. Consumers following the gcroot never observe a missing or
# half-updated link.
tmp="${gcroot_path}.tmp"
# -t so sudo can prompt when passwordless sudo isn't configured.
# Client-side expansion of $out/$tmp/$gcroot_path is intentional: those
# values are only known here, not on the target.
# shellcheck disable=SC2029
ssh -t "$target_host" sudo sh -c \
  "'ln -sfn \"$out\" \"$tmp\" && mv -Tf \"$tmp\" \"$gcroot_path\"'"

echo "==> Done. $target_host now pins $out."
