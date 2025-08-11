let
  pkgs = import <nixpkgs> { };
  dev-env = import (
    builtins.fetchTarball {
      url = "https://github.com/netbek/dev-env/archive/refs/tags/v1.0.3.tar.gz";
    }
  );
  rootPath = builtins.toString ./.;
in
dev-env {
  inherit pkgs rootPath;

  packages = [
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
      version = "3.12";
      venv = {
        enable = true;
        requirements = [
          ./development_requirements.txt
          ./production_requirements.txt
        ];
      };
    };
  };

  # pre-commit = {
  #   enable = true;
  # };
}
