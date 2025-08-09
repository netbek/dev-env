# dev-env

A basic dev environment using Nix.

## Install

1. Install Nix:

    ```shell
    sh <(curl -L https://nixos.org/nix/install) --daemon
    ```

2. Create `shell.nix`. [See example](#usage).

3. Create `.gitignore`. [See example](.gitignore).

## Automatic shell activation

1. Install direnv:

    ```shell
    sudo apt install direnv
    ```

2. Create `.envrc`. [See example](.envrc).

## pre-commit

Create `.pre-commit-config.yaml`. [See example](.pre-commit-config.yaml).

## Uninstall

To destroy the dev environment (`.dev-env` and `.direnv`), Python virtual environment (if enabled) and Node modules (if enabled), run:

```shell
dev-env-destroy
```

## Usage

`packages`, `languages` and `pre-commit` are optional.

```nix
let
  pkgs = import <nixpkgs> { };
  devEnv = import (
    builtins.fetchGit {
      url = "https://github.com/netbek/dev-env.git";
      ref = "refs/tags/v1.0.0";
    }
  );
in
devEnv {
  inherit pkgs;

  packages = [
    pkgs.cairo
    pkgs.pkg-config
  ];

  languages = {
    javascript = {
      enable = true;
      version = "22";
      npm = {
        enable = true;
      };
    };

    python = {
      enable = true;
      version = "3";
      venv = {
        enable = true;
        requirements = [
          ./development_requirements.txt
          ./production_requirements.txt
        ];
      };
    };
  };

  pre-commit = {
    enable = true;
  };
}
```

## Credit

Inspired by:

- [devenv](https://github.com/cachix/devenv) (Apache License 2.0)

## License

Copyright (c) 2025 Hein Bekker. Licensed under the GNU Affero General Public License, version 3.
