#!/bin/bash
#
# Hytale CamyHost - Entrypoint v3
#
# AUTO_UPDATE=0 -> Apenas inicia o servidor (rapido)
# AUTO_UPDATE=1 -> Baixa/atualiza o jogo antes de iniciar
# AUTO_AUTH=1   -> Gerencia autenticacao automaticamente
#

cd /home/container

echo "=========================================="
echo "       Hytale CamyHost v3"
echo "=========================================="
echo ""

# Arquivos de configuracao
SERVER_TOKENS=".hytale-server-tokens.json"
OAUTH_TOKENS=".hytale-oauth-tokens.json"

# Endpoints OAuth
OAUTH_DEVICE_URL="https://oauth.accounts.hytale.com/oauth2/device/auth"
OAUTH_TOKEN_URL="https://oauth.accounts.hytale.com/oauth2/token"
PROFILE_URL="https://account-data.hytale.com/my-account/get-profiles"
SESSION_URL="https://sessions.hytale.com/game-session/new"
CLIENT_ID="hytale-server"

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

# Funcao para renovar tokens OAuth usando refresh_token
refresh_oauth_tokens() {
    if [ ! -f "$OAUTH_TOKENS" ]; then
        return 1
    fi

    REFRESH_TOKEN=$(jq -r '.refresh_token' "$OAUTH_TOKENS" 2>/dev/null)
    if [ -z "$REFRESH_TOKEN" ] || [ "$REFRESH_TOKEN" = "null" ]; then
        return 1
    fi

    echo "[Auth] Renovando tokens OAuth..."
    RESPONSE=$(curl -s -X POST "$OAUTH_TOKEN_URL" \
        -d "client_id=$CLIENT_ID" \
        -d "grant_type=refresh_token" \
        -d "refresh_token=$REFRESH_TOKEN" 2>/dev/null)

    NEW_ACCESS=$(echo "$RESPONSE" | jq -r '.access_token' 2>/dev/null)
    NEW_REFRESH=$(echo "$RESPONSE" | jq -r '.refresh_token' 2>/dev/null)

    if [ -n "$NEW_ACCESS" ] && [ "$NEW_ACCESS" != "null" ]; then
        # Atualiza arquivo de tokens OAuth
        echo "$RESPONSE" | jq ". + {updated_at: \"$(date -Iseconds)\"}" > "$OAUTH_TOKENS"
        echo "[Auth] Tokens OAuth renovados!"
        return 0
    else
        echo "[Auth] Falha ao renovar tokens: $RESPONSE"
        rm -f "$OAUTH_TOKENS"
        return 1
    fi
}

# Funcao para obter session/identity tokens
get_session_tokens() {
    if [ ! -f "$OAUTH_TOKENS" ]; then
        return 1
    fi

    ACCESS_TOKEN=$(jq -r '.access_token' "$OAUTH_TOKENS" 2>/dev/null)
    if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
        return 1
    fi

    # Obtem profile
    echo "[Auth] Obtendo perfil..."
    PROFILE_RESPONSE=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$PROFILE_URL" 2>/dev/null)
    PROFILE_UUID=$(echo "$PROFILE_RESPONSE" | jq -r '.[0].uuid' 2>/dev/null)

    if [ -z "$PROFILE_UUID" ] || [ "$PROFILE_UUID" = "null" ]; then
        echo "[Auth] Erro ao obter perfil: $PROFILE_RESPONSE"
        return 1
    fi

    echo "[Auth] Profile: $PROFILE_UUID"

    # Cria sessao
    echo "[Auth] Criando sessao..."
    SESSION_RESPONSE=$(curl -s -X POST "$SESSION_URL" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"uuid\": \"$PROFILE_UUID\"}" 2>/dev/null)

    SESSION_TOKEN=$(echo "$SESSION_RESPONSE" | jq -r '.sessionToken' 2>/dev/null)
    IDENTITY_TOKEN=$(echo "$SESSION_RESPONSE" | jq -r '.identityToken' 2>/dev/null)

    if [ -n "$SESSION_TOKEN" ] && [ "$SESSION_TOKEN" != "null" ]; then
        cat > "$SERVER_TOKENS" << EOF
{
    "session_token": "$SESSION_TOKEN",
    "identity_token": "$IDENTITY_TOKEN",
    "profile_uuid": "$PROFILE_UUID",
    "created_at": "$(date -Iseconds)"
}
EOF
        echo "[Auth] Tokens de sessao obtidos!"
        return 0
    else
        echo "[Auth] Erro ao criar sessao: $SESSION_RESPONSE"
        return 1
    fi
}

