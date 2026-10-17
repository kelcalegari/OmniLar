> **Especificação original (06/10/2026).** Escrita antes do código. O que foi feito pode ser diferente: em caso de dúvida vale o código. O estado atual está em [plano_diretor_unificado.md](plano_diretor_unificado.md) e [pendencias_proxima_sessao.md](pendencias_proxima_sessao.md).

Documentação Funcional: Módulo de Captura Inteligente (Foto, QR Code e Boleto)

1. Visão Geral e Propósito
   Este módulo transforma uma foto, um QR Code ou um código de barras em dados estruturados para os demais módulos. O usuário aponta a câmera para um cupom, uma nota, um boleto ou um comprovante, e o app propõe o lançamento preenchido, para ser revisado e confirmado. Ele elimina a digitação manual em compras, contas e comprovantes, sem nunca gravar dinheiro sem a confirmação de uma pessoa.

2. Conceitos Essenciais
   2.1. Captura
   Qualquer entrada visual: foto, imagem da galeria, print, PDF de um arquivo, QR Code ou código de barras.
   2.2. Tipos de Documento
   Cupom/Nota Fiscal (NFC-e), Boleto/Conta, Comprovante de Pix/Transferência, Foto de Produto, Foto de Despensa, Convite/Receita (data e local) e Foto de Problema (tarefa).
   2.3. Leitura e Proposta
   O sistema lê o documento, extrai os campos e gera uma Proposta (rascunho). A proposta nunca vira lançamento sozinha.
   2.4. Nível de Confiança
   Cada campo extraído tem uma confiança (alta, média ou baixa). Campos de confiança baixa aparecem destacados para revisão.
   2.5. Ordem de Fonte
   QR Code/arquivo estruturado, depois leitura de foto. O app tenta sempre a fonte mais confiável primeiro.

3. Regras de Negócio Fundamentais
   RN01: Proposta Antes de Gravar
   Nenhum dado financeiro é gravado a partir de uma captura sem que o usuário confirme a tela de revisão.
   RN02: Detecção do Tipo
   O app identifica o tipo do documento automaticamente. O usuário pode corrigir o tipo, e a leitura é refeita.
   RN03: QR Code Primeiro
   Se a foto contém QR Code de NFC-e, o app usa os dados oficiais (itens, quantidade, preço, loja, data, total) em vez de fazer OCR dos textos impressos.
   RN04: Originais como Prova
   A imagem original fica anexada ao lançamento (alinhado à RN05 do módulo de Empréstimos) e não pode ser alterada. Ela pode ser removida apenas por quem a anexou, e a remoção fica registrada.
   RN05: Mascaramento de Dados Sensíveis
   Antes de enviar a imagem ao servidor de leitura, o app oculta dados desnecessários (CPF na nota, número completo de cartão e dados de conta quando possível). O servidor guarda a imagem original pelo prazo definido nas configurações e a descarta depois.
   RN06: Duplicidade
   Antes de propor um lançamento, o sistema compara valor, data, loja e itens com lançamentos existentes e com compras da Lista de Compras. Se encontrar semelhança, oferece Vincular ao existente em vez de criar outro.
   RN07: Conciliação com a Lista de Compras
   Itens lidos em uma nota são casados com os itens pendentes da lista (por nome e similaridade). Os casados são marcados como Comprados. Os não reconhecidos são oferecidos como Avulsos (viram histórico, sem entrar na lista). Os pendentes sem correspondência permanecem na lista.
   RN08: Normalização de Nomes
   Nomes abreviados da nota são normalizados ("LT INT 1L" vira "Leite integral 1L"), agrupados em categorias e ligados à despensa. O usuário corrige e a correção é aprendida.
   RN09: Itens Pessoais
   Na revisão de uma nota, o usuário pode marcar itens como Pessoais, e atribuir a quem. O restante vira Gasto da Casa. Os itens pessoais geram Empréstimo P2P (RN06 da Lista de Compras).
   RN10: Boletos e Contas
   O código de barras e a linha digitável são lidos e validados (dígito verificador). A leitura propõe valor, vencimento e beneficiário. Boleto com valor diferente do esperado para uma conta recorrente gera um alerta de variação.
   RN11: Comprovantes
   Um comprovante de Pix é associado a um aporte ou à baixa de uma parcela P2P, quando o valor e as partes coincidem. O vínculo é sugerido e confirmado pelo usuário.
   RN12: Falha de Leitura
   Se a leitura falhar, o app permite refazer a foto ou preencher manualmente, mantendo a imagem anexada.
   RN13: Privacidade e Consentimento
   O envio de imagens para leitura exige consentimento do usuário nas configurações, que pode ser revogado. Imagens de outros membros só são visíveis conforme a visibilidade do lançamento.

