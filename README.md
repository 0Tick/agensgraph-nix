# agensgraph-nix

A nix flake wrapping [AgensGraph](https://github.com/skaiworldwide-oss/agensgraph), a multi-model graph database based on PostgreSQL.

## Usage

### Using the overlay

Add the flake to your inputs and apply the overlay to get `agensgraph` as a package in nixpkgs:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    agensgraph = {
      url = "github:0Tick/agensgraph-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, agensgraph, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ agensgraph.overlays.default ];
      };
    in
    {
      # Now pkgs.agensgraph is available under pkgs
      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.agensgraph ];
      };
    };
}
```

### NixOS module

You can use AgensGraph with the standard NixOS PostgreSQL service:

```nix
{ pkgs, ... }:
{
  services.postgresql = {
    enable = true;
    package = pkgs.agensgraph;
  };
}
```

### With extensions

AgensGraph supports PostgreSQL 16 extensions via `withPackages`:

```nix
pkgs.agensgraph.withPackages (ps: [ ps.postgis ps.pg_cron ])
```

### JIT support

A JIT-enabled variant is available:

```nix
# Via the packages output
agensgraph.packages.${system}.agensgraph-jit

# Or toggle on an existing package
pkgs.agensgraph.withJIT
```
