# CamBar

App de barra de menu para macOS que mostra ao vivo as câmeras IP (RTSP) da sua rede. Um clique no ícone abre um popover com a imagem da câmera; dali você troca de câmera, abre uma janela expandida ou uma visão geral em grade.

Feito para câmeras genéricas (como as que usam o app Yoosee), que costumam ter um app de celular ruim e nenhum cliente para Mac.

## Recursos

- **Barra de menu:** ícone de câmera de segurança com o número de câmeras online (`N ON`) e popover nativo com seta.
- **Painel rápido:** imagem ao vivo da câmera selecionada e abas para trocar de câmera sem reconectar.
- **Janela expandida:** vídeo grande com telemetria real (resolução, FPS e codec), seletor HD/SD, som, foto e tela cheia. A janela mantém a proporção 16:9 e o cabeçalho aparece ao passar o mouse.
- **Controle PTZ:** direcional, zoom e joystick, por ONVIF. Só aparece se a câmera for motorizada.
- **Visão geral:** grade com todas as câmeras, estados de conexão e botão de reconectar.
- **Configuração:** janela responsiva com pré-visualização ao vivo e teste de sinal.
- **Baixo consumo:** as câmeras ficam conectadas em modo espera quando o painel está fechado (ver [Desempenho](#desempenho)).
- **Segurança:** senhas guardadas no Keychain do macOS.

## Requisitos

- macOS 14 ou superior
- Swift 5.9 ou superior (Xcode ou Command Line Tools)
- [ffmpeg](https://ffmpeg.org), que decodifica o stream:

```bash
brew install ffmpeg
```

O CamBar procura o ffmpeg em `/opt/homebrew/bin` e `/usr/local/bin`.

## Compilar e executar

```bash
./build.sh
open build/CamBar.app
```

O script compila em release, monta o `CamBar.app` com o ícone e assina o app de forma ad-hoc. Não precisa do Xcode completo, só do Swift. Para ficar disponível sempre, arraste `build/CamBar.app` para a pasta Aplicativos.

Na primeira execução o macOS pode pedir permissão de acesso à rede local. Aceite, ou o app não enxerga as câmeras.

## Como usar

1. Clique no ícone da câmera na barra de menu.
2. Abra o ícone de ajustes e cadastre a câmera (veja abaixo).
3. Use **Testar Sinal** para confirmar que a câmera responde na porta, depois **Salvar**.
4. Volte ao painel: a imagem aparece em alguns segundos.

No painel, o botão de expandir abre a janela da câmera, o ícone de grade abre a visão geral e o botão **Sempre ativo** controla se as câmeras continuam conectadas com o painel fechado.

### Campos da câmera

| Campo | O que colocar |
|---|---|
| Nome | Como você quer chamar a câmera. |
| IP da câmera | Endereço local, por exemplo `192.168.1.10`. |
| Porta RTSP | Normalmente `554`. |
| Caminho RTSP | O trecho depois da porta, por exemplo `/onvif1`. |
| Porta ONVIF (PTZ) | Opcional. Se vazio, o app tenta `5000`, `80` e `8080`. |
| Usuário e senha | As credenciais do RTSP da câmera. |
| Transporte | Automático, UDP, TCP ou HTTP. Se não conectar, tente TCP. |

Senhas com caracteres especiais (`@`, `:`, `/`) funcionam sem ajuste: o app converte antes de montar a URL.

### Câmeras Yoosee e genéricas

Muitas câmeras só aceitam RTSP depois de ativá-lo no app do fabricante (procure por RTSP ou ONVIF nas configurações da câmera). Ao ativar, o app costuma mostrar o usuário e a senha do RTSP, que podem ser diferentes dos da sua conta. Caminhos comuns:

| Caminho | Uso |
|---|---|
| `/onvif1` | stream principal |
| `/onvif2` | stream secundário |
| `/live/ch0` e `/live/ch1` | modelos mais antigos |

O endereço completo fica assim: `rtsp://USUARIO:SENHA@IP:554/onvif1`. Se for testar no VLC, troque cada `@` da senha por `%40`.

## O que o app faz e não faz

O CamBar só recebe o que a câmera expõe por padrões abertos. Recursos que passam pelo protocolo fechado do fabricante não funcionam:

| Recurso | Funciona? |
|---|---|
| Vídeo ao vivo | Sim (RTSP) |
| Som da câmera | Sim, se o stream trouxer áudio |
| Foto | Sim, salva em `~/Pictures/CamBar` |
| Mover a câmera (PTZ) | Só se a câmera for motorizada e responder ao ONVIF |
| Falar pela câmera, luz, sirene | Não |
| Gravações e cartão SD | Não |
| Notificações de movimento | Não |

A câmera envia no máximo os FPS dela (por exemplo 15); o app não aumenta isso.

## Desempenho

O vídeo passa por um processo ffmpeg por câmera, que decodifica (com aceleração de hardware, VideoToolbox) e entrega quadros JPEG ao app. A qualidade muda conforme o uso:

| Situação | Resolução | Quadros |
|---|---|---|
| Painel aberto | 720 px | todos os que a câmera envia |
| Janela expandida (HD) | 1280 px | todos os que a câmera envia |
| Modo espera (painel fechado) | 480 px | só quadros-chave, cerca de 1 por segundo |

- Com **Sempre ativo** ligado (padrão), as câmeras ficam conectadas mesmo com o painel fechado, então trocar de aba e abrir o painel é instantâneo. No modo espera o consumo medido para duas câmeras foi de cerca de 2% de um núcleo e 240 MB de memória.
- Desligado, as câmeras desconectam 60 segundos depois que o painel fecha.
- O status online vem de uma conexão TCP simples à porta de cada câmera, a cada 20 segundos. Isso só indica que a câmera responde na rede, não que o vídeo funciona.

## Segurança e privacidade

- As senhas ficam no Keychain do macOS. As câmeras cadastradas (sem a senha) ficam nas preferências do app.
- O ffmpeg recebe a URL com usuário e senha como argumento, então outros processos do mesmo Mac podem vê-la enquanto o vídeo roda.
- O app só acessa a rede local; ele não envia nada para a internet.
- As câmeras ficam acessíveis a qualquer aparelho da sua rede. Use senhas fortes e, se o roteador tiver, isole a rede das câmeras.

## Solução de problemas

O app mostra o motivo no lugar do vídeo. O ffmpeg grava o detalhe, com as credenciais mascaradas, em `~/Library/Logs/CamBar.log`, e as respostas do PTZ ficam em `~/Library/Logs/CamBar-ptz.log`.

| Mensagem | Causa provável |
|---|---|
| A câmera não aceitou o RTSP (405) | A porta não fala RTSP. Ative RTSP/ONVIF no app da câmera. |
| Usuário ou senha incorretos (401/403) | Credenciais erradas. Use as que o app do fabricante mostra para o RTSP. |
| Caminho RTSP não encontrado (404) | Caminho errado. Teste `/onvif1`, `/onvif2` ou `/live/ch0`. |
| 400 Bad Request | Em câmeras genéricas, costuma ser usuário ou caminho incorreto. |
| Câmera inacessível | IP errado, câmera desligada ou fora da rede. |
| ffmpeg não encontrado | Instale com `brew install ffmpeg`. |

## Estrutura do projeto

O pacote tem três alvos:

- **`CamBarCore`**: lógica sem interface (modelos, comando do ffmpeg, leitura de MJPEG e do log, classificação de erros, ONVIF, Keychain, persistência). Não depende de AppKit nem SwiftUI.
- **`CamBar`**: o app (AppKit + SwiftUI), que usa o `CamBarCore`.
- **`CamBarChecks`**: verificações do `CamBarCore`. XCTest e Swift Testing exigem o Xcode completo, então elas rodam como executável:

```bash
swift run CamBarChecks
```

```
Sources/CamBarCore/
  Models/Camera.swift              Câmera e transporte RTSP
  Persistence/CameraRepository.swift  Onde a lista de câmeras é salva
  Security/CredentialStore.swift   Senhas no Keychain
  Network/Reachability.swift       Teste de conexão TCP
  Logging/FileLog.swift            Log com credenciais mascaradas e tamanho limitado
  Streaming/                       Perfis, comando do ffmpeg, MJPEG, telemetria e erros
  Audio/PCMConverter.swift         Conversão do áudio
  ONVIF/ONVIF.swift                Mensagens SOAP, WS-Security e cliente PTZ
Sources/CamBar/
  App/                             Entrada, ambiente de dependências, item da barra de menu, janelas
  Stores/                          Lista de câmeras e status online
  Streaming/                       Processo ffmpeg, stream de uma câmera e pool compartilhado
  Services/                        Áudio, PTZ e fotos
  Views/                           Tema, vídeo, popover, janela expandida, visão geral e configurações
Sources/CamBarChecks/main.swift    Verificações
```

### Arquitetura

- **Injeção de dependências:** `AppEnvironment` cria os serviços uma vez e os entrega às views (`environmentObject` e um `WindowRouting` no environment).
- **Pool com empréstimo (lease):** cada view que mostra uma câmera pega um `StreamLease` do `StreamPool`, que mantém um único ffmpeg por câmera e escolhe o perfil (espera, normal ou HD) conforme quem está olhando.
- **MVVM:** a janela expandida e as configurações têm view models próprios; as views só desenham.
- **Concorrência:** estado da interface no `@MainActor`; leitura e decodificação dos quadros fora da thread principal.
- **Protocolos:** repositório, credenciais e teste de conexão são protocolos, com versões em memória para as verificações.

Para regenerar o ícone:

```bash
mkdir -p /tmp/AppIcon.iconset
swiftc scripts/make-icon.swift -o /tmp/make-icon
/tmp/make-icon /tmp/AppIcon.iconset
iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns
```

## Créditos

- O ícone `cctv` é da biblioteca [Lucide](https://lucide.dev) (licença ISC).
- A decodificação de vídeo é feita pelo [FFmpeg](https://ffmpeg.org).

## Licença

[MIT](LICENSE)
