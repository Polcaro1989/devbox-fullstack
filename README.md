# devbox-fullstack

Devbox Docker 24/7 com PHP, Composer, Python, pip, NVM/Node.js e SDKs .NET 8, 9 e 10, além de SSH com usuário não-root `dev`.

## O que vem instalado

- PHP CLI + extensões comuns
- Composer
- Python 3 + pip + venv
- NVM + Node.js LTS + npm
- .NET SDK 8.x, 9.x e 10.x lado a lado
- Git e ferramentas de compilação
- OpenSSH Server

## Primeiro uso

```bash
git clone https://github.com/Polcaro1989/devbox-fullstack.git
cd devbox-fullstack
cp .env.example .env
```

Edite `.env` e defina uma senha forte em `DEVBOX_SSH_PASSWORD`. O arquivo `.env` é ignorado pelo Git e não deve ser commitado.

Depois execute:

```bash
chmod +x scripts/*.sh entrypoint.sh
./scripts/install-host.sh
```

O instalador habilita o Docker no boot em hosts Linux com systemd, valida o Compose e executa `docker compose up -d --build`.

## Funcionamento 24/7

O Compose usa:

```yaml
restart: unless-stopped
```

Isso significa que o container volta automaticamente após reinicialização do Docker ou do host, desde que você não o tenha parado manualmente antes.

## SSH

Por padrão:

```bash
ssh dev@IP_DO_HOST -p 2222
```

Usuário: `dev`
Senha: valor de `DEVBOX_SSH_PASSWORD` no seu `.env` local.

Root por SSH está desabilitado. Para trocar a porta do host, altere `SSH_PORT` no `.env`.

## Workspace

Por padrão, `./workspace` do host é montado em `/workspace` dentro do container. Para usar outra pasta:

```env
WORKSPACE_PATH=/caminho/absoluto/dos/projetos
```

## Comandos úteis

```bash
docker compose ps
docker compose logs -f
docker compose exec devbox bash
docker compose restart
docker compose stop
docker compose up -d
```

## Verificar ferramentas

```bash
docker compose exec devbox verify-toolchain
```

Para ver todos os SDKs .NET:

```bash
docker compose exec devbox dotnet --list-sdks
```

Cada projeto pode fixar seu SDK com `global.json`, por exemplo:

```json
{
  "sdk": {
    "version": "10.0.100",
    "rollForward": "latestFeature"
  }
}
```

Use uma versão realmente mostrada por `dotnet --list-sdks`.

## Segurança

Nenhuma senha, token, chave privada ou segredo fica salvo no repositório. A senha SSH é aplicada ao usuário `dev` somente na inicialização do container a partir do `.env` local.
