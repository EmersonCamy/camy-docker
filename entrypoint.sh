#!/bin/bash
#
# Hytale CamyHost - Entrypoint v2
#
# AUTO_UPDATE=0 -> Apenas inicia o servidor (rapido)
# AUTO_UPDATE=1 -> Baixa/atualiza o jogo antes de iniciar
# AUTO_AUTH=1   -> Tenta autenticar automaticamente usando credenciais do downloader
#

cd /home/container

echo "=========================================="
echo "       Hytale CamyHost v2"
echo "=========================================="
echo ""

# Arquivo para salvar tokens do servidor
TOKENS_FILE=".hytale-server-tokens.json"
DOWNLOADER_CREDS=".hytale-downloader-credentials.json"

# Funcao para baixar/atualizar o servidor
download_server() {
    echo "[Download] Iniciando download do Hytale..."

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

# Funcao para obter tokens via API
get_server_tokens() {
    echo "[Auth] Tentando obter tokens do servidor..."

    # Verifica se tem credenciais do downloader
    if [ ! -f "$DOWNLOADER_CREDS" ]; then
        echo "[Auth] Credenciais do downloader nao encontradas"
        return 1
    fi

    # Extrai access_token das credenciais do downloader
    ACCESS_TOKEN=$(jq -r '.access_token' "$DOWNLOADER_CREDS" 2>/dev/null)

    if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
        echo "[Auth] Access token nao encontrado nas credenciais"
        return 1
    fi

    # Obtem o profile UUID
    echo "[Auth] Obtendo perfil..."
    PROFILE_RESPONSE=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
        "https://sessions.hytale.com/my-account/get-profiles" 2>/dev/null)

    PROFILE_UUID=$(echo "$PROFILE_RESPONSE" | jq -r '.[0].uuid' 2>/dev/null)

    if [ -z "$PROFILE_UUID" ] || [ "$PROFILE_UUID" = "null" ]; then
        echo "[Auth] Nao foi possivel obter profile UUID"
        echo "[Auth] Resposta: $PROFILE_RESPONSE"
        return 1
    fi

    echo "[Auth] Profile UUID: $PROFILE_UUID"

    # Cria nova sessao de jogo
    echo "[Auth] Criando sessao do servidor..."
    SESSION_RESPONSE=$(curl -s -X POST \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"uuid\": \"$PROFILE_UUID\"}" \
        "https://sessions.hytale.com/game-session/new" 2>/dev/null)

    SESSION_TOKEN=$(echo "$SESSION_RESPONSE" | jq -r '.sessionToken' 2>/dev/null)
    IDENTITY_TOKEN=$(echo "$SESSION_RESPONSE" | jq -r '.identityToken' 2>/dev/null)

    if [ -z "$SESSION_TOKEN" ] || [ "$SESSION_TOKEN" = "null" ]; then
        echo "[Auth] Nao foi possivel obter session token"
        echo "[Auth] Resposta: $SESSION_RESPONSE"
        return 1
    fi

    # Salva tokens no arquivo
    echo "[Auth] Salvando tokens..."
    cat > "$TOKENS_FILE" << EOF
{
    "session_token": "$SESSION_TOKEN",
    "identity_token": "$IDENTITY_TOKEN",
    "profile_uuid": "$PROFILE_UUID",
    "created_at": "$(date -Iseconds)"
}
EOF

    echo "[Auth] Tokens salvos com sucesso!"
    return 0
}

# Funcao para carregar tokens salvos
load_saved_tokens() {
    if [ -f "$TOKENS_FILE" ]; then
        SAVED_SESSION=$(jq -r '.session_token' "$TOKENS_FILE" 2>/dev/null)
        SAVED_IDENTITY=$(jq -r '.identity_token' "$TOKENS_FILE" 2>/dev/null)

        if [ -n "$SAVED_SESSION" ] && [ "$SAVED_SESSION" != "null" ]; then
            echo "[Auth] Tokens salvos encontrados!"
            export SESSION_TOKEN="$SAVED_SESSION"
            export IDENTITY_TOKEN="$SAVED_IDENTITY"
            return 0
        fi
    fi
    return 1
}

# Verifica AUTO_UPDATE
if [ "${AUTO_UPDATE}" = "1" ]; then
    echo "[Config] AUTO_UPDATE=1 -> Verificando atualizacoes..."
    download_server
else
    echo "[Config] AUTO_UPDATE=0 -> Iniciando sem baixar"
fi

# Verifica arquivos do servidor
if [ ! -f "Server/HytaleServer.jar" ]; then
    echo "[ERRO] Server/HytaleServer.jar nao encontrado!"
    exit 1
fi

if [ ! -f "Assets.zip" ]; then
    echo "[ERRO] Assets.zip nao encontrado!"
    exit 1
fi

# === AUTO AUTH ===
if [ "${AUTO_AUTH}" = "1" ]; then
    echo ""
    echo "[Auth] AUTO_AUTH=1 -> Verificando autenticacao..."

    # Tenta carregar tokens salvos primeiro
    if load_saved_tokens; then
        echo "[Auth] Usando tokens salvos"
    else
        # Tenta obter novos tokens via API
        if get_server_tokens; then
            load_saved_tokens
        else
            echo "[Auth] Falha ao obter tokens automaticamente"
            echo "[Auth] Voce precisara fazer login manual: /auth login device"
        fi
    fi
else
    # Se AUTO_AUTH desativado, ainda tenta carregar tokens salvos
    if load_saved_tokens; then
        echo "[Auth] Tokens salvos carregados"
    fi
fi

# Instala plugin SourceQuery se solicitado
if [ "${INSTALL_SOURCEQUERY_PLUGIN}" = "1" ]; then
    echo ""
    echo "[Plugin] Verificando SourceQuery plugin..."
    mkdir -p mods
    PLUGIN_URL=$(curl -s https://api.github.com/repos/Jenya705/hytale-sourcequery/releases/latest \
        | jq -r '.assets[0].browser_download_url' 2>/dev/null)
    if [ -n "$PLUGIN_URL" ] && [ "$PLUGIN_URL" != "null" ]; then
        curl -sL "$PLUGIN_URL" -o mods/hytale-sourcequery.jar
        echo "[Plugin] SourceQuery instalado!"
    fi
fi

# Configura MaxViewRadius se definido
if [ -f "config.json" ] && [ -n "${HYTALE_MAX_VIEW_RADIUS}" ]; then
    echo "[Config] Configurando MaxViewRadius=${HYTALE_MAX_VIEW_RADIUS}..."
    jq ".MaxViewRadius = ${HYTALE_MAX_VIEW_RADIUS}" config.json > config.json.tmp \
        && mv config.json.tmp config.json
fi

echo ""
echo "=========================================="
echo "   Iniciando Hytale Server..."
echo "=========================================="

# Monta argumentos de token se disponiveis
TOKEN_ARGS=""
if [ -n "$SESSION_TOKEN" ] && [ "$SESSION_TOKEN" != "null" ]; then
    TOKEN_ARGS="$TOKEN_ARGS --session-token $SESSION_TOKEN"
    echo "[Auth] Session token configurado"
fi
if [ -n "$IDENTITY_TOKEN" ] && [ "$IDENTITY_TOKEN" != "null" ]; then
    TOKEN_ARGS="$TOKEN_ARGS --identity-token $IDENTITY_TOKEN"
    echo "[Auth] Identity token configurado"
fi

echo ""

# Inicia o servidor
exec /java.sh $TOKEN_ARGS "$@"
