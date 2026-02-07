{
  lib,
  stdenv,
  src,
  pkg-config,
  bison,
  flex,
  perl,
  python3,
  gettext,
  zlib,
  readline,
  openssl,
  icu,
  lz4,
  zstd,
  libxml2,
  libxslt,
  systemd,
  libossp_uuid,
  linux-pam,
  # Optional features
  enableSystemd ? lib.meta.availableOn stdenv.hostPlatform systemd,
  enableNls ? true,
  enablePlperl ? false,
  enablePlpython ? false,
  enableGssapi ? false,
  libkrb5,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "agensgraph";
  version = "2.16.0";

  inherit src;

  nativeBuildInputs = [
    pkg-config
    bison
    flex
    perl
    python3
  ] ++ lib.optional enableNls gettext;

  buildInputs = [
    zlib
    readline
    openssl
    icu
    lz4
    zstd
    libxml2
    libxslt
    libossp_uuid
    linux-pam
  ]
  ++ lib.optional enableSystemd systemd
  ++ lib.optional enableGssapi libkrb5;

  # Use the configure script instead of meson
  configureFlags = [
    "--with-openssl"
    "--with-readline"
    "--with-libxml"
    "--with-libxslt"
    "--with-lz4"
    "--with-zstd"
    "--with-uuid=ossp"
    "--with-icu"
    "--with-pam"
  ]
  ++ lib.optional enableNls "--enable-nls"
  ++ lib.optional (!enableNls) "--disable-nls"
  ++ lib.optional enableSystemd "--with-systemd"
  ++ lib.optional enablePlperl "--with-perl"
  ++ lib.optional enablePlpython "--with-python"
  ++ lib.optional enableGssapi "--with-gssapi";

  # Nix's patchShebangs handles the script interpreters automatically.
  postPatch = ''
    patchShebangs src/tools
    patchShebangs src/backend/catalog
    patchShebangs config
  '';

  # Enable parallel builds
  enableParallelBuilding = true;

  meta = {
    description = "AgensGraph - a multi-model graph database based on PostgreSQL";
    homepage = "https://github.com/skaiworldwide-oss/agensgraph";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
  };
})
