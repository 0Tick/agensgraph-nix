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

          # Use the same LLVM version as nixpkgs postgresql
          llvmPackages = pkgs.llvmPackages_18;

          # Helper function to create AgensGraph with extensions (similar to postgresqlWithPackages)
          agensgraphWithPackages =
            { agensgraph }:
            f:
            let
              # Get extension packages from the agensgraph's pkgs scope
              installedExtensions = f agensgraph.pkgs;
              baseAgensgraph = agensgraph.basePackage or agensgraph;
              finalPackage = pkgs.buildEnv {
                name = "${agensgraph.pname}-and-plugins-${agensgraph.version}";
                paths = installedExtensions ++ [ agensgraph ];

                pathsToLink = [
                  "/"
                  "/bin"
                  "/share/postgresql/extension"
                  "/share/postgresql/timezonesets"
                  "/share/postgresql/tsearch_data"
                ];

                nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
                postBuild =
                  let
                    args = lib.concatMap (ext: ext.wrapperArgs or [ ]) installedExtensions;
                  in
                  ''
                    wrapProgram "$out/bin/postgres" ${lib.concatStringsSep " " args}
                  '';

                passthru = {
                  inherit installedExtensions;
                  inherit (agensgraph)
                    pkgs
                    psqlSchema
                    version
                    jitSupport
                    ;

                  # Preserve base package reference for JIT toggling
                  basePackage = baseAgensgraph;

                  # JIT variants preserve extensions
                  withJIT = agensgraphWithPackages { agensgraph = baseAgensgraph.withJIT; } (
                    _: installedExtensions
                  );
                  withoutJIT = agensgraphWithPackages { agensgraph = baseAgensgraph.withoutJIT; } (
                    _: installedExtensions
                  );

                  # Allow adding more packages
                  withPackages =
                    f':
                    agensgraphWithPackages { inherit agensgraph; } (ps: installedExtensions ++ f' ps);
                };
              };
            in
            finalPackage;

          # Builder function for AgensGraph with configurable options
          mkAgensgraph =
            {
              jitSupport ? false,
            }:
            stdenv.mkDerivation (finalAttrs: {
              pname = "agensgraph";
              version = "2.16.0";

              src = agensgraph-src;

              nativeBuildInputs =
                with pkgs;
                [
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
                ]
                ++ lib.optionals jitSupport [
                  llvmPackages.llvm
                  llvmPackages.clang
                ];

              buildInputs =
                with pkgs;
                [
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
                ]
                ++ lib.optionals jitSupport [
                  llvmPackages.llvm
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

              configureFlags =
                [
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
                ]
                ++ lib.optionals jitSupport [
                  "--with-llvm"
                  "CLANG=${llvmPackages.clang}/bin/clang"
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

              postInstall = lib.optionalString jitSupport ''
                # In the case of JIT support, prevent useless dependencies on header files
                # Bitcode files are in lib/postgresql/bitcode/
                find "$out/lib/postgresql" -iname '*.bc' -type f -exec ${pkgs.nukeReferences}/bin/nuke-refs '{}' +

                # Stop lib depending on the -dev output of llvm
                # The JIT library is in lib/postgresql/
                ${pkgs.removeReferencesTo}/bin/remove-references-to -t ${llvmPackages.llvm.dev} "$out/lib/postgresql/llvmjit.so"
              '';

              # Wrap initdb with glibc locale path
              postFixup = ''
                wrapProgram $out/bin/initdb --prefix PATH ":" ${pkgs.glibc.bin}/bin
              '';

              # Passthru attributes required by NixOS services.postgresql module
              passthru =
                let
                  thisPackage = finalAttrs.finalPackage;
                  # Create variants with/without JIT
                  withJitPkg = mkAgensgraph { jitSupport = true; };
                  withoutJitPkg = mkAgensgraph { jitSupport = false; };
                in
                {
                  # PostgreSQL version compatibility (AgensGraph 2.16 is based on PostgreSQL 16)
                  psqlSchema = "16";

                  # Whether JIT is enabled in this build
                  inherit jitSupport;

                  # Empty by default, populated when withPackages is used
                  installedExtensions = [ ];

                  # JIT variants - allows toggling JIT support
                  # If this package has JIT, withJIT returns itself; otherwise returns JIT-enabled variant
                  # If this package has no JIT, withoutJIT returns itself; otherwise returns non-JIT variant
                  withJIT = if jitSupport then thisPackage else withJitPkg;
                  withoutJIT = if jitSupport then withoutJitPkg else thisPackage;

                  # Reuse PostgreSQL 16's extension packages
                  # This allows building extensions against AgensGraph using the same interface
                  pkgs = pkgs.postgresql_16.pkgs;

                  # Function to create a derivation with extensions
                  withPackages = agensgraphWithPackages { agensgraph = thisPackage; };
                };

              meta = {
                description = "AgensGraph - a multi-model graph database based on PostgreSQL";
                homepage = "https://github.com/skaiworldwide-oss/agensgraph";
                license = lib.licenses.asl20;
                platforms = lib.platforms.linux;
              };
            });

          # Default package without JIT (faster build, most users don't need JIT)
          defaultAgensgraph = mkAgensgraph { jitSupport = false; };

          # JIT-enabled variant
          agensgraphWithJIT = mkAgensgraph { jitSupport = true; };
        in
        {
          # Default package (without JIT)
          agensgraph = defaultAgensgraph;
          default = defaultAgensgraph;

          # Explicit JIT variant
          agensgraph-jit = agensgraphWithJIT;
        }
      );
    };
}
