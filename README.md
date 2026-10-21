# PDFCRTV

App nativo macOS (SwiftUI + PDFKit) para criar, ler e anotar PDFs, como alternativa ao Acrobat.
Faz parte da família CRTV (DownloaderCRTV, SplitterCRTV, CleanerCRTV, CobrançaCRTV).

## Instalar no seu Mac

Precisa de um Mac com Apple Silicon (M1 ou mais novo) e macOS 26 ou mais novo.

1. Instale o **Xcode** pela App Store (grátis), abra uma vez e aceite a licença.
   Ele traz o compilador Swift e a ferramenta que gera o ícone.
2. Abra o app **Terminal** e rode:

```bash
git clone https://github.com/noahcrtv1/PDFCRTV.git
cd PDFCRTV
scripts/build-app.sh --install  # compila e instala em /Applications
```

O app aparece em **Aplicativos** como PDFCRTV. Para abrir PDFs sempre nele: Obter Informações em um PDF ▸
Abrir com: PDFCRTV ▸ Alterar Tudo.

3. Na primeira vez que abrir, o macOS pode bloquear (o app não é assinado pela Apple).
   Vá em **Ajustes do Sistema ▸ Privacidade e Segurança** e clique em **Abrir Mesmo Assim**.

Para converter DOC/DOCX, XLS/XLSX e PPT/PPTX em PDF, instale também o
[LibreOffice](https://www.libreoffice.org/download/download-libreoffice/) (grátis).

Para atualizar depois: `cd PDFCRTV && git pull` e rode o último comando de novo.

## O que faz
- **Criar PDF** (⌘N): imagens, PDF, TXT, RTF, HTML, Office (via LibreOffice), captura de tela, scanner,
  página da web, área de transferência, página em branco e modelos. Combina vários arquivos em um.
- **OCR pesquisável**: reconhecimento local em português, inglês e espanhol.
- **Leitura e anotação**: miniaturas, sumário, busca, marca-texto, notas, desenho, assinatura desenhada,
  formulários, reordenar/girar/extrair/dividir páginas, exportar comprimido, com senha, PNG e texto.
- **Espaços locais**: pastas que reúnem cópias de arquivos, links e notas.

Limites: a edição altera anotações, não reescreve o texto original do PDF; sem assinatura com certificado.
Detalhes em `scripts/LEIA-ME.txt` e `docs/versao-1.1.0.md`.

## Build
```bash
swift test                    # testes do núcleo (PDFCoreTests)
scripts/build-app.sh          # build/PDFCRTV.app (--install copia para /Applications)
scripts/make-dmg.sh           # build/PDFCRTV-<versão>.dmg para compartilhar
```
