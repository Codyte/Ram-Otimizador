# 🧹 Sistema Inteligente de Limpeza de RAM

## O que é?

Um sistema automático que monitora o uso de RAM em tempo real e executa limpezas **estratégicas e inteligentes** usando a **API nativa do Windows** (`NtSetSystemInformation`) ou, como alternativa, o RAMMap (Microsoft Sysinternals) — configurável via `CleanEngine` (padrão `Auto`: nativo se disponível, senão RAMMap).

Ao contrário de limpar tudo constantemente (prejudicial para o SSD), este sistema:
- ✅ Limpa **apenas quando a RAM usada passa do limite** que você define (em % e/ou GB)
- ✅ Aplica **uma ação por perfil**: `All` (tudo), `SafeStrong` (sem stutter) ou `Standby`
- ✅ **Detecta apps pesados** (jogos, editores 3D, etc) e rebaixa `All`→`SafeStrong` p/ evitar engasgo
- ✅ **Executa escondido** em background (tarefa agendada)
- ✅ **Registra tudo** em logs para diagnóstico

---

## 📋 Como Usar

### **Iniciar**

Duplo clique em **`INICIAR.bat`** → abre o **Painel gráfico (UI)** com tudo: limpeza,
tarefa em 2º plano, perfis, configurações, logs e histórico (auto-eleva via UAC).

Prefere o menu clássico no console? **`INICIAR.bat cmd`**:

```
1 - Analisar sistema e recomendar perfil
2 - Escolher perfil pre-pronto (games, servidor 24/7, ...)
3 - Iniciar MONITOR continuo (primeiro plano)
4 - Limpeza manual rapida
5 - Dashboard ao vivo
6 - Configurar auto-execucao / agendamento / menu de contexto
7 - Testar sistema (RAMMap, permissoes, arquivos)
8 - Ver logs de hoje
9 - Editar configuracao (JSON)
U - Abrir painel grafico (UI no navegador, modo app)
T - Iniciar/Parar a tarefa em 2o plano
0 - Sair
```

> No monitor em primeiro plano (opção 3), pressione **Q** para parar e voltar ao menu.
> Perfis aplicados pelo menu passam a valer sozinhos no próximo ciclo do monitor
> (a config é recarregada automaticamente quando muda em disco).

---

### **Painel gráfico (opção U)** 🖥️

Interface visual completa que abre no navegador em **modo app** (janela própria, sem
barra de endereço — parece programa nativo). Tudo do script em um lugar só:

- **RAM ao vivo** — gauge de células estilo pente de memória (em uso / standby recuperável / livre), atualizado a cada 2s
- **Limpeza manual** — os 6 tipos (Safe, SafeStrong, Standby, Working Sets, Modified, All) com o resultado em GB
- **Perfis** — cards com todos os perfis + análise/recomendação do sistema com 1 clique
- **Configuração** — formulário de todos os campos do JSON (validado pelo mesmo parser do engine)
- **Tarefa 2º plano** — tudo do menu 6: iniciar/parar, criar monitor contínuo ou verificação periódica, status, menu de contexto (instalar/remover), remover auto-execução e "parar tudo"
- **Logs e resumo** — log de hoje ao vivo + estatísticas dos últimos 7 dias

Como funciona por dentro: `scripts/UI-Server.ps1` sobe um servidor HTTP **apenas em
localhost**, com **token de sessão** aleatório (nenhum outro programa consegue chamar a
API), serve `ui/index.html` (arquivo único, zero dependências/CDN — funciona offline) e
se encerra sozinho ~90s após a janela fechar. Requer qualquer navegador moderno
(Edge já vem no Windows 10/11). Também abre pelo botão direito: *Ram-Otimizador →
Abrir Painel (UI)*.

---

### **Auto-Execução em background (Recomendado)**

No menu, escolha **6 - Configurar auto-execucao**. Opções:
- **1** = Monitor contínuo no boot/logon (roda como SYSTEM, escondido) — recomendado p/ desktop/games
- **2** = Verificação periódica leve a cada N min — bom p/ servidor
- **3** = Ver status da tarefa
- **4** = Adicionar menu de contexto (botão direito na área de trabalho/pasta → Ram-Otimizador → Abrir Painel (UI) + limpeza 1-5)
- **5** = Remover menu de contexto
- **6** = Remover auto-execução (só o agendamento)
- **7** = Parar tudo e limpar resíduos (mata monitores + remove agendamentos)

> A tarefa roda como **SYSTEM**; o configurador já aceita o EULA do RAMMap p/ essa conta
> (senão a limpeza em 2º plano não funciona — veja *Troubleshooting*).
>
> O menu de contexto (opção 4) instala em HKCU (por usuário, sem admin p/ instalar).
> Cada ação auto-eleva via UAC ao clicar e roda oculta (sem janela azul).

---

## ⚙️ Ajustes de Configuração

Edite `RamCleanerConfig.json`:

Modelo simples: **UM limite dispara UMA ação**. Edite `RamCleanerConfig.json`:

