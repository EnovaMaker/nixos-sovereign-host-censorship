# Guia Rápido

## Instalar

```nix
{
  inputs.sovereign-host.url = "github:EnovaMaker/nixos-sovereign-host";

  outputs = { nixpkgs, sovereign-host, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        sovereign-host.nixosModules.sovereign-host
        ./configuration.nix
      ];
    };
  };
}
```

## Configurar — âmbito financiado (Matrix + bridges + Syncthing)

```nix
{
  services.sovereign = {
    enable = true;
    matrix = {
      enable = true;
      domain = "matrix.exemplo.org";
      enableTls = true;              # certificado ACME real via nginx
      adminEmail = "admin@exemplo.org";
      bridge.whatsapp.enable = true; # confirmado a funcionar de ponta a ponta num teste VM
      # bridge.telegram.enable = true;  # confirmado a passar numa corrida VM real
      # bridge.signal.enable = true;    # best-effort — ver o aviso abaixo
    };
    syncthing = {
      enable = true;
      guiAddress = "127.0.0.1:8384";
    };
  };
}
```

Ativar qualquer bridge (whatsapp/signal/telegram) traz o `libolm`, que o
nixpkgs marca como inseguro (deprecated a montante, CVE-2024-45191/2/3).
Vai ver um erro de build a menos que aceites isso explicitamente:

```nix
{ nixpkgs.config.permittedInsecurePackages = [ "olm-3.2.16" ]; }
```

Faz uma decisão informada antes de o fazeres — ver `docs/ROADMAP.md`
para o que foi de facto encontrado ao testar cada bridge.

## Segredos (OIDC/TURN/credenciais dos bridges)

Todos os segredos deste módulo são baseados em ficheiro — nada sensível
é alguma vez escrito no Nix store:

```nix
{
  services.sovereign.matrix = {
    sso.enable = true;
    sso.clientSecretFile = config.sops.secrets.matrix-oidc-secret.path;
    turn.enable = true;
    turn.sharedSecretFile = config.sops.secrets.matrix-turn-secret.path;
    bridge.telegram.environmentFile = config.sops.secrets.telegram-bridge-env.path;
  };
}
```

Rodar uma credencial é só: atualizar o ficheiro gerido por
sops-nix/agenix, depois reiniciar o serviço afetado
(`systemctl restart matrix-synapse` / `mautrix-<bridge>` / `coturn`). O
`preStart` de cada bridge relê o seu `environmentFile` em cada arranque,
não só no primeiro, por isso isto apanha sempre o novo valor. Aponta o
`restartUnits` do sops-nix para o serviço relevante para tornar isto
automático em vez de manual.

## Módulos bónus opcionais (fora do âmbito financiado)

`monitoring`, `backup`, e `sso` sobrepõem-se ao
[`ibizaman/selfhostblocks`](https://github.com/ibizaman/selfhostblocks)
(já financiado pela NLnet) — incluídos neste repo e testados, mas não
faturados como parte desta grant. Compõe com o Self Host Blocks se
quiseres uma stack de monitoring/backup/SSO mantida e financiada; usa
estes módulos se preferires ter tudo numa única flake.

## Limitações conhecidas

- Bridge Signal: excluído dos testes VM por completo — separadamente do
  problema do libolm acima, `mautrix-signal.service` produziu zero
  output no journal e nunca completou o arranque ao longo de 5+ minutos
  de testes reais neste ambiente. Best-effort.
- Bridge Telegram e o teste de integração Matrix+bridge+Syncthing: ambos
  confirmados a passar numa corrida VM real — ver
  `docs/FINAL_REPORT.md` para os dois bugs reais corrigidos pelo caminho.
