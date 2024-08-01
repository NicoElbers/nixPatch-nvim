{
  description = "My neovim config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nv = {
      url = "github:NicoElbers/nv";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nv, ... }: 
  let
    # Copied from flake utils
    eachSystem = with builtins; systems: f:
        let
        # Merge together the outputs for all systems.
        op = attrs: system:
          let
          ret = f system;
          op = attrs: key: attrs //
            {
              ${key} = (attrs.${key} or { })
              // { ${system} = ret.${key}; };
            }
          ;
          in
          foldl' op attrs (attrNames ret);
        in
        foldl' op { }
        (systems
          ++ # add the current system if --impure is used
          (if builtins ? currentSystem then
             if elem currentSystem systems
             then []
             else [ currentSystem ]
          else []));
    
    forEachSystem = eachSystem nixpkgs.lib.platforms.all;
  in 
  let
    # Easily configure a custom name, this will affect the name of the standard
    # executable, you can add as many aliases as you'd like in the configuration.
    name = "nv";

    # Any custom package config you would like to do.
    extra_pkg_config = {
        # allow_unfree = true;
    };

    configuration = { pkgs, ... }: 
    let
      patchUtils = pkgs.callPackage ./patchUtils.nix {};
    in 
    {
      # The path to your neovim configuration.
      luaPath = ./.;

      # Plugins you use in your configuration.
      plugins = with pkgs.vimPlugins; [ ];

      # Runtime dependencies. This is thing like tree-sitter, lsps or programs
      # like ripgrep.
      runtimeDeps = with pkgs; [ ];

      # Environment variables set during neovim runtime.
      environmentVariables = { };

      # Aliases for the patched config
      aliases = [ "vim" "vi" ];

      # Extra wrapper args you want to pass.
      # Look here if you don't know what those are:
      # https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/setup-hooks/make-wrapper.sh
      extraWrapperArgs = [ ];

      # Extra python packages for the neovim provider.
      # This must be a list of functions returning lists.
      python3Packages = [ ];

      # Wrapper args but then for the python provider.
      extraPython3WrapperArgs = [ ];

      # Extra lua packages for the neovim lua runtime.
      luaPackages = [ ]; # FIXME: why is this not being used????

      # Extra packages that should be available at build time for packages.
      propagatedBuildInputs = [ ]; # FIXME: why is this not being used????

      # Extra shared libraries available at runtime.
      sharedLibraries = [ ];

      # Extra lua configuration put at the top of your init.lua
      # This cannot replace your init.lua, if none exists in your configuration
      # this will not be writtern. 
      # Must be provided as a list of strings.
      extraConfig = [ ];

      # Custom subsitutions you want the patcher to make. They must be provided
      # in the following format
      # {
      #   type = "string" or "plugin";
      #   from = string literal or plugin url
      #   to = The string literal replacing "from"
      #   extra = for type "string" this is the "key" of the string as seen here:
      #           `key = "string"`
      #           leave as null if you don't care about the key.
      #           For type "plugin" this is the plugin name
      # }
      # TODO: Expose functions to make this much easier on the user
      customSubs = with pkgs.vimPlugins patchUtils; [ ];

      settings = {
        # Enable the NodeJs provider
        withNodeJs = false;

        # Enable the ruby provider
        withRuby = false;

        # Enable the perl provider
        withPerl = false;

        # Enable the python3 provider
        withPython3 = false;

        # Any extra name 
        extraName = "";

        # The default config directory for neovim
        configDirName = "nvim";

        # Any other neovim package you would like to use, for example nightly
        neovim-unwrapped = null;

        # Whether to add custom subsitution made in the original repo, makes for
        # a better out of the box experience 
        patchSubs = true;

        # Whether to add runtime dependencies to the back of the path
        suffix-path = false;

        # Whether to add shared libraries dependencies to the back of the path
        suffix-LD = false;
      };
    };
  in 
  forEachSystem (system: {
    packages.default = 
      nv.configWrapper.${system} { inherit configuration extra_pkg_config name; };
  });
}
