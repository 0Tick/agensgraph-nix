{
  description = "AgensGraph - a multi-model graph database based on PostgreSQL";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    agensgraph = {
      url = "github:skaiworldwide-oss/agensgraph/v2.16.0";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      agensgraph,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      overlays.default = final: prev: {
        agensgraph = self.packages.${prev.system}.default;
      };

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          agensgraph = pkgs.callPackage ./default.nix {
            src = agensgraph;
          };
          default = self.packages.${system}.agensgraph;
        }
      );
    };
}
