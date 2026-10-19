/// Termos de uso e política de privacidade (decisão 13 de plano_proximas_frentes.md).
///
/// Redigidos a partir de como o app funciona em 17/10/2026; precisam de revisão
/// jurídica antes da abertura ao público. Mudou o texto de forma relevante?
/// Troque [kLegalVersion]: quem já aceitou a versão anterior aceita de novo.
library;

/// Versão vigente dos dois textos (data da redação).
const kLegalVersion = '2026-10-17';

/// Data da versão, por extenso, para mostrar nas páginas.
const kLegalVersionLabel = '17 de outubro de 2026';

/// Quem responde pelo app e pelos dados. Sem CNPJ por enquanto: a pessoa física
/// do dono. Ao abrir o CNPJ, troque aqui (os dois textos usam estes valores).
const kLegalControllerName = 'Kelvynn Bordin Calegari';
const kLegalContactEmail = 'omnilarapp@gmail.com';

class LegalSection {
  final String title;
  final List<String> paragraphs;

  const LegalSection(this.title, this.paragraphs);
}

class LegalDocument {
  final String title;
  final String intro;
  final List<LegalSection> sections;

  const LegalDocument({required this.title, required this.intro, required this.sections});
}

const termsOfUse = LegalDocument(
  title: 'Termos de uso',
  intro: 'Estes termos explicam as regras para usar o Omni Lar. Ao criar a conta ou continuar usando o app, '
      'você concorda com eles e com a Política de privacidade.',
  sections: [
    LegalSection('1. O que é o Omni Lar', [
      'O Omni Lar é um aplicativo para organizar as finanças e a rotina de uma casa compartilhada: '
          'despesas, divisão entre os moradores, empréstimos entre eles, caixinhas, fechamento do ciclo, '
          'compras, tarefas e agenda.',
      'O app é oferecido por $kLegalControllerName, que pode ser contatado pelo e-mail $kLegalContactEmail.',
    ]),
    LegalSection('2. Quem pode usar', [
      'O app é para maiores de 18 anos.',
      'Cada conta é pessoal. Você é responsável pelas informações que cadastra e por manter sua senha em segredo. '
          'Contas novas podem passar por análise antes de serem liberadas.',
    ]),
    LegalSection('3. A casa e os moradores', [
      'Quem cria a casa é o dono dela. O dono e os administradores convidam moradores por código de convite '
          'e podem mudar as configurações da casa.',
      'Os moradores de uma casa veem os lançamentos dela: despesas, divisões, aportes, empréstimos entre moradores, '
          'caixinhas, fechamentos, compras, tarefas e agenda, conforme as regras de cada tela. '
          'Só convide pessoas com quem você aceita compartilhar essas informações.',
    ]),
    LegalSection('4. O que o app faz e o que não faz', [
      'O Omni Lar registra e calcula. Ele não movimenta dinheiro, não é banco nem instituição de pagamento '
          'e não faz Pix: as transferências são feitas por você, fora do app.',
      'Os cálculos (divisão, Fôlego, Super Pix, fechamento) são uma ferramenta de apoio, baseada no que os '
          'moradores lançaram. Confira os valores antes de pagar ou cobrar.',
      'Empréstimos e acordos registrados entre moradores são combinados entre eles. O app guarda o registro, '
          'mas não garante o pagamento nem interfere em desacordos.',
    ]),
    LegalSection('5. Leitura de documentos e anexos de comprovantes', [
      'Fotos e arquivos de notas, boletos, faturas e extratos podem ser lidos por inteligência artificial. '
          'A leitura pode ter erros: revise os valores antes de confirmar.',
      'Comprovantes e notas fiscais anexados às despesas ficam disponíveis para consulta, auditoria e download '
          'pelos moradores da casa durante o ciclo financeiro ativo e por até 30 dias após o seu fechamento e quitação. '
          'Decorrido esse período de conferência, os arquivos físicos são excluídos automaticamente, permanecendo '
          'inalterados os lançamentos contábeis, valores e categorias no histórico da casa.',
      'O funcionamento e os detalhes sobre privacidade estão na Política de privacidade.',
    ]),
    LegalSection('6. Planos', [
      'O app tem os planos Free e Premium, com limites diferentes (por exemplo, de moradores, casas, projetos '
          'e leituras por IA). Os limites e as condições podem mudar; mudanças relevantes são avisadas antes.',
    ]),
    LegalSection('7. Uso adequado', [
      'Não é permitido usar o app para fins ilegais, tentar acessar dados de outras casas ou contas, '
          'interferir no funcionamento do serviço ou cadastrar informações de terceiros sem autorização.',
    ]),
    LegalSection('8. Disponibilidade', [
      'O app está em desenvolvimento e pode ter interrupções, erros ou mudanças. Fazemos o possível para '
          'manter o serviço funcionando e os dados guardados, mas não há garantia de funcionamento contínuo.',
    ]),
    LegalSection('9. Responsabilidade', [
      'Na medida permitida pela lei, o Omni Lar não responde por decisões financeiras tomadas com base nos '
          'cálculos do app, por valores lançados errado pelos moradores nem por acordos entre eles. '
          'Nada nestes termos afasta os seus direitos como consumidor.',
    ]),
    LegalSection('10. Suspensão e exclusão', [
      'Contas que descumprirem estes termos podem ser suspensas. Você pode excluir a sua conta a qualquer momento '
          'em Ajustes › Conta e segurança; o que acontece com os seus dados está na Política de privacidade.',
    ]),
    LegalSection('11. Mudanças nestes termos', [
      'Quando estes termos mudarem de forma relevante, o app pede o seu aceite de novo antes de continuar.',
    ]),
    LegalSection('12. Lei aplicável e contato', [
      'Estes termos seguem as leis do Brasil. Fica eleito o foro do seu domicílio.',
      'Dúvidas: $kLegalContactEmail.',
    ]),
  ],
);

