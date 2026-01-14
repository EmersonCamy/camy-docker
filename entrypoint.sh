#!/bin/bash
#
# Hytale Server Entrypoint - Com controle de Auto-Update
#
# AUTO_UPDATE=0 -> Apenas inicia o servidor (rapido)
# AUTO_UPDATE=1 -> Baixa/atualiza o jogo antes de iniciar
#

set -e
cd /home/container

echo "=========================================="
echo "   Hytale Server - Entrypoint"
echo "=========================================="
echo ""

# Funcao para baixar/atualizar o servidor
download_server() {
    echo "[Download] Iniciando download do Hytale..."

    # Verifica se o downloader existe
    if [ ! -f "hytale-downloader/hytale-downloader-linux" ]; then
        echo "[Download] Downloader nao encontrado!"
        echo "[Download] Execute 'Reinstall' no painel primeiro."
        exit 1
    fi

    PATCHLINE="${HYTALE_PATCHLINE:-release}"
    echo "[Download] Patchline: $PATCHLINE"

    ./hytale-downloader/hytale-downloader-linux \
        -patchline "$PATCHLINE" \
        -skip-update-check \
        -download-path game.zip

    if [ -f "game.zip" ]; then
        echo "[Download] Extraindo arquivos..."
        unzip -oq game.zip
        rm -f game.zip
        echo "[Download] Concluido!"
    else
        echo "[Download] ERRO: Falha no download"
        exit 1
    fi
}

# Verifica AUTO_UPDATE
if [ "${AUTO_UPDATE}" = "1" ]; then
    echo "[Config] AUTO_UPDATE=1 -> Verificando atualizacoes..."
    download_server
else
    echo "[Config] AUTO_UPDATE=0 -> Iniciando sem baixar"
fi

# Verifica se os arquivos do servidor existem
if [ ! -f "Server/HytaleServer.jar" ]; then
    echo ""
    echo "[ERRO] Server/HytaleServer.jar nao encontrado!"
    echo "[ERRO] Execute 'Reinstall' no painel ou defina AUTO_UPDATE=1"
    exit 1
fi

if [ ! -f "Assets.zip" ]; then
    echo ""
    echo "[ERRO] Assets.zip nao encontrado!"
    echo "[ERRO] Execute 'Reinstall' no painel ou defina AUTO_UPDATE=1"
    exit 1
fi

# Instala plugin SourceQuery se solicitado
if [ "${INSTALL_SOURCEQUERY_PLUGIN}" = "1" ]; then
    echo ""
    echo "[Plugin] Verificando SourceQuery plugin..."
    mkdir -p mods

    # Busca a ultima release do plugin
    PLUGIN_URL=$(curl -s https://api.github.com/repos/Jenya705/hytale-sourcequery/releases/latest \
        | jq -r '.assets[0].browser_download_url' 2>/dev/null)

    if [ -n "$PLUGIN_URL" ] && [ "$PLUGIN_URL" != "null" ]; then
        echo "[Plugin] Baixando SourceQuery..."
        curl -sL "$PLUGIN_URL" -o mods/hytale-sourcequery.jar
        echo "[Plugin] SourceQuery instalado!"
    else
        echo "[Plugin] Nao foi possivel obter URL do plugin"
    fi
fi

# Configura MaxViewRadius se definido
if [ -f "config.json" ] && [ -n "${HYTALE_MAX_VIEW_RADIUS}" ]; then
    echo ""
    echo "[Config] Configurando MaxViewRadius=${HYTALE_MAX_VIEW_RADIUS}..."
    jq ".MaxViewRadius = ${HYTALE_MAX_VIEW_RADIUS}" config.json > config.json.tmp \
        && mv config.json.tmp config.json
fi

echo ""
echo "=========================================="
echo "   Iniciando Hytale Server..."
echo "=========================================="
echo ""

# Inicia o servidor usando o java.sh do Pterodactyl
exec /java.sh "$@"
