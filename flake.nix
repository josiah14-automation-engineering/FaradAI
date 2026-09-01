{
  inputs = {
    mise.url = "git+https://github.com/josiah14/mise.git";
    nixpkgs.follows = "mise/nixpkgs";
  };

  outputs =
    {
      self,
      mise,
      nixpkgs,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      devShells = forAllSystems (system: {
        default = nixpkgs.legacyPackages.${system}.mkShell {
          packages =
            mise.lib.${system}.go-1-26-3
            ++ mise.lib.${system}.elvish-0-21-0
            ++ mise.lib.${system}.bats-1-12-0
            ++ mise.lib.${system}.hadolint-2-14-0
            ++ mise.lib.${system}.podman-5-8-2;
        };
      });
    };
}
