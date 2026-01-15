#!/bin/bash
#
# Hytale CamyHost - Entrypoint
#
# AUTO_UPDATE=0 -> Apenas inicia o servidor (rapido)
# AUTO_UPDATE=1 -> Baixa/atualiza o jogo antes de iniciar
#

cd /home/container

echo "=========================================="
echo "       Hytale CamyHost"
echo "=========================================="
echo ""

# Funcao para baixar/atualizar o servidor
download_server() {
    echo "[Download] Iniciando download do Hytale..."
    if [ ! -f "hytale-downloader/hytale-downloader-linux" ]; then
        echo "[Download] Downloader nao encontrado! Execute Reinstall."
        exit 1
    fi
    PATCHLINE="${HYTALE_PATCHLINE:-release}"
    ./hytale-downloader/hytale-downloader-linux \
        -patchline "$PATCHLINE" -skip-update-check -download-path game.zip
    if [ -f "game.zip" ]; then
        unzip -oq game.zip && rm -f game.zip
        echo "[Download] Concluido!"
    else
        echo "[Download] ERRO: Falha no download"
        exit 1
    fi
}

# === INICIO ===

# Verifica AUTO_UPDATE
if [ "${AUTO_UPDATE}" = "1" ]; then
    echo "[Config] AUTO_UPDATE=1 -> Atualizando..."
    download_server
fi

# Verifica arquivos
if [ ! -f "Server/HytaleServer.jar" ] || [ ! -f "Assets.zip" ]; then
    echo "[ERRO] Arquivos do servidor nao encontrados! Execute Reinstall."
    exit 1
fi

# Plugins e config
if [ "${INSTALL_SOURCEQUERY_PLUGIN}" = "1" ]; then
    mkdir -p mods
    PLUGIN_URL=$(curl -s https://api.github.com/repos/Jenya705/hytale-sourcequery/releases/latest \
        | jq -r '.assets[0].browser_download_url' 2>/dev/null)
    [ -n "$PLUGIN_URL" ] && [ "$PLUGIN_URL" != "null" ] && \
        curl -sL "$PLUGIN_URL" -o mods/hytale-sourcequery.jar
fi

if [ -f "config.json" ] && [ -n "${HYTALE_MAX_VIEW_RADIUS}" ]; then
    jq ".MaxViewRadius = ${HYTALE_MAX_VIEW_RADIUS}" config.json > config.json.tmp \
        && mv config.json.tmp config.json
fi

echo ""
echo "=========================================="
echo "   Iniciando Hytale Server..."
echo "=========================================="
echo ""

# Se modo autenticado, envia comando de auth automaticamente apos o servidor iniciar
if [ "${HYTALE_AUTH_MODE}" = "authenticated" ]; then
    echo "[CamyHost] Modo autenticado - enviando /auth login device automaticamente..."
    {
        sleep 20  # Aguarda servidor iniciar
        echo "/auth login device"
        cat  # Continua passando input do usuario
    } | /java.sh "$@"
else
    exec /java.sh "$@"
fi
