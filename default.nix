{
  pkgs,
  rootPath,
  packages ? [ ],
  languages ? { },
  pre-commit ? {
    enable = false;
  },
  enterShell ? "",
}:

let
  # Directory where state files (checksums, requirements, lockfiles) are stored
  statePath = "${rootPath}/.dev-env";

  # Python setup
  pythonConfig = languages.python or { };
  venvConfig = pythonConfig.venv or { };
  venvPath = "${rootPath}/${venvConfig.directory or "venv"}";

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
  nodeModulesPath = "${rootPath}/${npmConfig.directory or "node_modules"}";

  nodePkg =
    if javascriptConfig.enable or false then
      let
        version =
          let
            v = javascriptConfig.version or "";
          in
          if builtins.match "^[0-9]+$" v == null then
            throw ''Invalid Node.js version: "${v}". Must be in the form "<major>", e.g. "22"''
          else
            v;
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

      if [ -d "${statePath}" ]; then
        echo "Destroying environment ..."
        rm -fr "${rootPath}/.direnv" "${statePath}" "${venvPath}" "${nodeModulesPath}"
        rm -f "${rootPath}/.git/hooks/pre-commit"
        echo "Environment destroyed."
      else
        echo "${statePath} not found"
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

    # Save sha256 checksum of file to state directory
    save_checksum() {
      local file="$1"
      local version="$2"
      local filename=$(basename "$file")
      local normalized_name=$(kebab_case "$filename")
      local checksum_file="${statePath}/checksum-$normalized_name"
      local checksum=$(sha256sum "$file" | cut -d' ' -f1)
      local actual="$version:$checksum"
      echo "$actual" > "$checksum_file"
    }

    # Check whether checksum of file has changed compared to stored checksum file
    checksum_changed() {
      local file="$1"
      local version="$2"
      local filename=$(basename "$file")
      local normalized_name=$(kebab_case "$filename")
      local checksum_file="${statePath}/checksum-$normalized_name"
      local checksum=$(sha256sum "$file" | cut -d' ' -f1)
      local actual="$version:$checksum"
      local stored=$(cat "$checksum_file" 2>/dev/null || echo "")
      [[ "$actual" != "$stored" ]]
    }

    # Remove file and its stored checksum file from state directory
    untrack_file() {
      local file="$1"
      local filename=$(basename "$file")
      local normalized_name=$(kebab_case "$filename")
      local checksum_file="${statePath}/checksum-$normalized_name"
      rm -f "$file" "$checksum_file"
    }

    ${
      if (pythonConfig.enable or false) && (venvConfig.enable or false) then
        ''
          mkdir -p "${statePath}"
          requirements_file="${statePath}/requirements.txt"

          if [ ! -d "${venvPath}" ]; then
            untrack_file "$requirements_file"
          fi

          cat ${toString (venvConfig.requirements or [ ])} | sort | uniq > "$requirements_file"
          export PYTHONPATH=${pythonPkg}/${pythonPkg.sitePackages}

          if [ ! -d "${venvPath}" ]; then
            echo "Creating Python virtual environment: ${venvPath} ..."
            ${pythonPkg}/bin/python -m venv ${venvPath}
            source ${venvPath}/bin/activate
            pip install --upgrade pip setuptools wheel
          else
            source ${venvPath}/bin/activate
          fi

          if checksum_changed "$requirements_file" "${pythonConfig.version}"; then
            echo "Installing Python dependencies ..."
            pip install -r "$requirements_file"
            save_checksum "$requirements_file" "${pythonConfig.version}"
          fi
        ''
      else
        ""
    }

    ${
      if (javascriptConfig.enable or false) && (npmConfig.enable or false) then
        ''
          mkdir -p "${statePath}"
          lock_file="${rootPath}/package-lock.json"
          state_lock_file="${statePath}/package-lock.json"

          if [ ! -d "${nodeModulesPath}" ]; then
            untrack_file "$state_lock_file"
          fi

          if [ -f "$lock_file" ]; then
            cp -f "$lock_file" "$state_lock_file"

            if [ ! -d "${nodeModulesPath}" ] || checksum_changed "$state_lock_file" "${javascriptConfig.version}"; then
              echo "Installing Node dependencies ..."
              ${nodePkg}/bin/npm ci
              save_checksum "$state_lock_file" "${javascriptConfig.version}"
            fi

            export PATH="${nodeModulesPath}/.bin:$PATH"
          else
            echo "$lock_file not found"
            exit 1
          fi
        ''
      else
        ""
    }

    ${
      if pre-commit.enable then
        ''
          if [ -d "${rootPath}/.git" ]; then
            if [ ! -f "${rootPath}/.git/hooks/pre-commit" ]; then
              echo "Installing pre-commit ..."
              pre-commit install
            fi
          else
            echo "${rootPath}/.git not found"
            exit 1
          fi
        ''
      else
        ""
    }

    ${enterShell}
  '';
}
