with builtins; rec {
  eachSystem = systems: f:
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

  flattenToListWith = flattenFn: attrset: concatMap
    (v: 
      if isAttrs v && !lib.isDerivation v then flattenToListWith v
      else if isList v then v
      else if v != null then [v]
      else []
    ) (flattenFn attrset);

  flattenToList = flattenToListWith attrValues;

  flattenMapAttrLeaves = twoArgFn: attrset: 
    let 
      mapLeaves = attr: attrValues (mapAttrs (n: v:
        if isAttrs v then v
        else (twoArgFn n v)
      ) attr);
    in
    flattenToListWith mapLeaves attrset;


  # Getting python deps
  getDeps = attrname: map (plugin: plugin.${attrname} or (_: [ ]));

  combineFns = values: x: (builtins.map (value: value x) values);
}