```json
{
  "ThresholdClean": 80,         // % de RAM USADA que dispara a limpeza (ou "80%")
  "ThresholdCleanGB": null,     // idem em GB (ex: 10.5 ou "10.5gb"); combina com % por OU
  "CleanAction": "Safe",        // Safe (padrao, dia a dia) | All (max) | SafeStrong | Standby
  "CleanEngine": "Auto",        // Auto (nativo se disponivel) | Native | RAMMap
  "StepDelayMs": 400,           // delay entre os passos de uma limpeza multi-etapa (ms)
  "CheckIntervalSeconds": 30,   // Verifica a cada 30 segundos
  "CleanCooldownSeconds": 120,  // Tempo minimo entre 2 limpezas (anti-thrashing)
  "Enabled": true,              // Ativar/desativar
  "LogLevel": "INFO",           // DEBUG, INFO, WARNING
  "LogRetentionDays": 30,       // Apaga logs diarios com mais de N dias
  "EnableGameDetection": true,  // App pesado aberto => Safe/All viram SafeStrong (evita stutter)
  "RestartOnError": true        // Reiniciar se errar
}
```

### **Ações de limpeza (`CleanAction`)**

| Ação | Passos | Quando usar | Impacto |
|------|--------|-------------|---------|
| `Safe` (padrão) | Working Sets → Modified | **Dia a dia** — maior liberação real; também ideal antes de desligar | Apara Working Sets: páginas quentes voltam por page fault (custo momentâneo; páginas frias nem voltam) |
| `All` (TUDO) | Working Sets → System WS → Modified → Standby | **Antes de trocar de tarefa pesada** (fechar jogo → abrir editor), low-RAM | Libera o máximo, incluindo o cache Standby |
| `SafeStrong` | Modified → Standby | **Jogo, servidor, criação** | Forte **sem stutter** (não toca nos Working Sets) — usado automaticamente pela guarda anti-stutter |
| `Standby` | Standby | Bateria, uso leve | Mínimo, só cache |

> Os passos rodam **em ordem** (Working Sets → Modified → Standby) com um pequeno
> `StepDelayMs` entre eles. A ordem importa: aparar Working Sets manda páginas sujas
> pra Modified List; o flush da Modified as grava no pagefile e as move pra Standby;
> a purga da Standby libera tudo de uma vez. Purgar a Standby **não** gera páginas
> Modified (é cache limpo), então não há risco de loop.

> **Guarda anti-stutter:** com `EnableGameDetection: true`, se um app pesado/jogo
> estiver aberto e a ação for `Safe` ou `All` (as que aparam Working Sets), ela é
> rebaixada automaticamente para `SafeStrong` naquele ciclo — protege o jogo mesmo
> com o padrão de desktop.

### **Limite em % e/ou GB (RAM USADA)**

- `ThresholdClean` → percentual (número ou `"80%"`).
- `ThresholdCleanGB` → GB absoluto (`10.5`, `"10.5gb"`, `"10,5 GB"`, `"512mb"`). `null` = só %.

Quando **os dois** estão definidos, combinam por **OU**: dispara assim que
**qualquer um** for atingido (o mais agressivo vence).

```json
// Num PC de 32GB: limpar quando passar de 20% OU de 10.5GB usados
{ "ThresholdClean": "20%", "ThresholdCleanGB": "10.5gb" }
```

### **Recomendações por Cenário:**

#### PC com pouca RAM (≤8GB):
```json
{ "ThresholdClean": 72, "CleanAction": "Safe", "CheckIntervalSeconds": 20 }
```

#### PC com 16GB+ (uso normal):
```json
{ "ThresholdClean": 82, "CleanAction": "Safe", "CheckIntervalSeconds": 30 }
```

#### Gaming intenso (Rust, Warzone, etc):
```json
{ "ThresholdClean": 80, "CleanAction": "Safe", "CheckIntervalSeconds": 15, "EnableGameDetection": true }
```
> Com jogo aberto a guarda anti-stutter rebaixa `Safe`→`SafeStrong` sozinha; fora do jogo libera de verdade.

#### Servidor 24/7:
```json
{ "ThresholdClean": 90, "CleanAction": "Safe", "CheckIntervalSeconds": 60, "CleanCooldownSeconds": 300 }
```

---

## 🎮 Detecção Automática de Apps Pesados

O script detecta automaticamente e adapta a limpeza se encontrar:
- 🎮 Jogos (Rust, Warzone, Battlefield, GTA)
- 🎬 Editores (Premiere, Adobe)
- 3️⃣ Modeladores (Blender)
- 🌐 Navegadores (Chrome, Firefox)
- 💬 Discord, OBS, etc

Se detectar + RAM alta → usa limpeza mais agressiva

---

## 📝 Logs e Diagnóstico

Os logs são salvos em: `C:\Scripts\Ram Otimizador\logs\RAMMap_YYYY-MM-DD.log`

### Visualizar logs:
```powershell
Get-Content "C:\Scripts\Ram Otimizador\logs\RAMMap_$(Get-Date -Format 'yyyy-MM-dd').log" -Tail 30
```

### Interpretar logs:

