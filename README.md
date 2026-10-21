# CamBar

App de barra de menu para macOS que mostra ao vivo as câmeras IP (RTSP) da sua rede, com acesso rápido pelo ícone e janela expandida.

## Recursos

- Ícone na barra de menu com o número de câmeras online (`N ON`) e popover nativo
- Painel rápido com a imagem ao vivo e abas para trocar de câmera
- Janela expandida com telemetria real (resolução, FPS, codec), HD/SD, som e foto
- Controle PTZ por ONVIF, quando a câmera é motorizada
- Visão geral em grade com todas as câmeras
- Streams ficam conectados com modo espera (baixo consumo) quando o painel está fechado
- Janela de configuração responsiva, com pré-visualização e teste de sinal
- Senhas guardadas no Keychain do macOS
- Transporte RTSP configurável (automático, UDP, TCP ou HTTP)

## Requisitos

- macOS 14 ou superior
- Swift 5.9+ (Xcode ou Command Line Tools)
- [ffmpeg](https://ffmpeg.org) para decodificar o stream:

```bash
brew install ffmpeg
```

## Como compilar e executar

```bash
./build.sh
open build/CamBar.app
```

O app roda só na barra de menu, sem ícone no Dock.

## Como usar

1. Clique no ícone da câmera na barra de menu e abra **Gerenciar câmeras**.
2. Cadastre nome, IP, porta (554), caminho RTSP, usuário e senha.
3. Use **Testar Sinal** para checar se a câmera responde e salve.

Muitas câmeras genéricas só aceitam RTSP depois de ativá-lo (RTSP/ONVIF) no app do fabricante.

## Observações

- O ffmpeg recebe a URL com usuário e senha como argumento, então outros processos do mesmo Mac podem vê-la enquanto o vídeo roda.
- O log do ffmpeg, com as credenciais mascaradas, fica em `~/Library/Logs/CamBar.log`; as respostas do PTZ ficam em `~/Library/Logs/CamBar-ptz.log`.
- Fotos salvas pelo app vão para `~/Pictures/CamBar`.
- O ícone `cctv` é da biblioteca [Lucide](https://lucide.dev) (licença ISC).

## Licença

[MIT](LICENSE)
