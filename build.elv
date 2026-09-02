#!/usr/bin/env elvish
use path

pragma unknown-command = disallow

var script-dir = (path:dir (path:abs (src)[name]))

e:podman build ^
  --pull=missing ^
  --network=host ^
  --file (path:join $script-dir Containerfile) ^
  --build-arg USERNAME=(e:id -un) ^
  --build-arg USER_UID=(e:id -u) ^
  --build-arg USER_GID=(e:id -g) ^
  -t faradai:latest ^
  $script-dir
