{
  description = "Super thin wrapper around neovim";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    zig = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zls = {
      # Last commit on 0.13.0
      url = "github:zigtools/zls?rev=a26718049a8657d4da04c331aeced1697bc7652b";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";
  };

  outputs = { nixpkgs, zig, zls, ... }@inputs: 
  let
    name = "nv";

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
    let
      patchUtils = pkgs.callPackage ./patchUtils.nix {};
    in 
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

        nvim-dap # rustaceanvim dep

        # treesitter
        nvim-treesitter-textobjects
        (nvim-treesitter.withPlugins (
          plugins: with plugins; [
            asm
            bash
            bibtex
            c
            cpp
            css
            html
            http
            javascript
            lua
            make
            markdown
            markdown_inline
            nix
            python
            rust
            toml
            typescript
            vim
            vimdoc
            xml
            yaml

            comment
            diff
            git_config
            git_rebase
            gitcommit
            gitignore
            gpg
            jq
            json
            json5
            llvm
            ssh_config
          ]
        ))

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

        # Zig sucks bc the LSP is only suported for master
        # inputs.zls.packages.${pkgs.system}.zls

        # Rust
        rust-analyzer
        cargo
        rustc

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

      # Extra python3 packages (must be functions returning lists)
      extraPython3Packages = with pkgs; [ ];

      # Extra Lua packages (must be functions returning lists)
      extraLuaPackages = with pkgs; [ ];

      # Shared libraries available at run time
      sharedLibraries = with pkgs; [ ];

      aliases = [ "vim" "vi" ];

      customSubs = with pkgs.vimPlugins patchUtils; [

      ];

      settings = {
        withNodeJs = true;
        withRuby = true;
        withPerl = true;
        withPython3 = true;
        extraName = "";
        configDirName = "nvim";
        aliases = null;
        # neovim-unwrapped = null;
        neovim-unwrapped = inputs.neovim-nightly-overlay.packages.${pkgs.system}.neovim;
        patchSubs = true;
        suffix-path = false;
        suffix-LD = false;
        disablePythonSafePath = false;
      };
    };
  in 
  forEachSystem (system: 
  let
    inherit (builders) baseBuilder zigBuilder patcherBuilder;
    pkgs = nixpkgs.legacyPackages.${system}; # Get a copy of pkgs here for dev shells

    patcher = pkgs.callPackage zigBuilder {};

    configPatcher = (pkgs.callPackage patcherBuilder {}) {
      inherit nixpkgs patcher;
    };

    configWrapper = baseBuilder configPatcher {
      inherit nixpkgs system dependencyOverlays;
    };
  in {
    packages = rec {
      default = nv;
      nv = configWrapper { inherit configuration extra_pkg_config name; };
    };

    inherit configWrapper;

    devShells.default = with pkgs; mkShell {
      packages = [
        zig.packages.${system}."0.13.0"
        zls.packages.${system}.zls
      ];
    };
  }) // {
    templates = import ./templates;
  };
}

