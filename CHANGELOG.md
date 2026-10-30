# Changelog

- A Jetson enrolled by jetson.sh can run its class (2026-10-30, #1). The script
  installs community.docker and python3-requests, without which the update
  fails while loading or cannot reach the daemon, and docker.io where no docker
  is installed, without which the update stops at "this board has no container
  runtime".
