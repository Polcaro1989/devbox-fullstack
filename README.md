# devbox-fullstack

Devbox fullstack com dois modos de uso:

1. **GitHub Codespaces com desktop Linux no navegador** — usa a infraestrutura do GitHub enquanto o Codespace estiver ativo.
2. **Docker local/servidor 24/7 com SSH** — usa a máquina onde o Docker estiver rodando.

A toolchain inclui PHP, Composer, Python, pip, NVM/Node.js LTS e SDKs .NET 8, 9 e 10.

## GitHub Codespaces + desktop gráfico

No GitHub, abra este repositório e use:

```text
Code -> Codespaces -> Create codespace on main
```

O Codespace abre normalmente no VS Code Web. A mesma máquina também disponibiliza um desktop Linux leve com Fluxbox por noVNC.

Quando o ambiente terminar de criar, abra o painel **Ports** e clique em:

```text
Desktop (noVNC) - 6080
```

A porta 6080 é configurada como **private**. O noVNC não usa uma senha fixa própria; o acesso fica atrás da autenticação e das permissões do GitHub Codespaces. Não altere a visibilidade da porta para pública se não houver uma necessidade específica.

Aplicações gráficas iniciadas no terminal aparecem no desktop. Exemplos:

```bash
xterm &
nautilus &
mousepad &
```

Para verificar toda a toolchain dentro do Codespace:

```bash
verify-toolchain
```

O ambiente gráfico usa a feature oficial `ghcr.io/devcontainers/features/desktop-lite:1`, com Fluxbox, TigerVNC e noVNC. O container reserva 1 GB de shared memory para reduzir problemas com aplicações GUI.

O Codespaces está sujeito à cota, timeout de inatividade e demais regras do seu plano GitHub. Ele não é configurado por este projeto para permanecer ativo 24/7 indefinidamente.

## O que vem instalado

- PHP CLI + extensões comuns
- Composer
- Python 3 + pip + venv
- NVM + Node.js LTS + npm
- .NET SDK 8.x, 9.x e 10.x lado a lado
- Git e ferramentas de compilação
- OpenSSH Server no modo Docker/servidor
- Fluxbox + TigerVNC + noVNC no modo Codespaces

## Docker local ou servidor

Clone o repositório:

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

## Funcionamento 24/7 no modo Docker

O Compose usa:

```yaml
restart: unless-stopped
```

Isso significa que o container volta automaticamente após reinicialização do Docker ou do host, desde que você não o tenha parado manualmente antes.

## SSH no modo Docker

Por padrão:

```bash
ssh dev@IP_DO_HOST -p 2222
```

Usuário: `dev`

Senha: valor de `DEVBOX_SSH_PASSWORD` no seu `.env` local.

Root por SSH está desabilitado. Para trocar a porta do host, altere `SSH_PORT` no `.env`.

## Workspace

No modo Docker, `./workspace` do host é montado em `/workspace` dentro do container por padrão. Para usar outra pasta:

```env
WORKSPACE_PATH=/caminho/absoluto/dos/projetos
```

No Codespaces, o próprio repositório aberto pelo GitHub é o workspace do Dev Container.

## Comandos úteis do Docker

```bash
docker compose ps
docker compose logs -f
docker compose exec devbox bash
docker compose restart
docker compose stop
docker compose up -d
```

## Verificar ferramentas

No Docker:

```bash
docker compose exec devbox verify-toolchain
```

No Codespaces:

```bash
verify-toolchain
```

Para ver todos os SDKs .NET:

```bash
dotnet --list-sdks
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

Nenhuma senha, token, chave privada ou segredo fica salvo no repositório. A senha SSH existe apenas no `.env` do modo Docker. O Codespaces não usa `DEVBOX_SSH_PASSWORD`; o desktop noVNC é encaminhado como porta privada e depende do controle de acesso do GitHub.
