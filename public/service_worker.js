// https://github.com/DeVuDeveloper/push-notifications/blob/develop/public/service_worker.js
// https://medium.com/@dejanvu.developer/implementing-web-push-notifications-in-a-ruby-on-rails-application-dcd829e02df0

self.addEventListener("install", (event) => {
    console.log("Service worker installed");
});

self.addEventListener("activate", (event) => {
    console.log("Service worker activated");
});

self.addEventListener("push", function (event) {
    console.log("service_worker - event received");

    const notificationData = JSON.parse(event.data.text());

    console.log("service_worker - event data:", notificationData);

    const options = {
        title: notificationData.title,
        body: notificationData.body,
        icon: notificationData.icon,
    };

    console.log("service_worker - show notification - notification data:", options);

    event.waitUntil(self.registration.showNotification(notificationData.title, options));
});
