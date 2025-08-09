{ pkgs, lib ? pkgs.lib }:

let
  normalizeV5 = import ./normalize-v5.nix { inherit pkgs lib; };
  # normalizeV9 will be wired in a subsequent step.
in raw:
  let
    # lockfileVersion may be a string or number; handle both
    rawVersion = if (builtins.hasAttr "lockfileVersion" raw) then raw.lockfileVersion else null;
    versionStr = if builtins.isString rawVersion then rawVersion else (toString rawVersion);
    majorStr = builtins.elemAt (lib.splitString "." versionStr) 0;
    major = lib.toInt majorStr;
  in if major == 5 then
    normalizeV5 raw
  else if major == 9 then
    throw "lockfile v9 normalization not implemented yet"
  else
    throw "Unsupported pnpm lockfileVersion: ${versionStr}"


