# Copied verbatim from https://github.com/Gerg-L/mnw/blob/4ea225024677e7c3a96080af8624fd3aa5dfa1b6/ruby_provider/gemset.nix
{
  msgpack = {
    groups = [ "default" ];
    platforms = [ ];
    source = {
      remotes = [ "https://rubygems.org" ];
      sha256 = "1a5adcb7bwan09mqhj3wi9ib52hmdzmqg7q08pggn3adibyn5asr";
      type = "gem";
    };
    version = "1.7.2";
  };
  multi_json = {
    groups = [ "default" ];
    platforms = [ ];
    source = {
      remotes = [ "https://rubygems.org" ];
      sha256 = "sha256-H9BBOLbkqQAX6NG4BMA5AxOZhm/z+6u3girqNnx4YV0=";
      type = "gem";
    };
    version = "1.15.0";
  };
  neovim = {
    dependencies = [
      "msgpack"
      "multi_json"
    ];
    groups = [ "default" ];
    platforms = [ ];
    source = {
      remotes = [ "https://rubygems.org" ];
      sha256 = "0gl34rriwwmj6p1s6ms0b311wmqaqiyc510svq31283jk0kp0qcd";
      type = "gem";
    };
    version = "0.10.0";
  };
}
