{
  pkgs,
  packages ? [ ],
  languages ? { },
  pre-commit ? {
    enable = false;
  },
  enterShell ? "",
}:

let
  # Directory where state files (hashes, requirements, lockfiles) are stored
  stateDir = ".dev-env";

  # Python setup
  pythonConfig = languages.python or { };
  venvConfig = pythonConfig.venv or { };
  venvDir = venvConfig.directory or "venv";

  pythonPkg =
    if pythonConfig.enable or false then
      let
        version =
          let
            v = pythonConfig.version or "";
          in
          if builtins.match "^[0-9]+\\.[0-9]+$" v == null then
            throw ''Invalid Python version: "${v}". Must be in the form "<major>.<minor>", e.g. "3.13"''
          else
            v;

        basePkg =
          if version == "3.8" then
            (import (builtins.fetchTarball {
              url = "https://github.com/NixOS/nixpkgs/archive/976fa3369d722e76f37c77493d99829540d43845.tar.gz";
              sha256 = "1r6c7ggdk0546wzf2hvd5a7jwzsf3gn1flr8vjd685rm74syxv6d";
            }) { }).python38
          else
            builtins.getAttr ("python" + builtins.replaceStrings [ "." ] [ "" ] version) pkgs;
      in
      basePkg.withPackages (
        ps: with ps; [
          pip
          setuptools
          wheel
        ]
      )
    else
      null;

  # JavaScript setup
  javascriptConfig = languages.javascript or { };
  npmConfig = javascriptConfig.npm or { };
  nodeModulesDir = npmConfig.directory or "node_modules";

  nodePkg =
    if javascriptConfig.enable or false then
      let
        version = javascriptConfig.version or "22";
      in
      builtins.getAttr ("nodejs_" + version) pkgs
    else
      null;

  # Destroy dev environment
  destroy = pkgs.writeShellApplication {
    name = "dev-env-destroy";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      #!/usr/bin/env bash
      set -e

      if [ -d "${stateDir}" ]; then
        echo "Destroying environment ..."
        rm -fr .direnv "${stateDir}" "${venvDir}" "${nodeModulesDir}"
        rm -f .git/hooks/pre-commit
        echo "Environment destroyed."
      else
        echo "${stateDir} not found"
        exit 1
      fi
    '';
  };

in
pkgs.mkShell {
  # Packages to install in shell:
  # - user-specified packages
  # - coreutils and gnused for shell functions
  # - pre-commit if enabled
  # - pythonPkg if Python is enabled
  # - nodePkg if JavaScript is enabled
  buildInputs =
    packages
    ++ [
      pkgs.coreutils
      pkgs.gnused
      pkgs.nixfmt-rfc-style
      destroy
    ]
    ++ (if pre-commit.enable then [ pkgs.pre-commit ] else [ ])
    ++ (if pythonConfig.enable or false then [ pythonPkg ] else [ ])
    ++ (if javascriptConfig.enable or false then [ nodePkg ] else [ ]);

  shellHook = ''
    #!/usr/bin/env bash
    set -e

    kebab_case() {
      echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g'
    }

    # Save sha256 hash of file to state directory
    save_hash() {
      local file="$1"
      local filename=$(basename "$file")
      local normalized_name=$(kebab_case "$filename")
      local hash_file="${stateDir}/hash-$normalized_name"
      local current_hash=$(sha256sum "$file" | cut -d' ' -f1)
      echo "$current_hash" > "$hash_file"
    }

    # Check whether hash of file has changed compared to stored hash file
    hash_changed() {
      local file="$1"
      local filename=$(basename "$file")
      local normalized_name=$(kebab_case "$filename")
      local hash_file="${stateDir}/hash-$normalized_name"
      local current_hash=$(sha256sum "$file" | cut -d' ' -f1)
      local stored_hash=$(cat "$hash_file" 2>/dev/null || echo "")
      [[ "$current_hash" != "$stored_hash" ]]
    }

    # Remove file and its stored hash file from state directory
    untrack_file() {
      local file="$1"
      local filename=$(basename "$file")
      local normalized_name=$(kebab_case "$filename")
      local hash_file="${stateDir}/hash-$normalized_name"
      rm -f "$file" "$hash_file"
    }

    ${
      if (pythonConfig.enable or false) && (venvConfig.enable or false) then
        ''
          mkdir -p "${stateDir}"
          requirements_file="${stateDir}/requirements.txt"

          if [ ! -d "${venvDir}" ]; then
            untrack_file "$requirements_file"
          fi

          cat ${toString (venvConfig.requirements or [ ])} | sort | uniq > "$requirements_file"
          export PYTHONPATH=${pythonPkg}/${pythonPkg.sitePackages}

          if [ ! -d "${venvDir}" ]; then
            echo "Creating Python virtual environment: ${venvDir} ..."
            ${pythonPkg}/bin/python -m venv ${venvDir}
            source ${venvDir}/bin/activate
            pip install --upgrade pip setuptools wheel
          else
            source ${venvDir}/bin/activate
          fi

          if hash_changed "$requirements_file"; then
            echo "Installing Python dependencies ..."
            pip install -r "$requirements_file"
            save_hash "$requirements_file"
          fi
        ''
      else
        ""
    }

    ${
      if (javascriptConfig.enable or false) && (npmConfig.enable or false) then
        ''
          mkdir -p "${stateDir}"
          lock_file="${stateDir}/package-lock.json"

          if [ ! -d "${nodeModulesDir}" ]; then
            untrack_file "$lock_file"
          fi

          if [ -f package-lock.json ]; then
            cp -f package-lock.json "$lock_file"

            if [ ! -d "${nodeModulesDir}" ] || hash_changed "$lock_file"; then
              echo "Installing Node dependencies ..."
              npm ci
              save_hash "$lock_file"
            fi
          else
            echo "package-lock.json not found"
            exit 1
          fi
        ''
      else
        ""
    }

    ${
      if pre-commit.enable then
        ''
          if [ ! -f .git/hooks/pre-commit ]; then
            echo "Installing pre-commit ..."
            pre-commit install
          fi
        ''
      else
        ""
    }

    ${enterShell}
  '';
}
