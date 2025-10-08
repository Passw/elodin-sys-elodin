{
  pkgs,
  crane,
  rustToolchain,
  lib,
  elodinPy,
  python,
  pythonPackages,
  ...
}: let
  craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;
  pname = (craneLib.crateNameFromCargoToml {cargoToml = ../../apps/elodin/Cargo.toml;}).pname;
  version = (craneLib.crateNameFromCargoToml {cargoToml = ../../Cargo.toml;}).version;
  src = pkgs.nix-gitignore.gitignoreSource [] ../../.;
  pythonPath = pythonPackages.makePythonPath [elodinPy];
  pythonMajorMinor = lib.versions.majorMinor python.version;

  commonArgs = with pkgs; {
    inherit pname version;
    inherit src;
    doCheck = false;
    cargoExtraArgs = "--package=${pname}";
    nativeBuildInputs = [makeWrapper];
    buildInputs =
      [
        pkg-config
        cmake
        gfortran
        python
      ]
      ++ lib.optionals stdenv.isLinux [
        alsa-lib
        udev
      ];

    # Workaround for netlib-src 0.8.0 incompatibility with GCC 14+
    # GCC 14 treats -Wincompatible-pointer-types as error by default
    NIX_CFLAGS_COMPILE = lib.optionalString pkgs.stdenv.isLinux "-Wno-error=incompatible-pointer-types";
  };

  cargoArtifacts = craneLib.buildDepsOnly commonArgs;

  clippy = craneLib.cargoClippy (
    commonArgs
    // {
      inherit cargoArtifacts;
      cargoClippyExtraArgs = "--all-targets -- --deny warnings --allow deprecated";
    }
  );

  bin = craneLib.buildPackage (
    commonArgs
    // {
      inherit cargoArtifacts;
      doCheck = false;
      postInstall = ''
        wrapProgram $out/bin/elodin \
          --prefix PATH : "${python}/bin" \
          --prefix PYTHONPATH : "${pythonPath}" \
          --prefix PYTHONPATH : "${python}/lib/python${pythonMajorMinor}" \
      '';
    }
  );

  test = craneLib.cargoNextest (
    commonArgs
    // {
      inherit cargoArtifacts;
      partitions = 1;
      partitionType = "count";
      cargoNextestPartitionsExtraArgs = "--no-tests=pass";
    }
  );
in {
  inherit bin clippy test;
}
