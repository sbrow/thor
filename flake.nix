{
  description = "A dev environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    # process-compose-flake.url = "github:Platonic-Systems/process-compose-flake";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ self
    , flake-parts
    , nixpkgs
    , nixpkgs-unstable
    # , process-compose-flake
    , treefmt-nix
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.treefmt-nix.flakeModule
        # inputs.process-compose-flake.flakeModule
      ];
      systems = [ "x86_64-linux" ];

      perSystem =
        { pkgs, system, inputs', ... }: {
          _module.args.pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;

            overlays = [
              (final: prev: { unstable = inputs'.nixpkgs-unstable.legacyPackages; })
            ];
          };

          treefmt = {
            # Used to find the project root
            projectRootFile = "flake.nix";
            settings.global.excludes = [
              ".direnv/**"
              ".jj/**"
              ".env"
              ".envrc"
              ".env.local"
            ];


            # Format nix files
            programs.nixpkgs-fmt.enable = true;
            programs.deadnix.enable = true;

            # Format js, json, and yaml files
            programs.prettier.enable = true;
            settings.formatter.prettier =
              {
                excludes = [
                  "public/**"
                  "resources/js/modernizr.js"
                  "storage/app/caniuse.json"
                  "*.md"
                ];
              };
          };

          #process-compose.default.settings.processes = { };

          packages.default = pkgs.stdenv.mkDerivation rec {
            pname = "thor";
            version = nixpkgs.lib.trim (builtins.readFile ./version.txt);
            src = ./.;

            nativeBuildInputs = [
              pkgs.odin
              pkgs.pkg-config
            ];

            buildInputs = [
              pkgs.git
            ];

            doCheck = true;
            checkPhase = ''
              runHook preCheck
              odin test . -all-packages
              runHook postCheck
            '';

            buildPhase = ''
              runHook preBuild
              odin build . -o:speed -out:${pname}-keep
              echo "Listing filles..."
              ls .
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              install -Dm755 ${pname}-keep $out/bin/${pname}
              runHook postInstall
            '';
          };

          devShells.default = pkgs.mkShell
            {
              buildInputs = with pkgs; [
                odin
                ols

                # IDE
                unstable.helix
                typescript-language-server
                vscode-langservers-extracted
              ];
            };
        };
    };
}
