{ lib }:
rec {
  urlSub = url: plugin:
    [{
      type = "plugin";
      from = "${url}";
      to = "${plugin}";
      extra = "${plugin.pname}";
    }];
  githubUrlSub = shortUrl: plugin:
    (urlSub shortUrl plugin)
    ++ (urlSub "https://github.com/${shortUrl}" plugin);
  stringSub = from: to: 
    [{
      type = "string";
      from = from;
      to = to;
      extra = null;
    }];
  keyedStringSub = from: to: key: 
    [{
      type = "string";
      from = from;
      to = to;
      extra = key;
    }];

  hasPlugin = plugins: plugin: lib.lists.any (p: p == plugin) plugins;
  optPatch = plugins: plugin: sub: lib.optionals (hasPlugin plugins plugin) sub;
}
