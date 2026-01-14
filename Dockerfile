#
# Java Game Server - Docker Image
#

FROM        --platform=$TARGETOS/$TARGETARCH ghcr.io/pterodactyl/yolks:java_25

LABEL       author="CamyHost"
LABEL       org.opencontainers.image.source="https://github.com/EmersonCamy/camy-docker"
LABEL       org.opencontainers.image.description="Java Game Server"
LABEL       org.opencontainers.image.licenses=MIT

USER        root

COPY        --from=ghcr.io/pterodactyl/yolks:java_25 /entrypoint.sh /java.sh
RUN         chmod +x /java.sh

RUN         apt-get update -y \
            && apt-get install -y unzip jq curl \
            && rm -rf /var/lib/apt/lists/*

COPY        ./entrypoint.sh /entrypoint.sh
RUN         chmod +x /entrypoint.sh

USER        container
ENV         USER=container HOME=/home/container
WORKDIR     /home/container

CMD         [ "/bin/bash", "/entrypoint.sh" ]
