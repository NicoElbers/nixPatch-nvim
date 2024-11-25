{ lib, stdenv, makeWrapper, neovim-node-client }:
{
  name
  , withNodeJs
  , withRuby
  , rubyEnv ? null
  , withPerl
  , perlEnv ? null
  , withPython3
  , python3Env ? null
  , extraPython3WrapperArgs ? []
}:
stdenv.mkDerivation {
  name = "${name}-providers";

  __structuredAttrs = true;
  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  # Link all the providers into one directory
  postBuild = 
      ""
      + lib.optionalString withPython3 ''
        makeWrapper ${python3Env.interpreter} $out/bin/${name}-python3 --unset PYTHONPATH ${builtins.concatStringsSep " " extraPython3WrapperArgs}
      ''
      + lib.optionalString withRuby ''
        ln -s ${rubyEnv}/bin/neovim-ruby-host $out/bin/${name}-ruby
      ''
      + lib.optionalString withNodeJs ''
        ln -s ${neovim-node-client}/bin/neovim-node-host $out/bin/${name}-node
      ''
      + lib.optionalString withPerl ''
        ln -s ${perlEnv}/bin/perl $out/bin/${name}-perl
      '';
}
