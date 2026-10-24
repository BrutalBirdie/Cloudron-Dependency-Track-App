#!/bin/bash

set -eu

cd /app/code/apiserver

# flags from upstream image CMD - https://github.com/DependencyTrack/dependency-track/blob/main/apiserver/src/main/docker/Dockerfile
exec java ${JAVA_OPTIONS} \
    --add-opens java.base/java.util.concurrent=ALL-UNNAMED \
    --enable-native-access=ALL-UNNAMED \
    --sun-misc-unsafe-memory-access=allow \
    -Djdk.http.auth.tunneling.disabledSchemes= \
    -cp 'dependency-track-apiserver.jar:lib/*' \
    org.dependencytrack.Application \
    -context /
