# 🎮 Ram-Otimizador — Limpador e otimizador de RAM para Windows

[![CI](https://github.com/Codyte/Ram-Otimizador/actions/workflows/ci.yml/badge.svg)](https://github.com/Codyte/Ram-Otimizador/actions/workflows/ci.yml)
🇺🇸 [English version](README.en.md)

**Monitor automático de memória: quando o uso de RAM passa do limite configurado, limpa sozinho — via API nativa do Windows, com cada limpeza registrada em CSV.**

Limpador de RAM em PowerShell para Windows 10/11: apara o working set dos apps e descarrega páginas sujas usando `NtSetSystemInformation` (sem programas externos), com detecção de jogo anti-stutter, perfis prontos, painel gráfico e histórico de resultados por limpeza.

![Painel do Ram-Otimizador](docs/ui-screenshot.png)

---

## 📊 Testes até agora

Todas as limpezas ficam registradas em `logs/cleanup-history.csv`. Resultados de **209 limpezas** na máquina de desenvolvimento (32GB de RAM):

| Ação | O que faz | Mediana liberada | Máximo | N |
|------|-----------|------------------|--------|---|
| **Safe** (padrão) | Working Sets → Modified | **3,3 GB** | 7,7 GB | 171 |
| All | Tudo, incluindo cache standby | 0,8 GB | 4,2 GB | 8 |
| Working Sets | Só apara memória dos apps | 0,7 GB | 2,1 GB | 10 |
| SafeStrong | Modified + Standby (não toca nos apps) | 0,4 GB | 0,4 GB | 2 |
| Modified | Só descarrega páginas sujas | 0,3 GB | 1,3 GB | 15 |
| Standby | Só o cache standby | ~0 | ~0 | 3 |

**Leia com atenção:** `Safe` é o padrão porque é o que libera de verdade. `SafeStrong` libera pouco — o valor dele é **não tocar nos apps abertos** (zero engasgo), por isso o monitor troca para ele automaticamente quando detecta jogo rodando. `Standby` sozinho é quase inútil: o Windows já solta esse cache sob demanda.

Seus números vão variar com hardware e carga. Rode e confira no seu próprio CSV.

---

## 📌 O que esperar ao usar

- **Alivia pressão de memória.** Quando a RAM opera perto do limite (80%+), o sistema começa a paginar e engasgar; liberar memória nesse cenário reduz paginação e os travamentos que ela causa. Com RAM folgada, o efeito é pequeno — o monitor simplesmente não dispara.
- **Nada é fechado.** A limpeza atua em cache e working sets; seus programas continuam abertos e funcionando.
- **Consequência no disco:** descarregar Modified escreve as páginas sujas no disco (elas iriam para lá de qualquer forma na próxima paginação); o cooldown limita a frequência disso.
- **Onde mais ajuda:** máquinas com 8-16GB sob carga (jogo + navegador + Discord), servidores que degradam com o tempo, e edição pesada de vídeo/3D.

---

## ✅ O que ele FAZ (de verdade, tudo no código)

- **Monitor automático** (tarefa agendada, roda como SYSTEM, invisível): limpa quando a RAM passa do limite, com histerese em banda (não fica limpando em loop) e cooldown configurável.
- **Anti-stutter real:** com jogo ou app de criação aberto, ações `All`/`Safe` viram `SafeStrong` sozinhas (não tocam no working set do jogo). Lista detectada: Rust, Warzone, Battlefield, GTA V, Valorant, CS:GO/CS2, Fortnite, League, Steam, Epic + Blender, Premiere, DaVinci, Photoshop, After Effects, Unreal, Unity, 3ds Max, Maya.
- **Motor nativo:** `NtSetSystemInformation` direto — sem depender de programa externo. RAMMap (Sysinternals) é só fallback opcional.
- **Painel gráfico local** (screenshot acima): limpeza manual, perfis, config, logs, gráfico de RAM das últimas horas com marcas de limpeza. Servidor HTTP local com token de sessão.
- **7 perfis prontos** + recomendação automática que analisa seu hardware.
- **Tudo logado:** log diário + CSV de histórico por limpeza (antes/depois/GB).

---

## 🚀 Quick Start (2 minutos)

### 1. Instalar (1 linha no PowerShell)
```powershell
irm https://raw.githubusercontent.com/Codyte/Ram-Otimizador/master/install.ps1 | iex
```
Baixa a última versão, instala em `%LOCALAPPDATA%\Ram-Otimizador` (atualizações preservam sua config) e abre o painel.

<details><summary>Prefere git clone?</summary>

```powershell
git clone https://github.com/Codyte/Ram-Otimizador.git
cd Ram-Otimizador
```
</details>

### 2. Executar
```
Duplo clique em INICIAR.bat → abre o Painel gráfico (auto-eleva via UAC)
Prefere o menu clássico no console? INICIAR.bat cmd
```

### 3. Escolher perfil e ativar o monitor
```
No painel: seção "Perfis" → clique num card (ou "Analisar sistema e recomendar")
Depois: "Criar monitor contínuo" → pronto, seu PC cuida da RAM sozinho.
```

---

## ⚙️ Perfis (valores reais do código)

| Perfil | Limite | Ação | Checagem | Cooldown | Para quem |
|--------|--------|------|----------|----------|-----------|
| **equilibrado** | 82% | Safe | 30s | 120s | Desktop no dia a dia |
| **games** | 80% | Safe* | 15s | 60s | Jogos (*vira SafeStrong com jogo aberto) |
| **servidor-24-7** | 90% | Safe | 60s | 300s | Servidor: raro e leve |
| **workstation-criacao** | 88% | SafeStrong | 30s | 180s | Edição de vídeo/3D (não trima os editores) |
| **low-ram** | 72% | Safe | 20s | 90s | Máquinas com ≤8GB |
| **economia-bateria** | 90% | Safe | 120s | 600s | Notebook na bateria |
| **agressivo-maximo** | 65% | All | 15s | 45s | Máxima RAM livre a qualquer custo |

Todo perfil também configura histerese, standby mínima e nível de log. Editou qualquer valor na mão? O perfil vira `personalizado`.

---

## 🔧 Ações de limpeza explicadas

- **Safe** (padrão) — Working Sets → Modified. Maior liberação real (mediana 3,3GB nos nossos logs) e **preserva o cache de disco** (standby).
- **All** — tudo: Working Sets → System WS → Modified → Standby. Use antes de abrir uma tarefa pesada. Purgar standby joga fora cache que o Windows reaproveitaria.
- **SafeStrong** — Modified + Standby, **sem tocar nos apps abertos**. Libera pouco, mas zero engasgo — é o modo anti-stutter que o monitor usa com jogo aberto.
- **Standby / Working Sets / System WS / Modified** — cada passo isolado, para testar o efeito na sua máquina.

---

## 💻 Menu clássico (console)

```
1 - Analisar sistema e recomendar perfil
2 - Escolher perfil pré-pronto
3 - Iniciar MONITOR contínuo (primeiro plano)
4 - Limpeza manual rápida
5 - Dashboard ao vivo
6 - Configurar auto-execução / agendamento / menu de contexto
7 - Testar sistema (permissões, arquivos)
8 - Ver logs de hoje
9 - Editar configuração (JSON)
```

---

## ❓ FAQ

**P: Vai matar meus programas abertos?**
R: Não. Limpa cache e apara working sets; nada é fechado.

**P: Vou ganhar FPS?**
R: Se sua RAM vive perto do limite enquanto joga, reduzir a pressão evita paginação e os engasgos que ela causa. Com RAM folgada o efeito é pequeno.

**P: Qual limpeza libera mais?**
R: `Safe` (padrão): apara working sets e descarrega modified — mediana de 3,3GB nos nossos logs. Purgar só o standby libera quase nada, porque o Windows já solta esse cache sob demanda (por isso não é o padrão).

**P: Precisa de admin?**
R: Sim — a API de limpeza exige. O painel auto-eleva via UAC; a tarefa agendada roda como SYSTEM sem te incomodar.

**P: Funciona com 8GB?**
R: Sim, é onde mais ajuda (perfil `low-ram`). Com pouca RAM a pressão é constante.

**P: E o SSD?**
R: Transparência: descarregar Modified *escreve* as páginas sujas no disco (elas iriam para lá de qualquer forma no próximo paging). O cooldown existe justamente para não fazer isso toda hora.

---

## 🐛 Troubleshooting

### "Não abre / não faz nada"
1. PowerShell como Admin: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force`
2. Rode `INICIAR.bat` de novo (aceite o UAC)

### "Limpeza em background não libera RAM"
A tarefa roda como SYSTEM. Painel → "Criar monitor contínuo" (recria a tarefa).

### "Monitor não limpa nunca"
Confira o limite (`ThresholdClean`) vs seu uso real, e o log de hoje (painel ou `Menu > 8`).

### Quer mais agressividade?
Painel → Configuração → Limite 70-75%, ou aplique o perfil `agressivo-maximo`.

---

## 🤖 Para agentes de IA e automação

Instalação sem interação (PowerShell, Windows 10/11):

```powershell
irm https://raw.githubusercontent.com/Codyte/Ram-Otimizador/master/install.ps1 | iex
```

- Instala em `%LOCALAPPDATA%\Ram-Otimizador`; atualizações preservam `config/` e `logs/`.
- Limpeza exige elevação (UAC): `INICIAR.bat` e o painel auto-elevam; a tarefa agendada roda como SYSTEM.
- Limpeza manual por linha de comando (admin): `scripts\LimparRAM-Inteligente.ps1 -Clean Safe` (ações: `Safe|All|SafeStrong|Standby|WorkingSets|SystemWorkingSets|ModifiedPageList`).
- Config em `config/RamCleanerConfig.json` (schema e limites em `scripts/RamCommon.ps1`); resultados por limpeza em `logs/cleanup-history.csv`.
- Resumo legível por máquina: [`llms.txt`](llms.txt).

---

## 🛠️ Tecnologia

PowerShell (82%) + painel em HTML/CSS/JS vanilla (16%). Sem dependências externas, sem telemetria, sem instalador esquisito — é script, você pode ler tudo.

Qualidade: testes de regressão da config + PSScriptAnalyzer rodam no CI a cada push.

---

## 🤝 Contribuindo

- [ ] **UI em inglês** — o painel e menus são pt-BR hoje
- [ ] **Mais jogos na detecção** — a lista está em `scripts/RamCommon.ps1` (`$Global:RamGameApps`)
- [ ] **Benchmark de FPS de verdade** — se você tem como medir frametime antes/depois com rigor, é a contribuição mais valiosa que existe aqui
- [ ] **Notificação** — webhook/Discord quando limpar

**Como participar:** [CONTRIBUTING.md](CONTRIBUTING.md)

---

## 📝 Licença

MIT — use livremente.

---

**Feito com ❤️ no Brasil. Os números deste README vêm do código e do `logs/cleanup-history.csv`.**
**v1.0** — 2026-07-13
