/** @format */

importScripts("https://www.gstatic.com/firebasejs/8.2.1/firebase-app.js");
importScripts("https://www.gstatic.com/firebasejs/8.2.1/firebase-messaging.js");

firebase.initializeApp({
    apiKey: "AIzaSyCABo-jItycXrHHDk9HsUtveLjzLDTSUcc",
    authDomain: "sway-7947e.firebaseapp.com",
    projectId: "sway-7947e",
    storageBucket: "sway-7947e.appspot.com",
    messagingSenderId: "392965817311",
    appId: "1:392965817311:web:c27d583551c85fae2dba6a",
});

self.onnotificationclick = function (event) {
    // event.preventDefault(); // prevent the browser from focusing the Notification's tab
    event.notification.close();

    event.waitUntil(
        clients
            .matchAll({ includeUncontrolled: true, type: "window" })
            .then(function (clientList) {
                for (let i = 0; i < clientList.length; i++) {
                    let client = clientList[i];

                    if (client.url.includes("localhost")) {
                        // Scope url is the part of main url
                        client.navigate(
                            "http://localhost:3000/bill-of-the-week",
                        );
                        return client.focus();
                    }
                    if (client.url.includes("127.0.0.1")) {
                        // Scope url is the part of main url
                        client.navigate(
                            "http://127.0.0.1:3000/bill-of-the-week",
                        );
                        return client.focus();
                    }
                    if (client.url.includes("sway")) {
                        // Scope url is the part of main url
                        client.navigate(
                            "https://app.sway.vote/bill-of-the-week",
                        );
                        return client.focus();
                    }
                }
                if (clients.openWindow) {
                    return clients.openWindow("/");
                }
            }),
    );
};

var messaging = firebase.messaging();

// Debugging/logging -> about:debugging#/runtime/this-firefox
messaging.onBackgroundMessage(function (payload) {
    var data = payload.data.body ? payload.data : payload.notification;
    var _options = {
        icon: "/logo512.png",
    };
    if (!data) {
        self.registration.showNotification("Sway", _options);
        return;
    }

    var options = {
        icon: "/logo512.png",
        body: data.body || "",
    };
    self.registration.showNotification(data.title || "Sway", options);
});
