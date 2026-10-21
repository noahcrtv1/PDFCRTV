# PDFCRTV 1.1.0

## Entrega

Central Criar PDF acessível ao abrir o aplicativo ou com Cmd+N. Nove origens: arquivo, vários arquivos, espaços locais, captura, scanner, página web, área de transferência, página em branco e modelos.

Conversão local de imagens, TXT/RTF e HTML; documentos Office por LibreOffice opcional. Combinação na ordem escolhida, prévia, configurações de papel e salvamento. OCR pesquisável via Vision e camada de texto invisível, conservando conteúdo vetorial e anotações. Espaços locais com cópias de arquivos, links e notas.

## Verificação

- Testes de operações de página, criptografia e persistência da assinatura desenhada.
- Testes de paginação do texto, modelos, ordem da combinação e dimensões da página.
- OCR: camada invisível, texto recuperável após salvar, posição em páginas giradas e preservação de anotações.
- Integração real com Vision: imagem sem texto para PDF pesquisável; segundo OCR não duplica a camada.
- Integração DOCX para PDF com LibreOffice disponível no ambiente de teste. O aplicativo distribuído requer uma instalação separada de LibreOffice.
- Espaços: persistência, cópias independentes e rejeição de caminhos fora da pasta.
- Aplicativo de teste: páginas em branco, modelo, combinação ordenada e HTML longo com marcador final.

A inspeção visual completa da janela não foi confirmada: a captura de tela foi bloqueada pelo ambiente e a captura interna não reproduziu todas as camadas.

Scanner físico e captura interativa precisam de validação com dispositivo/permissões do usuário. Conversão de planilhas e apresentações usa o mesmo conversor Office, mas não foi validada com documentos reais nesta entrega.

## Limites

Espaços locais não oferecem IA, contas ou colaboração. A exportação web representa o conteúdo carregado e não garante páginas privadas ou carregamento infinito. O OCR ignora páginas que já contêm qualquer texto selecionável. OCR e conversão geram cópias e não preservam validade de assinaturas digitais. Não há edição do conteúdo original, tarja segura ou assinatura com certificado.

O pacote usa assinatura local e não tem notarização Apple.
