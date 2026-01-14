#
# Hytale Server Docker Image - Com controle de Auto-Update
# Baseado em ghcr.io/pterodactyl/yolks:java_25
#
# Build: docker build -t seu-usuario/hytale-server:latest .
# Push:  docker push seu-usuario/hytale-server:latest
#

FROM        --platform=$TARGETOS/$TARGETARCH ghcr.io/pterodactyl/yolks:java_25

LABEL       author="EmersonCamy"
LABEL       org.opencontainers.image.source="https://github.com/EmersonCamy/hytale-docker"
LABEL       org.opencontainers.image.description="Hytale Server with optional auto-update"
LABEL       org.opencontainers.image.licenses=MIT

USER        root

# Copia o entrypoint original do Java para /java.sh (usado para iniciar o servidor)
COPY        --from=ghcr.io/pterodactyl/yolks:java_25 /entrypoint.sh /java.sh
RUN         chmod +x /java.sh

# Instala dependencias necessarias
RUN         apt-get update -y \
            && apt-get install -y unzip jq curl \
            && rm -rf /var/lib/apt/lists/*

# Copia o entrypoint personalizado (antes de mudar de usuario)
COPY        ./entrypoint.sh /entrypoint.sh
RUN         chmod +x /entrypoint.sh

USER        container
ENV         USER=container HOME=/home/container
WORKDIR     /home/container

CMD         [ "/bin/bash", "/entrypoint.sh" ]
