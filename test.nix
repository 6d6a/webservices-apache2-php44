with import <nixpkgs> {
  overlays = [
    (import (builtins.fetchGit { url = "git@gitlab.intr:_ci/nixpkgs.git"; ref = "refactor"; }))
  ];
};

#maketestPhp {
#  php = php4;
#  image = callPackage ./default.nix {};
#  rootfs = ./rootfs;
#}