// https://github.com/DeVuDeveloper/push-notifications/blob/develop/public/service_worker.js
// https://medium.com/@dejanvu.developer/implementing-web-push-notifications-in-a-ruby-on-rails-application-dcd829e02df0    

self.addEventListener('push', function(event) {
    const notificationData = JSON.parse(event.data.text());

    const options = {
        title: notificationData.title,
        body: notificationData.body,
        icon: notificationData.icon,
    };

    event.waitUntil(
        self.registration.showNotification(notificationData.title, options)
    );
});