const privacyPolicy = LegalDocument(
  title: 'Política de privacidade',
  intro: 'Esta política explica quais dados o Omni Lar usa, para quê, com quem são compartilhados e como '
      'você exerce os seus direitos, conforme a Lei Geral de Proteção de Dados (Lei 13.709/2018).',
  sections: [
    LegalSection('1. Quem cuida dos seus dados', [
      'O responsável pelos dados (controlador) é $kLegalControllerName. '
          'Para qualquer assunto sobre privacidade, escreva para $kLegalContactEmail.',
    ]),
    LegalSection('2. Quais dados usamos', [
      'Cadastro: nome, e-mail e senha (a senha fica só no serviço de autenticação, cifrada, e nunca é vista por nós). '
          'Opcionais: telefone, foto e chave Pix.',
      'Dados da casa: moradores, convites, despesas e seus itens, divisões, aportes, empréstimos entre moradores, '
          'caixinhas, fechamentos, linhas de faturas e extratos importados, compras, tarefas, agenda e projetos.',
      'Documentos e comprovantes: fotos e arquivos de notas, boletos, faturas e extratos. '
          'Documentos enviados apenas para leitura por IA são processados e descartados em seguida. '
          'Comprovantes anexados a despesas são mantidos temporariamente durante o ciclo financeiro em aberto '
          'e por até 30 dias após o seu fechamento e quitação para conferência entre os moradores, sendo excluídos definitivamente do armazenamento após esse prazo.',
      'Uso e segurança: contagem de leituras por IA, registro de alterações financeiras da casa (auditoria), '
          'aparelhos cadastrados para notificações e situação da conta (análise, plano).',
    ]),
    LegalSection('3. Para que usamos e com que base', [
      'Para prestar o serviço que você pediu: guardar e calcular as contas da casa, enviar avisos, '
          'permitir convites e o fechamento do ciclo (execução de contrato).',
      'Para ler documentos com inteligência artificial, com o seu consentimento, pedido antes da primeira leitura.',
      'Para segurança, prevenção de abuso e auditoria das alterações financeiras (legítimo interesse).',
      'Para cumprir obrigações legais, quando houver.',
      'Não vendemos dados e não os usamos para publicidade.',
    ]),
    LegalSection('4. Com quem compartilhamos', [
      'Moradores da sua casa: veem os dados da casa, como explicado nos Termos de uso.',
      'Supabase: banco de dados e autenticação, com os dados guardados no Brasil (São Paulo).',
      'Google: a leitura por IA (Gemini), as notificações no celular (Firebase Cloud Messaging) e a hospedagem do site '
          '(Firebase Hosting). Esses serviços podem processar dados fora do Brasil.',
      'Secretarias da Fazenda estaduais: ao ler o QR Code de uma nota fiscal, o endereço da consulta pública da nota '
          'é acessado pelo nosso servidor.',
      'A administração do Omni Lar vê dados da conta e números de uso, nunca os valores das casas.',
    ]),
    LegalSection('5. Leitura por inteligência artificial', [
      'Fotos e arquivos enviados para leitura vão para a API Gemini, do Google. Em textos enviados, CPF e número de '
          'cartão são mascarados antes; fotos e PDFs vão inteiros.',
      'Enquanto o app estiver em fase de testes, a leitura usa o plano gratuito da API, em que o Google pode usar o '
          'conteúdo enviado para melhorar os serviços dele. Antes da abertura ao público, a leitura passará a usar o '
          'plano pago, em que isso não acontece, e esta política será atualizada.',
      'Se você cadastrar a sua própria chave da API do Google, a leitura usa a sua conta Google, com as condições dela.',
      'Você pode retirar o consentimento em Ajustes; sem ele, o app não envia documentos para a IA.',
    ]),
    LegalSection('6. Dados guardados no seu aparelho', [
      'Para abrir sem internet, o app guarda no aparelho, cifrada, uma cópia do que você viu com conexão. '
          'Também guarda as alterações feitas sem internet até enviá-las e o rascunho de uma importação em andamento. '
          'Sair da conta apaga a cópia e a fila. O site usa o armazenamento do navegador para a sessão e essa cópia; '
          'não usa cookies de publicidade nem de rastreamento.',
    ]),
    LegalSection('7. Por quanto tempo guardamos', [
      'Enquanto a sua conta existir. Ao excluir a conta, os seus dados pessoais são apagados; o que você lançou numa '
          'casa com outros moradores fica no histórico deles, sem o seu nome (aparece como "Ex-morador"), porque faz '
          'parte das contas da casa. Se você era o único morador, a casa é apagada junto.',
      'Comprovantes e notas fiscais anexadas seguem a política de retenção por ciclo financeiro: ficam disponíveis '
          'durante o ciclo ativo e são apagados automaticamente 30 dias após o fechamento e quitação do ciclo.',
      'Cópias de segurança do banco são mantidas pelo provedor por um período limitado e depois descartadas.',
    ]),
    LegalSection('8. Segurança', [
      'Os dados trafegam cifrados (TLS) e ficam cifrados no banco. Cada casa só é vista pelos seus moradores, '
          'por regras de acesso no próprio banco, e as alterações financeiras ficam registradas.',
    ]),
    LegalSection('9. Seus direitos', [
      'Você pode, a qualquer momento: confirmar quais dados temos e baixá-los (Ajustes › Conta e segurança › '
          'Baixar meus dados); corrigir os seus dados (Ajustes); excluir a conta (Ajustes › Conta e segurança); '
          'retirar o consentimento da IA; e pedir informações sobre o compartilhamento.',
      'Para qualquer outro pedido, escreva para $kLegalContactEmail. Você também pode reclamar à Autoridade Nacional '
          'de Proteção de Dados (ANPD).',
    ]),
    LegalSection('10. Menores de idade', [
      'O app não é para menores de 18 anos.',
    ]),
    LegalSection('11. Mudanças nesta política', [
      'Quando esta política mudar de forma relevante, o app pede o seu aceite de novo antes de continuar.',
    ]),
  ],
);
