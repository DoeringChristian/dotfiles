{
  description = "RapidRAW - GPU-accelerated RAW image editor";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
      };

      # Pre-fetch ONNX Runtime library (RapidRAW's build script downloads this)
      onnxruntimeLib = pkgs.fetchurl {
        url = "https://huggingface.co/CyberTimon/RapidRAW-Models/resolve/main/onnxruntimes-v1.22.0/libonnxruntime-linux-x86_64.so?download=true";
        hash = "sha256-PaYUbhTnuKrsYl3eEdYRTHRXyHpfk9dEiX2oeB41xnM=";
        name = "libonnxruntime.so";
      };

      # Build frontend separately
      frontend = pkgs.buildNpmPackage {
        pname = "rapidraw-frontend";
        version = "1.4.12";

        src = pkgs.fetchFromGitHub {
          owner = "CyberTimon";
          repo = "RapidRAW";
          rev = "v1.4.12";
          hash = "sha256-ZsyRK2enyRZzmd/0Kv0RqkPiLso3CET9x6yCPRU0RBk=";
          fetchSubmodules = true;
        };

        npmDepsHash = "sha256-jenSEANarab/oQnC80NoM1jWmvdeXF3bJ9I/vOGcBb0=";

        buildPhase = ''
          runHook preBuild
          npm run build
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out
          cp -r dist $out/
          runHook postInstall
        '';
      };

      rapidraw = pkgs.rustPlatform.buildRustPackage rec {
        pname = "RapidRAW";
        version = "1.4.12";

        src = pkgs.fetchFromGitHub {
          owner = "CyberTimon";
          repo = "RapidRAW";
          rev = "v${version}";
          hash = "sha256-ZsyRK2enyRZzmd/0Kv0RqkPiLso3CET9x6yCPRU0RBk=";
          fetchSubmodules = true;
        };

        sourceRoot = "${src.name}/src-tauri";

        cargoHash = "sha256-F5fN14dv8iFUub3bYci+MC8fuyLLZKuoF9W1cfJ7NLo=";

        nativeBuildInputs = with pkgs; [
          pkg-config
          wrapGAppsHook4
        ];

        buildInputs = with pkgs; [
          # Tauri dependencies
          openssl
          glib
          gtk4
          libsoup_3
          webkitgtk_4_1
          librsvg

          # GPU/graphics
          vulkan-loader
          libGL

          # ML
          onnxruntime
        ];

        # Set ONNX Runtime location for the ort crate
        ORT_LIB_LOCATION = "${pkgs.onnxruntime}";

        # Tell Tauri where to find the frontend dist for embedding
        TAURI_FRONTEND_DIST = "${frontend}/dist";

        # Make parent directory writable, copy frontend assets and ONNX Runtime
        postUnpack = ''
          chmod -R u+w source
          mkdir -p source/dist
          cp -r ${frontend}/dist/* source/dist/

          # Pre-provide the ONNX Runtime library in resources/ so build script skips download
          mkdir -p source/src-tauri/resources
          cp ${onnxruntimeLib} source/src-tauri/resources/libonnxruntime.so
        '';

        # Wrap with required libraries
        postFixup = ''
          wrapProgram $out/bin/RapidRAW \
            --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath [
            pkgs.vulkan-loader
            pkgs.libGL
          ]}
        '';

        meta = with pkgs.lib; {
          description = "A beautiful, non-destructive, GPU-accelerated RAW image editor";
          homepage = "https://github.com/CyberTimon/RapidRAW";
          license = licenses.agpl3Only;
          maintainers = [];
          platforms = platforms.linux;
          mainProgram = "RapidRAW";
        };
      };
    in {
      packages = {
        default = rapidraw;
        rapidraw = rapidraw;
      };
    });
}