4. Descrição de Funcionalidades (Features)
* Câmera Inteligente: modo único que detecta QR Code, código de barras e documentos, com enquadramento automático.
* Tela de Revisão: lista de campos e itens extraídos, com destaque de baixa confiança, edição rápida e botão Confirmar.
* Leitura de Nota (NFC-e): itens, preços, loja e total, com divisão entre casa e pessoais.
* Leitura de Boleto/Conta: valor, vencimento, beneficiário e criação do compromisso na Timeline.
* Leitura de Comprovante: valor, data e partes, com sugestão de vínculo a aporte ou parcela.
* Foto de Produto/Código de Barras: adiciona item à Lista de Compras com nome normalizado.
* Foto de Despensa: sugere itens que parecem estar acabando (apenas sugestão).
* Foto para Tarefa: cria tarefa com a imagem anexada e título/categoria sugeridos.
* Foto para Evento: lê convite ou receita e cria um evento rascunho (data, local, título).
* Histórico de Capturas: lista de capturas com status (Pendente de revisão, Confirmada, Descartada).
* Fila Offline: capturas feitas sem internet ficam na fila e são processadas ao reconectar.

5. Experiência do Usuário (UX) e Navegação
   5.1. Pontos de Entrada
* Smart FAB: nova opção 📷 Escanear, junto das já existentes.
* Contextual: ícone de câmera dentro do fechamento da Lista de Compras, do formulário de Gasto da Casa, do Empréstimo, do Aporte, de Tarefa e de Evento.
  5.2. Fluxo Padrão
* Passo 1: tirar a foto ou escanear o QR Code.
* Passo 2: o app mostra "Lendo..." e depois a Proposta.
* Passo 3: revisar (itens, valores, categoria, quem paga, casa ou pessoal).
* Passo 4: confirmar, e o lançamento é criado com a imagem anexada.
  5.3. Tela de Revisão de Nota
* Cabeçalho: loja, data e total lido (com verificação de soma: "Itens somam R$ 312,40, total da nota R$ 312,40 ✔").
* Lista de itens com checkbox de casa/pessoal, e itens da lista de compras já pré-marcados.
* Campos de baixa confiança em destaque amarelo.
  5.4. Feedback Positivo (Nudges)
* "Nota lida! 18 itens encontrados, 12 marcados na sua lista. 🛒"
* "Este boleto parece o mesmo da conta de luz de outubro. Vincular?"
* "Pix de R$ 200 reconhecido. Parece o pagamento da parcela 3 do jogo."

6. Modelo de Dados Sugerido
```
captures(id, member_id, type, source[qr|photo|barcode|pdf|gallery], file_url, file_hash,
         status[pending|reviewed|confirmed|discarded|failed], created_at)
capture_extractions(id, capture_id, raw_json, confidence_json, model_version)
capture_items(id, capture_id, raw_name, normalized_name, quantity, unit_price_cents,
              total_cents, is_personal, owner_member_id, shopping_item_id)
capture_links(capture_id, target_type[house_expense|loan|payment|shopping_trip|task|event], target_id)
```
O arquivo original fica no storage com acesso controlado por RLS. `file_hash` ajuda na detecção de duplicidade.

7. Casos de Teste Derivados
* Captura nunca cria lançamento sem confirmação (RN01).
* Nota com QR Code usa os dados oficiais, sem OCR (RN03).
* Soma dos itens diferente do total sinaliza a divergência (tela de revisão).
* Nota com itens da lista marca os itens como Comprados (RN07).
* Mesma nota capturada duas vezes oferece vincular (RN06).
* Boleto com dígito verificador inválido é rejeitado (RN10).
* Comprovante de Pix sugere baixa da parcela correta (RN11).
* Sem internet, a captura entra na fila (Fila Offline).
* Imagem enviada tem CPF e dados de cartão mascarados (RN05).

8. Fora do Escopo (Versão Atual)
* Leitura de documentos de terceiros sem consentimento do usuário.
* Edição de imagem avançada.


9. Estratégia de Leitura: Código Primeiro, IA Depois
   O provedor de IA é a Gemini API (Google AI Studio), começando no plano gratuito (detalhes na seção 17 de [arquitetura_tecnica.md](arquitetura_tecnica.md)). Para economizar chamadas e aumentar a precisão, a leitura segue esta ordem:
* 1º QR Code da NFC-e: dados oficiais obtidos por código, sem IA.
* 2º Boleto: linha digitável e código de barras lidos e validados por código (dígito verificador). A IA só entra se a foto estiver ilegível.
* 3º Arquivo estruturado (OFX/CSV): lido por código.
* 4º Foto ou PDF sem estrutura: leitura pela IA (modelo multimodal), com saída em JSON validada por schema.
* Cache por `file_hash`: o mesmo arquivo nunca é enviado duas vezes à IA.
* Limite de uso por usuário e por Casa por dia. Ao atingir o limite ou em caso de erro de serviço, o app oferece o preenchimento manual, mantendo a imagem anexada (RN12).
* Plano gratuito: conteúdo enviado pode ser usado pelo Google para melhoria dos produtos. Durante o desenvolvimento, use apenas documentos fictícios ou seus. Antes de convidar outros usuários, migre para o plano pago e atualize o texto de consentimento (RN13).
