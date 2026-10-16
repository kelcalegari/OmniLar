// Service worker do push (FCM) do Omni Lar: recebe os avisos com o site
// fechado ou em segundo plano (navegador e iPhone com o site instalado).

// Toque no aviso: abre (ou traz para a frente) o app no item do deeplink. Vem
// antes do SDK do Firebase para valer também sem fcm_options.link.
self.addEventListener('notificationclick', (event) => {
  const data = event.notification.data || {};
  const payload = data.FCM_MSG || data;
  const deeplink = (payload.data && payload.data.deeplink) || '/notificacoes';
  const url = new URL(deeplink.startsWith('/') ? deeplink : '/notificacoes', self.location.origin).href;
  event.notification.close();
  event.stopImmediatePropagation();
  event.waitUntil((async () => {
    const windows = await clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const client of windows) {
      if (new URL(client.url).origin === self.location.origin && 'focus' in client) {
        await client.focus();
        if ('navigate' in client) await client.navigate(url);
        return;
      }
    }
    await clients.openWindow(url);
  })());
});

// A versão do SDK acompanha a do firebase_core_web (13.0.0).
importScripts('https://www.gstatic.com/firebasejs/13.0.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/13.0.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyAltqDtvDEqr5a78jMMpe8qNwJBzrhfWI8',
  authDomain: 'omnilar-ef002.firebaseapp.com',
  projectId: 'omnilar-ef002',
  storageBucket: 'omnilar-ef002.firebasestorage.app',
  messagingSenderId: '593321672478',
  appId: '1:593321672478:web:da7f4f7e9bb8c81ebc930f',
});

// Os avisos vêm com título e texto (a função notify sempre manda assim, como
// o iPhone exige), e o SDK os mostra sozinho com o site em segundo plano.
firebase.messaging();