# Funcao para iniciar device flow (primeira vez)
start_device_flow() {
    echo ""
    echo "=========================================="
    echo "   AUTENTICACAO NECESSARIA"
    echo "=========================================="
    echo ""
    echo "Iniciando OAuth Device Flow..."

    DEVICE_RESPONSE=$(curl -s -X POST "$OAUTH_DEVICE_URL" \
        -d "client_id=$CLIENT_ID" \
        -d "scope=openid offline auth:server" 2>/dev/null)

    DEVICE_CODE=$(echo "$DEVICE_RESPONSE" | jq -r '.device_code' 2>/dev/null)
    USER_CODE=$(echo "$DEVICE_RESPONSE" | jq -r '.user_code' 2>/dev/null)
    VERIFY_URL=$(echo "$DEVICE_RESPONSE" | jq -r '.verification_uri_complete // .verification_uri' 2>/dev/null)
    EXPIRES_IN=$(echo "$DEVICE_RESPONSE" | jq -r '.expires_in' 2>/dev/null)
    INTERVAL=$(echo "$DEVICE_RESPONSE" | jq -r '.interval // 5' 2>/dev/null)

    if [ -z "$DEVICE_CODE" ] || [ "$DEVICE_CODE" = "null" ]; then
        echo "[Auth] Erro ao iniciar device flow: $DEVICE_RESPONSE"
        return 1
    fi

    echo ""
    echo "==================================================================="
    echo "  ACESSE: $VERIFY_URL"
    echo "  CODIGO: $USER_CODE"
    echo "==================================================================="
    echo ""
    echo "Aguardando autorizacao (expira em ${EXPIRES_IN}s)..."

    # Poll para obter token
    ATTEMPTS=0
    MAX_ATTEMPTS=$((EXPIRES_IN / INTERVAL))

    while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
        sleep $INTERVAL
        ATTEMPTS=$((ATTEMPTS + 1))

        TOKEN_RESPONSE=$(curl -s -X POST "$OAUTH_TOKEN_URL" \
            -d "client_id=$CLIENT_ID" \
            -d "grant_type=urn:ietf:params:oauth:grant-type:device_code" \
            -d "device_code=$DEVICE_CODE" 2>/dev/null)

        ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token' 2>/dev/null)
        ERROR=$(echo "$TOKEN_RESPONSE" | jq -r '.error' 2>/dev/null)

        if [ -n "$ACCESS_TOKEN" ] && [ "$ACCESS_TOKEN" != "null" ]; then
            echo ""
            echo "[Auth] Autorizacao recebida!"
            echo "$TOKEN_RESPONSE" | jq ". + {created_at: \"$(date -Iseconds)\"}" > "$OAUTH_TOKENS"
            return 0
        elif [ "$ERROR" = "authorization_pending" ]; then
            echo -n "."
        elif [ "$ERROR" = "slow_down" ]; then
            INTERVAL=$((INTERVAL + 1))
        elif [ "$ERROR" = "expired_token" ] || [ "$ERROR" = "access_denied" ]; then
            echo ""
            echo "[Auth] Autorizacao expirada ou negada"
            return 1
        fi
    done

    echo ""
    echo "[Auth] Timeout aguardando autorizacao"
    return 1
}

# Funcao para carregar tokens de sessao
load_session_tokens() {
    if [ -f "$SERVER_TOKENS" ]; then
        export SESSION_TOKEN=$(jq -r '.session_token' "$SERVER_TOKENS" 2>/dev/null)
        export IDENTITY_TOKEN=$(jq -r '.identity_token' "$SERVER_TOKENS" 2>/dev/null)
        if [ -n "$SESSION_TOKEN" ] && [ "$SESSION_TOKEN" != "null" ]; then
            return 0
        fi
    fi
    return 1
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

# === AUTO AUTH ===
if [ "${AUTO_AUTH}" = "1" ]; then
    echo "[Auth] AUTO_AUTH=1 -> Verificando autenticacao..."

    AUTH_OK=false

    # 1. Tenta usar tokens de sessao existentes
    if load_session_tokens; then
        echo "[Auth] Tokens de sessao encontrados"
        AUTH_OK=true
    fi

    # 2. Se nao tem sessao, tenta renovar OAuth e criar sessao
    if [ "$AUTH_OK" = false ] && [ -f "$OAUTH_TOKENS" ]; then
        if refresh_oauth_tokens && get_session_tokens && load_session_tokens; then
            AUTH_OK=true
        fi
    fi

    # 3. Se ainda nao tem, inicia device flow
    if [ "$AUTH_OK" = false ]; then
        if start_device_flow && get_session_tokens && load_session_tokens; then
            AUTH_OK=true
        fi
    fi

    if [ "$AUTH_OK" = false ]; then
        echo "[Auth] Falha na autenticacao automatica"
        echo "[Auth] Use /auth login device no console do servidor"
    fi
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

# Monta argumentos de token
TOKEN_ARGS=""
if [ -n "$SESSION_TOKEN" ] && [ "$SESSION_TOKEN" != "null" ]; then
    TOKEN_ARGS="--session-token $SESSION_TOKEN"
    echo "[Auth] Session token: OK"
fi
if [ -n "$IDENTITY_TOKEN" ] && [ "$IDENTITY_TOKEN" != "null" ]; then
    TOKEN_ARGS="$TOKEN_ARGS --identity-token $IDENTITY_TOKEN"
    echo "[Auth] Identity token: OK"
fi

echo ""
exec /java.sh $TOKEN_ARGS "$@"
