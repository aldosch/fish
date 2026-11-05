function __nixx_flake_update --description 'nix flake update with an authenticated GitHub token'
    # api.github.com hard-rate-limits unauthenticated calls, and shared egress
    # IPs (VPNs, cloud NATs) burn through the 60/hr anonymous budget fast,
    # failing the nixx flake step with HTTP 403. Passing the gh token via
    # NIX_CONFIG (access-tokens) keeps the request authenticated. Degrades to
    # anonymous when no token resolves, which is no worse than before.
    set -l tok (gh auth token 2>/dev/null)
    if test -n "$tok"
        set -lx NIX_CONFIG "access-tokens = github.com=$tok"
    end
    cd ~/.config/nix; and nix flake update
end