```
[INFO] Perfil=agressivo-maximo | Limite=65% de RAM USADA -> acao=All
  └─ Monitor iniciado: limpa quando a RAM usada passar de 65%, executando 'All'

[DEBUG] RAM: 6.74GB / 31.7GB (21.27%) | Standby: 4320MB | limite=65% acao=All
  └─ Abaixo do limite, nenhuma ação necessária

[WARNING] [LIMPEZA] RAM 67% > limite 65% - executando acao 'All'...
[INFO] Limpeza OK! Liberados ~1.01GB (standby -1272MB) | RAM agora: 27.8%
  └─ Passou do limite, limpou e liberou ~1GB

[INFO] [GAMING] App pesado (game) aberto - usando SafeStrong (sem Working Sets) p/ evitar engasgo
  └─ Guarda anti-stutter: rebaixou 'All' para 'SafeStrong' por causa do jogo aberto
```

---

## 🚨 Troubleshooting

### "Não funciona nada - diz que precisa de ADMIN"
```powershell
# Clique direito no PowerShell → Executar como administrador
# Depois execute:
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser -Force
```

### "RAMMap.exe não encontrado"
```powershell
# O RAMMap acompanha o projeto. Verifique se existe em:
dir "C:\Scripts\Ram Otimizador\scripts\RAMMap.exe"

# Se faltar, baixe de https://learn.microsoft.com/en-us/sysinternals/downloads/rammap
# e copie RAMMap.exe para a pasta scripts do projeto.
```

### "Script some de repente"
Pode ter tido erro. Verifique logs:
```powershell
cat "C:\Scripts\Ram Otimizador\logs\RAMMap_$(Get-Date -Format 'yyyy-MM-dd').log" | Select-String "ERROR"
```

### "Limpeza em 2º plano não libera nada (mas em primeiro plano funciona)"
A tarefa roda como **SYSTEM**, que precisa aceitar o EULA do RAMMap. O configurador (menu 6)
já faz isso ao criar a tarefa, e o monitor também aceita sozinho na primeira limpeza. Se ainda
falhar, recrie a tarefa pelo menu **6 → 1**.

### "Quer limpar só com a RAM mais alta?"
Edite `RamCleanerConfig.json` e aumente `ThresholdClean` (ex: 85), ou defina `ThresholdCleanGB`.

---

## 🔧 Comandos Úteis

### Iniciar manual (escondido):
```powershell
Start-Process PowerShell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File 'C:\Scripts\Ram Otimizador\scripts\LimparRAM-Inteligente.ps1' -Monitor" -NoNewWindow
```

### Ver tarefa agendada:
```powershell
Get-ScheduledTask -TaskName "LimparRAM-Monitoramento" | Get-ScheduledTaskInfo
```

### Forçar execução agora:
```powershell
Start-ScheduledTask -TaskName "LimparRAM-Monitoramento"
```

### Ver se está rodando:
```powershell
Get-Process | Where-Object {$_.ProcessName -like "*RAMMap*"}
```

### Parar todas as instâncias:
```powershell
Stop-Process -Name "PowerShell" -Force -ErrorAction SilentlyContinue
# (cuidado - fecha todos PowerShells!)
```

---

## ✅ Checklist de Configuração

- [ ] RAMMap.exe presente em `C:\Scripts\Ram Otimizador\scripts\` (acompanha o projeto)
- [ ] Scripts, config e logs todos sob `C:\Scripts\Ram Otimizador\` (projeto autocontido)
- [ ] `config\RamCleanerConfig.json` editado conforme necessário
- [ ] Auto-execução configurada pelo menu **6** (monitor contínuo ou periódico)
- [ ] Logs sendo criados em `C:\Scripts\Ram Otimizador\logs\`
- [ ] Testado manual antes de usar em auto-execução

---

## 💡 Dicas Finais

1. **Não é para limpar a cada segundo** - O Windows gerencia RAM naturalmente. Este script evita deadlocks em jogos/apps pesados.

2. **SSD agradece** - Ao focar em Standby List, evita gravações constantes no disco.

3. **Monitore os logs** - Primeiro mês, veja `LogLevel: "DEBUG"` para entender seus padrões.

4. **Ajuste os thresholds** - Não existe "ideal universal". Teste, observe logs, ajuste.

5. **Combine com limpeza manual** - Às vezes, antes de abrir um jogo, use a limpeza manual (opção 4) para limpar tudo.

6. **Antes de desligar** - Use a limpeza manual **5 - Safe** (Working Sets → Modified): descarrega as páginas sujas pro disco e o shutdown fica mais rápido. Purgar a Standby antes de desligar não ajuda em nada (é cache limpo que o Windows descarta de graça).

---

## 📞 Suporte

Se tiver problemas:
1. Verifique os logs (vide seção Logs)
2. Rode o teste do sistema (opção 7 do menu)
3. Veja se RAMMap.exe existe
4. Tente com permissões de ADMIN

---

**Criado:** 2026-06-22 · **Atualizado:** 2026-07-02 (motor nativo, recarga automática de config, ordem Working Sets → Modified → Standby, tecla Q, rotação de logs, histórico CSV)  
**Ambiente:** Windows 10/11 + PowerShell 5.1+
