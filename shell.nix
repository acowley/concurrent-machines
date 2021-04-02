{ compiler ? null
, sources ? import ./nix/sources.nix
}:
let
  pkgs = import sources.nixpkgs-chan {};
  overrideByVersion = if compiler == "ghc8101"
                      then self: super: { }
                      else self: super: { };
  hspkgs = (if isNull compiler
            then pkgs.haskellPackages
            else pkgs.haskell.packages.${compiler}).override {
    overrides = self: super: overrideByVersion self super;
  };
  drv = pkgs.haskell.lib.doBenchmark (hspkgs.callPackage ./default.nix {});
  ghc = hspkgs.ghc.withHoogle (ps: drv.passthru.getBuildInputs.haskellBuildInputs ++ [ps.cabal-install]);
in pkgs.mkShell {
  buildInputs = [ ghc hspkgs.haskell-language-server ];
}

