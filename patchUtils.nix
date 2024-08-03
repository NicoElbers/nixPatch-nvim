{ lib }:
rec {
  # This will create a plugin substitution. To be exact, it will look for either
  # `url = "${url}"` or `"${url}"` and change it to
  # `dir = [[${plugin}]], name = [[${plugin.pname}]]`
  # Any type of lua string will work, `''` `""` or `[[]]`, any amount of whitespace
  # beteen 'url', '=' and ${url} will work.
  urlSub = url: plugin:
    [{
      type = "plugin";
      from = "${url}";
      to = "${plugin}";
      extra = "${plugin.pname}";
    }];

  # This will create 2 plugin substitutions as per the `urlSub` function.
  # One with the url being the shortUrl passed in, and another with
  # "https://github.com/${shortUrl}"
  githubUrlSub = shortUrl: plugin:
    (urlSub shortUrl plugin)
    ++ (urlSub "https://github.com/${shortUrl}" plugin);

  # This will substitute the lua string "${from}" to "${to}". 
  # Any type of lua string will work, `''` `""` or `[[]]`.
  stringSub = from: to: 
    [{
      type = "string";
      from = from;
      to = to;
      extra = null;
    }];

  # This will substitute the lua string "${from}" to "${to}" if and only if
  # the string has a key "${key}".
  # In practise this transforms 
  # `${key} = [[${from}]]` 
  # to
  # `${key} = [[${to}]]`
  # Any type of lua string will work, `''` `""` or `[[]]`, any amount of whitespace
  # beteen ${key}, '=' and ${from} will work.
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
