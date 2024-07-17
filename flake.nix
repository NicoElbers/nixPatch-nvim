{
  description = "Super thin wrapper around neovim";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    # neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";
  };

  outputs = { nixpkgs, ... }@inputs: 
  let
    utils = (import ./nix/utils);
    forEachSystem = utils.eachSystem nixpkgs.lib.platforms.all;
    builders = (import ./nix/builders);

    inherit (forEachSystem (system: 
      let
        dependencyOverlays = [ ];
      in 
      { inherit dependencyOverlays; })) dependencyOverlays;

    extra_pkg_config = {
      allow_unfree = true;
    };


    configuration = { pkgs, ... }:
    {
      # The path to your config
      luaPath = ./config;
      ##########################

      # Plugins 
      # Any plugins not under vimPlugins need to have custom substitutions
      # plugins = with pkgs.vimPlugins; [ ];
      plugins = with pkgs.vimPlugins; [
        # lazy
        lazy-nvim

        # completions
        nvim-cmp
        cmp_luasnip
        luasnip
        friendly-snippets
        cmp-path
        cmp-buffer
        cmp-nvim-lua
        cmp-nvim-lsp
        cmp-nvim-lsp-signature-help

        # telescope
        plenary-nvim
        telescope-nvim
        telescope-undo-nvim
        telescope-ui-select-nvim
        telescope-fzf-native-nvim
        todo-comments-nvim
        trouble-nvim

        # Formatting
        conform-nvim

        # lsp
        nvim-lspconfig
        fidget-nvim
        neodev-nvim
        rustaceanvim
        none-ls-nvim

        # treesitter
        nvim-treesitter-textobjects
        nvim-treesitter.withAllGrammars

        # ui
        lualine-nvim
        nvim-web-devicons
        gitsigns-nvim
        nui-nvim
        neo-tree-nvim
        undotree

        # Color scheme
        onedark-nvim
        catppuccin-nvim
        tokyonight-nvim

        #misc
        vimtex
        comment-nvim
        vim-sleuth
        indent-blankline-nvim
        markdown-preview-nvim
        image-nvim
        autoclose-nvim
      ];


      # Runtime dependencies (think LSPs)
      # runtimeDeps = with pkgs; [ ];
      runtimeDeps = with pkgs; [ 
        universal-ctags
        tree-sitter
        ripgrep
        fd
        gcc
        nix-doc

        # lsps
        lua-language-server
        nodePackages_latest.typescript-language-server
        emmet-language-server
        tailwindcss-language-server
        llvmPackages_18.clang-unwrapped
        nil
        marksman
        pyright
        # inputs.zls.packages.${pkgs.system}.zls
        rust-analyzer

        # Formatters
        prettierd
        stylua
        black
        rustfmt
        checkstyle
        languagetool-rust

        # latex
        texliveFull

        # Clipboard
        wl-clipboard-rs
      ];

      # Evironment variables available at run time
      environmentVariables = { };

      # Have a look here https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/setup-hooks/make-wrapper.sh
      extraWrapperArgs = [ ];

      # Extra python3 packages
      extraPython3Packages = with pkgs; [ ];

      # Extra Lua packages
      extraLuaPackages = with pkgs; [ ];

      # Dependencies available at build time
      propagatedBuildInputs = with pkgs; [ ];

      # Shared libraries available at run time
      sharedLibraries = with pkgs; [ ];

      aliases = [ "vim" "vi" ];

      settings = {
        withNodeJs = true;
        withRuby = true;
        withPerl = true;
        withPython3 = true;
        extraName = "";
        configDirName = "nvim";
        aliases = null;
        neovim-unwrapped = null;
        # neovim-unwrapped = inputs.neovim-nightly-overlay.packages.${pkgs.system}.neovim;

        suffix-path = false;
        suffix-LD = false;
        disablePythonSafePath = false;
      };
    };
  in 
  forEachSystem (system: 
  let
    inherit (builders) baseBuilder;
    pkgs = nixpkgs.legacyPackages.${system}; # Get a copy of pkgs here for dev shells

    # neovim-nightly = inputs.neovim-nightly-overlay.packages.${system}.neovim;

    configWrapper = baseBuilder {
      inherit nixpkgs system dependencyOverlays;
    };
  in {
    packages = {
      default = configWrapper { inherit configuration extra_pkg_config; };
    };
    devShells.default = with pkgs; mkShell {
      packages = [
        zig
        hello
      ];
    };
  }); 
}

