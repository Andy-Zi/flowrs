{
  description = "Nix flake for building and developing flowrs (Rust TUI for Apache Airflow)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    crane = {
      url = "github:ipetkov/crane";
    };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, crane }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
        lib = pkgs.lib;
        craneLib = crane.mkLib pkgs;

        # Include Cargo sources plus non-Rust assets required by include_str!
        # crane's cleanCargoSource omits extra files by default, so we extend the filter.
        src = lib.cleanSourceWith {
          src = craneLib.path ./.;
          filter = path: type:
            craneLib.filterCargoSources path type
            || (builtins.match ".*/image/.*" (toString path) != null)
            || lib.hasSuffix ".ascii" (toString path);
        };

        darwinBuildInputs = lib.optionals pkgs.stdenv.isDarwin [
          pkgs.libiconv
          pkgs.darwin.apple_sdk.frameworks.AppKit
          pkgs.darwin.apple_sdk.frameworks.Security
        ];

        linuxBuildInputs = lib.optionals (!pkgs.stdenv.isDarwin) [
          pkgs.openssl
        ];

        commonArgs = {
          pname = "flowrs-tui";
          version = "0.3.1";
          src = src;

          nativeBuildInputs = [
            pkgs.pkg-config
            pkgs.makeWrapper
          ];

          buildInputs = darwinBuildInputs ++ linuxBuildInputs;

          # Optionally set build features if needed
          cargoExtraArgs = "--locked";

          # Ensure openssl-sys does not try to build vendored OpenSSL
          OPENSSL_NO_VENDOR = 1;
        };
      in
      rec {
        # Pre-build dependency artifacts (speeds up builds and lets checks reuse them)
        cargoArtifacts = craneLib.buildDepsOnly (commonArgs // {
          cargoVendorHash = lib.fakeHash;
        });

        # Build the binary (first build will tell you the correct cargoVendorHash above)
        packages.default = craneLib.buildPackage (commonArgs // {
          inherit cargoArtifacts;
          # Do not run tests as part of the default package build (they can be run via `checks`)
          doCheck = false;
          # Ensure xdg-open is available at runtime for the webbrowser crate on Linux
          postInstall = lib.optionalString (!pkgs.stdenv.isDarwin) ''
            wrapProgram $out/bin/flowrs \
              --prefix PATH : ${lib.makeBinPath [ pkgs.xdg-utils ]}
          '';
        });

        # nix run
        apps.default = {
          type = "app";
          program = "${packages.default}/bin/flowrs";
        };

        # Development shell with Rust toolchain
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = [
            pkgs.rustc
            pkgs.cargo
            pkgs.clippy
            pkgs.rustfmt
            pkgs.pkg-config
          ];

          buildInputs = darwinBuildInputs ++ linuxBuildInputs;
        };

        # Optional quality checks
        checks = {
          fmt = craneLib.cargoFmt (commonArgs // { inherit cargoArtifacts; });
          clippy = craneLib.cargoClippy (commonArgs // {
            inherit cargoArtifacts;
            cargoClippyExtraArgs = "--all-targets --all-features -- -D warnings";
          });
          # Optionally, run unit tests only; disabled by default due to external deps
          # tests = craneLib.cargoTest (commonArgs // {
          #   inherit cargoArtifacts;
          #   cargoTestExtraArgs = "--lib --tests";
          # });
        };
      }
    );
}
