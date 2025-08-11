# dev-env

A basic dev environment using Nix.

## Install

1. Install Nix:

    ```shell
    sh <(curl -L https://nixos.org/nix/install) --daemon
    ```

2. Create `shell.nix`. [See example](example/shell.nix).

3. Create `.gitignore`. [See example](example/.gitignore).

## Automatic shell activation

1. Install direnv:

    ```shell
    sudo apt install direnv
    ```

2. Create `.envrc`. [See example](example/.envrc).

## pre-commit

Create `.pre-commit-config.yaml`. [See example](example/.pre-commit-config.yaml).

## Uninstall

To destroy the dev environment (`.dev-env` and `.direnv`), Python virtual environment (if enabled) and Node modules (if enabled), run:

```shell
dev-env-destroy
```

## Credit

Inspired by:

- [devenv](https://github.com/cachix/devenv) (Apache License 2.0)

## License

Copyright (c) 2025 Hein Bekker. Licensed under the GNU Affero General Public License, version 3.
