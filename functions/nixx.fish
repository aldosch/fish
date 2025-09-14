function nixx
    switch $argv
      case b
        fish -c "cd ~/.config/nix; nix build .#darwinConfigurations.$hostname.system --extra-experimental-features 'nix-command flakes' $argv[2..-1]"
      case a
        fish -c "cd ~/.config/nix; sudo -E ./result/sw/bin/darwin-rebuild switch --flake .#$hostname && nix-collect-garbage -d"
      case '*'
        fish -c "cd ~/.config/nix; nix build .#darwinConfigurations.$hostname.system --extra-experimental-features 'nix-command flakes' $argv[2..-1]"
        fish -c "cd ~/.config/nix; sudo -E ./result/sw/bin/darwin-rebuild switch --flake .#$hostname && nix-collect-garbage -d"
    end
end
