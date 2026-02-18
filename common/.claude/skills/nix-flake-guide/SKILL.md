---
name: nix-flake-guide
description: Explain how to create basic Nix flakes, including structure, inputs, outputs, and dev shells. Use when the user asks about creating flakes, nix flake basics, flake.nix files, or needs help understanding flake structure.
---

# Nix Flake Guide

This skill explains how to create basic Nix flakes for development environments.

## What is a Flake?

A Nix flake is a self-contained unit of Nix code with:
- Explicit dependencies (inputs)
- Reproducible outputs
- A standardized structure

## Default Flake Template

Always use this structure as the default starting point. It includes `flake-utils` for cross-platform support:

```nix
{
  description = "A simple flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = [
          ];
        };
      }
    );
}
```

This template:
- Uses `flake-utils` to automatically support all common systems (x86_64-linux, aarch64-linux, x86_64-darwin, aarch64-darwin)
- Follows the preferred Nix formatting style with `let` on the same line
- Provides an empty `buildInputs` list ready for packages
- Is the recommended default for all new flakes

## Common Inputs

```nix
inputs = {
  # Stable nixpkgs
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

  # Unstable nixpkgs
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  # Multi-system helper
  flake-utils.url = "github:numtide/flake-utils";

  # Rust toolchain
  rust-overlay.url = "github:oxalica/rust-overlay";

  # Pin another flake input to same nixpkgs
  some-flake.inputs.nixpkgs.follows = "nixpkgs";
};
```

## Common Outputs

```nix
outputs = { self, nixpkgs, ... }: {
  # Development shell (nix develop)
  devShells.x86_64-linux.default = ...;

  # Packages (nix build)
  packages.x86_64-linux.default = ...;
  packages.x86_64-linux.myapp = ...;

  # NixOS modules
  nixosModules.default = ...;

  # Overlays
  overlays.default = ...;

  # Apps (nix run)
  apps.x86_64-linux.default = ...;
};
```

## Dev Shell with Shell Hook

Add initialization scripts:

```nix
devShells.default = pkgs.mkShell {
  buildInputs = [
    pkgs.python3
    pkgs.poetry
  ];

  shellHook = ''
    echo "Welcome to the dev environment!"
    export PROJECT_ROOT=$(pwd)
    poetry install --quiet
  '';
};
```

## Getting Started

1. Create `flake.nix` in your project root
2. Initialize git: `git init` (flakes require git)
3. Add the flake: `git add flake.nix`
4. Enter the shell: `nix develop`
5. Build: `nix build`

## Useful Commands

| Command | Description |
|---------|-------------|
| `nix develop` | Enter the dev shell |
| `nix build` | Build the default package |
| `nix flake update` | Update all inputs |
| `nix flake lock --update-input nixpkgs` | Update specific input |
| `nix flake show` | Show flake outputs |
| `nix flake check` | Validate the flake |

## Tips

- Always commit `flake.lock` for reproducibility
- Use `nixpkgs.follows` to avoid duplicate nixpkgs versions
- Start with `nixos-unstable` for latest packages
- Use `nix flake check` to validate your flake
- Run `nix develop -c $SHELL` to keep your shell config
