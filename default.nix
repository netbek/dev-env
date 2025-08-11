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
  devEnvPath = "${rootPath}/.dev-env"; # Contains state files, e.g. checksums, Python requirements, Node lockfiles
  direnvPath = "${rootPath}/.direnv";
  gitPath = "${rootPath}/.git";

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
  nodeModulesPath = "${rootPath}/node_modules";

  nodePkg =
    if javascriptConfig.enable or false then
      let
        version =
          let
            v = javascriptConfig.version or "";
          in
          if builtins.match "^[0-9]+$" v == null then
            throw ''Invalid Node version: "${v}". Must be in the form "<major>", e.g. "22"''
          else
            v;
      in
      builtins.getAttr ("nodejs_" + version) pkgs
    else
      null;

  # Destroy dev environment
  destroyCmd = pkgs.writeShellApplication {
    name = "dev-env-destroy";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      #!/usr/bin/env bash
      set -e

      if [ -d "${devEnvPath}" ]; then
        echo "Destroying environment ..."
        rm -fr "${devEnvPath}" "${direnvPath}"

        ${
          if (pythonConfig.enable or false) && (venvConfig.enable or false) then
            ''rm -fr "${venvPath}"''
          else
            ""
        }

        ${
          if (javascriptConfig.enable or false) && (npmConfig.enable or false) then
            ''rm -fr "${nodeModulesPath}"''
          else
            ""
        }

        ${if pre-commit.enable then ''rm -f "${gitPath}/hooks/pre-commit"'' else ""}

        echo "Environment destroyed."
      else
        echo "${devEnvPath} not found"
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
      destroyCmd
    ]
    ++ pkgs.lib.optionals pre-commit.enable [ pkgs.pre-commit ]
    ++ pkgs.lib.optionals (pythonConfig.enable or false) [ pythonPkg ]
    ++ pkgs.lib.optionals (javascriptConfig.enable or false) [ nodePkg ];

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
      local checksum_file="${devEnvPath}/checksum-$normalized_name"
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
      local checksum_file="${devEnvPath}/checksum-$normalized_name"
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
      local checksum_file="${devEnvPath}/checksum-$normalized_name"
      rm -f "$file" "$checksum_file"
    }

    ${
      if (pythonConfig.enable or false) && (venvConfig.enable or false) then
        ''
          mkdir -p "${devEnvPath}"
          python_version="$(${pythonPkg}/bin/python --version | awk '{print $2}')"
          stored_requirements_file="${devEnvPath}/requirements.txt"

          if [ ! -d "${venvPath}" ]; then
            untrack_file "$stored_requirements_file"
          fi

          cat ${toString (venvConfig.requirements or [ ])} | sort | uniq > "$stored_requirements_file"
          export PYTHONPATH="${pythonPkg}/${pythonPkg.sitePackages}"

          if [ ! -d "${venvPath}" ]; then
            echo "Creating Python virtual environment: ${venvPath} ..."
            ${pythonPkg}/bin/python -m venv ${venvPath}
            source ${venvPath}/bin/activate
            pip install --upgrade pip setuptools wheel
          else
            source ${venvPath}/bin/activate
          fi

          if checksum_changed "$stored_requirements_file" "$python_version"; then
            echo "Installing Python dependencies: ${venvPath} ..."
            pip install -r "$stored_requirements_file"
            save_checksum "$stored_requirements_file" "$python_version"
          fi
        ''
      else
        ""
    }

    ${
      if (javascriptConfig.enable or false) && (npmConfig.enable or false) then
        ''
          mkdir -p "${devEnvPath}"
          node_version="$(${nodePkg}/bin/node --version | sed 's/^v//')"
          source_lock_file="${rootPath}/package-lock.json"
          stored_lock_file="${devEnvPath}/package-lock.json"

          if [ ! -d "${nodeModulesPath}" ]; then
            untrack_file "$stored_lock_file"
          fi

          if [ -f "$source_lock_file" ]; then
            cp -f "$source_lock_file" "$stored_lock_file"

            if [ ! -d "${nodeModulesPath}" ] || checksum_changed "$stored_lock_file" "$node_version"; then
              echo "Installing Node dependencies: ${nodeModulesPath} ..."
              ${nodePkg}/bin/npm ci
              save_checksum "$stored_lock_file" "$node_version"
            fi

            export PATH="${nodeModulesPath}/.bin:$PATH"
          else
            echo "$source_lock_file not found"
            exit 1
          fi
        ''
      else
        ""
    }

    ${
      if pre-commit.enable then
        ''
          if [ -d "${gitPath}" ]; then
            if [ ! -f "${gitPath}/hooks/pre-commit" ]; then
              echo "Installing pre-commit ..."
              pre-commit install
            fi
          else
            echo "${gitPath} not found"
            exit 1
          fi
        ''
      else
        ""
    }

    ${enterShell}
  '';
}
