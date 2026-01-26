importScripts('https://www.gstatic.com/firebasejs/9.10.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.10.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyDoi4Mmcv0a_zcfHrQClwEKCm3FK5wzNWY",
  authDomain: "ezeyway-2f869.firebaseapp.com",
  projectId: "ezeyway-2f869", 
  storageBucket: "ezeyway-2f869.firebasestorage.app",
  messagingSenderId: "413898594267",
  appId: "1:413898594267:android:a1836521ce3ca5252d79fe"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function(payload) {
  console.log('Received background message', payload);
  
  const notificationTitle = payload.notification?.title || 'EzyWay Notification';
  const notificationOptions = {
    body: payload.notification?.body || 'You have a new notification',
    icon: '/alert-icon.svg'
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});