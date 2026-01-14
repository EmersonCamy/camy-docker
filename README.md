# Hytale Server - Imagem Docker Personalizada

Imagem Docker para Pterodactyl com controle de AUTO_UPDATE.

## Problema que resolve

A imagem oficial `ghcr.io/pterodactyl/games:hytale` baixa o jogo **toda vez** que o servidor inicia. Esta imagem permite escolher:
- `AUTO_UPDATE=0` - Inicia rapido, sem baixar
- `AUTO_UPDATE=1` - Baixa/atualiza antes de iniciar

## Como usar

### Opcao 1: Usar GitHub Container Registry (Recomendado)

1. Faca fork deste repositorio no GitHub
2. Habilite GitHub Actions
3. A imagem sera publicada automaticamente em `ghcr.io/SEU-USUARIO/hytale-server:latest`

### Opcao 2: Build manual e push para Docker Hub

```bash
# Clone o repositorio
cd docker-image

# Build da imagem
docker build -t seu-usuario/hytale-server:latest .

# Push para Docker Hub
docker login
docker push seu-usuario/hytale-server:latest
```

### Opcao 3: Build manual e push para GHCR

```bash
# Login no GitHub Container Registry
echo $GITHUB_TOKEN | docker login ghcr.io -u SEU-USUARIO --password-stdin

# Build e push
docker build -t ghcr.io/seu-usuario/hytale-server:latest .
docker push ghcr.io/seu-usuario/hytale-server:latest
```

## Configurar no Pterodactyl

1. Importe a egg `hytale_custom_image.json` no painel
2. Edite a egg e substitua `ghcr.io/SEU-USUARIO/hytale-server:latest` pela sua imagem
3. Crie um servidor usando esta egg

## Variaveis de Ambiente

| Variavel | Padrao | Descricao |
|----------|--------|-----------|
| `AUTO_UPDATE` | 0 | 1=baixa/atualiza, 0=apenas inicia |
| `INSTALL_SOURCEQUERY_PLUGIN` | 0 | 1=instala plugin SourceQuery |
| `HYTALE_MAX_VIEW_RADIUS` | (vazio) | Define MaxViewRadius no config.json |
| `HYTALE_PATCHLINE` | release | release ou pre-release |
| `USE_AOT_CACHE` | 1 | Usa cache AOT para inicio rapido |
| `HYTALE_ALLOW_OP` | 1 | Permite comandos de operador |
| `HYTALE_AUTH_MODE` | authenticated | authenticated ou offline |
| `DISABLE_SENTRY` | 0 | Desativa crash tracking |

## Estrutura

```
docker-image/
├── Dockerfile      # Base: java_25 + unzip + jq + curl
├── entrypoint.sh   # Script que gerencia AUTO_UPDATE
└── README.md       # Este arquivo
```

## Comparacao com imagem oficial

| Recurso | games:hytale | Esta imagem |
|---------|--------------|-------------|
| Baixa a cada inicio | Sempre | Opcional (AUTO_UPDATE) |
| Controle do usuario | Nenhum | Total |
| Tempo de inicio | Lento | Rapido (AUTO_UPDATE=0) |
| Plugin SourceQuery | Sim | Sim |
| MaxViewRadius | Sim | Sim |

## Fontes

- [Pterodactyl Yolks](https://github.com/pterodactyl/yolks)
- [Hytale Egg Oficial](https://eggs.pterodactyl.io/egg/games-hytale/)
- [Luxxy-Hosting/pterodactyl-hytale](https://github.com/Luxxy-Hosting/pterodactyl-hytale/)
