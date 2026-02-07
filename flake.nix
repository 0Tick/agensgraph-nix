{
  description = "AgensGraph - a multi-model graph database based on PostgreSQL";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    agensgraph-src = {
      url = "github:skaiworldwide-oss/agensgraph/v2.16.0";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      agensgraph-src,
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
          lib = pkgs.lib;
          stdenv = pkgs.stdenv;
        in
        {
          agensgraph = stdenv.mkDerivation {
            pname = "agensgraph";
            version = "2.16.0";

            src = agensgraph-src;

            nativeBuildInputs = with pkgs; [
              pkg-config
              bison
              flex
              perl
              python3
              gettext
              docbook-xsl-nons
              docbook_xml_dtd_45
              libxslt
              makeBinaryWrapper
            ];

            buildInputs = with pkgs; [
              zlib
              readline
              openssl
              icu
              lz4
              zstd
              libxml2
              libxslt
              libuuid
              linux-pam
              systemdLibs
              libkrb5
            ];

            # Apply Nix-specific patches for AgensGraph
            patches = [
              ./patches/relative-to-symlinks-16+.patch
              ./patches/empty-pg-config-view-15+.patch
              ./patches/less-is-more.patch
              ./patches/paths-for-split-outputs.patch
              ./patches/paths-with-postgresql-suffix.patch

              # locale-binary-path.patch needs variable substitution
              (pkgs.replaceVars ./patches/locale-binary-path.patch {
                locale = "${lib.getBin stdenv.cc.libc}/bin/locale";
              })

              ./patches/socketdir-in-run-13+.patch

              # Fix for contrib/meta extension (pure SQL, incorrectly declares MODULE_big)
              ./patches/fix-meta-extension.patch
            ];

            configureFlags = [
              "--with-openssl"
              "--with-readline"
              "--with-libxml"
              "--with-libxslt"
              "--with-lz4"
              "--with-zstd"
              "--with-uuid=e2fs"
              "--with-icu"
              "--with-pam"
              "--with-systemd"
              "--with-gssapi"
              "--enable-nls"
              "--sysconfdir=/etc"
              "--with-system-tzdata=${pkgs.tzdata}/share/zoneinfo"
            ];

            # Substitute @out@ and @dev@ in patched files
            postPatch = ''
              patchShebangs src/tools
              patchShebangs src/backend/catalog
              patchShebangs config

              # The paths-for-split-outputs.patch uses @out@ and @dev@ placeholders
              # Since we use a single output, substitute both with $out
              substituteInPlace "src/Makefile.global.in" --subst-var out
              substituteInPlace "src/common/config_info.c" \
                --replace-fail "@dev@" "$out"
            '';

            buildFlags = [ "world" ];
            installTargets = [ "install-world" ];

            enableParallelBuilding = true;

            # Wrap initdb with glibc locale path
            postFixup = ''
              wrapProgram $out/bin/initdb --prefix PATH ":" ${pkgs.glibc.bin}/bin
            '';

            meta = {
              description = "AgensGraph - a multi-model graph database based on PostgreSQL";
              homepage = "https://github.com/skaiworldwide-oss/agensgraph";
              license = lib.licenses.asl20;
              platforms = lib.platforms.linux;
            };
          };

          default = self.packages.${system}.agensgraph;
        }
      );
    };
}
