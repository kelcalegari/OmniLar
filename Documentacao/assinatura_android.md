# Assinatura do APK Android

O APK de release é assinado com uma chave própria (keystore de release), e não mais com a chave de debug que está no repositório (`android/app/debug.keystore`, pública).

## Como o build escolhe a chave

`android/app/build.gradle.kts` procura a chave de release, nesta ordem:

1. Variáveis de ambiente `OMNILAR_KEYSTORE_PATH`, `OMNILAR_KEYSTORE_PASSWORD`, `OMNILAR_KEY_ALIAS` e `OMNILAR_KEY_PASSWORD` (usadas pelo CI).
2. O arquivo `android/key.properties` (usado na máquina do dono). Ele está no `.gitignore`.

Se não achar a chave:

- Com `OMNILAR_REQUIRE_RELEASE_SIGNING=true`, o build para com erro. O CI e o `scripts/publicar_apk_supabase.ps1` ligam essa variável, para que um APK com a chave de debug nunca seja publicado.
- Sem ela (por exemplo, `flutter run --release` para testar), o release é assinado com a chave de debug e o Gradle avisa.

No CI, depois do build, o passo "Verify APK Signature" confere com o `apksigner` que o APK não saiu com a chave de debug e mostra o SHA-256 do certificado no log.

## O que só o dono pode fazer

### 1. Gerar a keystore (uma vez só)

No PowerShell, numa pasta **fora** do repositório (por exemplo `C:\Chaves\OmniLar`):

```powershell
keytool -genkeypair -v -keystore omnilar-release.jks -storetype PKCS12 -keyalg RSA -keysize 4096 -validity 10000 -alias omnilar
```

O `keytool` vem com o JDK (o do Android Studio fica em `C:\Program Files\Android\Android Studio\jbr\bin`). Ele pede uma senha e os dados do certificado (nome, organização, cidade; podem ser simples). No formato PKCS12 a senha da chave é a mesma da keystore.

### 2. Guardar o backup

Sem essa chave e a senha, **nenhuma atualização futura instala por cima** da versão assinada com ela, e não há como recuperá-la. Guarde:

- O arquivo `omnilar-release.jks` em pelo menos dois lugares fora do computador (por exemplo, um gerenciador de senhas com anexo e um pendrive ou nuvem pessoal).
- A senha e o alias (`omnilar`) no gerenciador de senhas.

### 3. Criar os secrets no GitHub

Gere o conteúdo em base64 e copie para a área de transferência:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\Chaves\OmniLar\omnilar-release.jks")) | Set-Clipboard
```

Em GitHub → repositório → Settings → Secrets and variables → Actions → New repository secret, crie:

| Secret | Valor |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | o texto copiado acima |
| `ANDROID_KEYSTORE_PASSWORD` | a senha da keystore |
| `ANDROID_KEY_ALIAS` | `omnilar` |
| `ANDROID_KEY_PASSWORD` | a mesma senha |

Enquanto esses secrets não existirem, o job "Build & Publish Android APK" falha em `main` e não publica nada (o resto do CI segue normal).

### 4. Configurar a máquina local (para o `subir_release.bat`)

Crie `android/key.properties` (não vai para o Git):

```properties
storeFile=C:/Chaves/OmniLar/omnilar-release.jks
storePassword=SUA_SENHA
keyAlias=omnilar
keyPassword=SUA_SENHA
```

Use barras normais (`/`) no caminho. Sem esse arquivo, as opções do `subir_release.bat` que compilam param com erro. A opção 1 (só subir o APK que já existe) não compila: confira que o APK em `build\` foi gerado depois da troca.

### 5. Login com Google e Firebase

O cliente OAuth Android do Google (ver `plano_autenticacao.md`, passo 3) é ligado ao SHA-1 da chave. Quando for configurá-lo, inclua o SHA-1 da chave nova:

```powershell
keytool -list -v -keystore C:\Chaves\OmniLar\omnilar-release.jks -alias omnilar
```

Se o app Android estiver cadastrado no Firebase com SHA-1, adicione também o da chave nova. As notificações (FCM) não dependem da assinatura.

## Impacto para quem já instalou

O Android só instala uma atualização assinada com a mesma chave da versão instalada. Quem tem o APK assinado com a chave de debug verá "App não instalado" (conflito de pacote) ao abrir o APK novo. Essa pessoa precisa **desinstalar o Omni Lar e instalar o APK novo**. Os dados da casa ficam no servidor e voltam ao entrar de novo; perde-se só o que é deste aparelho (sessão, cópia offline, lançamentos na fila ainda não enviados e a revisão de importação em andamento). Antes de desinstalar, abra o app com internet para a fila enviar o que estiver pendente.

Depois dessa troca única, as próximas versões instalam por cima normalmente, desde que a mesma chave seja usada.
