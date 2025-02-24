import { router } from "@inertiajs/react";
import { useAxiosPost } from "app/frontend/hooks/useAxios";
import { handleError, logDev, notify } from "app/frontend/sway_utils";
import { useCallback, useEffect, useState } from "react";
import { Button } from "react-bootstrap";
import { sway } from "sway";

interface IProps {
    user: sway.IUser;
    sway_locale: sway.ISwayLocale;
    subscriptions: sway.notifications.IPushNotificationSubscription[];
}

const Notifications: React.FC<IProps> = ({ user: _user, subscriptions }) => {
    const { post } = useAxiosPost<sway.notifications.IPushNotificationSubscription>(
        "/notifications/push_notification_subscriptions",
    );
    const { post: testNotify } = useAxiosPost<sway.IValidationResult>("/notifications/push_notifications");
    const { post: destroy } = useAxiosPost<sway.notifications.IPushNotificationSubscription>(
        "/notifications/push_notification_subscriptions/destroy",
    );

    const test = useCallback(
        (e: React.MouseEvent<HTMLButtonElement>) => {
            e.preventDefault();

            navigator.serviceWorker.getRegistration().then((r) => {
                if (!r) return;

                r.pushManager.getSubscription().then((s) => {
                    if (s?.endpoint) {
                        testNotify({ endpoint: s.endpoint })
                            .then((result) => {
                                notify({
                                    level: result?.success ? "success" : "error",
                                    title:
                                        result?.message || result?.success
                                            ? "Test notification sent. You should receive one soon..."
                                            : "Failed to send test notification. Try disabling and re-enabling notifications.",
                                });
                            })
                            .catch(console.error);
                    }
                });
            });
        },
        [testNotify],
    );

    const disableNotifications = useCallback(
        (e: React.MouseEvent<HTMLButtonElement>) => {
            e.preventDefault();

            navigator.serviceWorker.getRegistration().then((r) => {
                if (!r) return;

                r.pushManager.getSubscription().then((s) => {
                    if (s?.endpoint) {
                        destroy({ endpoint: s.endpoint })
                            .then(() => router.reload())
                            .catch(handleError);
                    }
                });
            });
        },
        [destroy],
    );

    const saveSubscription = useCallback(
        (sub: PushSubscription) => {
            // Extract necessary subscription data
            const endpoint = sub.endpoint;
            const p256dh = btoa(
                String.fromCharCode.apply(
                    null,
                    // @ts-expect-error - types say this method doesn't take a Uint8Array but it does (working)
                    new Uint8Array(sub.getKey("p256dh") as ArrayBuffer),
                ),
            );
            const auth = btoa(
                String.fromCharCode.apply(
                    null,
                    // @ts-expect-error - types say this method doesn't take a Uint8Array but it does (working)
                    new Uint8Array(sub.getKey("auth") as ArrayBuffer),
                ),
            );

            // Send the subscription data to the server
            post({ endpoint, p256dh, auth })
                .then((result) => {
                    if (result) {
                        logDev("Subscription successfully saved on the server.");
                        router.reload();
                    } else {
                        console.error("Error saving subscription on the server.");
                    }
                })
                .catch((error) => {
                    console.error("Error sending subscription to the server:", error);
                });
        },
        [post],
    );

    const registerServiceWorker = useCallback(() => {
        // Check if the browser supports service workers
        if (navigator && "serviceWorker" in navigator && "VAPID_PUBLIC_KEY" in window) {
            // Register the service worker script (service_worker.js)
            navigator.serviceWorker
                .register("service_worker.js")
                .then(async (_serviceWorkerRegistration) => {
                    const serviceWorkerRegistration = await navigator.serviceWorker.ready;

                    // Check if a subscription to push notifications already exists
                    serviceWorkerRegistration.pushManager.getSubscription().then((existingSubscription) => {
                        if (!existingSubscription) {
                            // If no subscription exists, subscribe to push notifications
                            serviceWorkerRegistration.pushManager
                                .subscribe({
                                    userVisibleOnly: true,
                                    applicationServerKey: (
                                        window as Window & typeof globalThis & { VAPID_PUBLIC_KEY: string }
                                    ).VAPID_PUBLIC_KEY,
                                })
                                .then((sub) => {
                                    // Save the subscription on the server
                                    saveSubscription(sub);
                                });
                        } else {
                            saveSubscription(existingSubscription);
                        }
                    });
                })
                .catch((error) => {
                    console.error("Error during registration Service Worker:", error);
                });
        }
    }, [saveSubscription]);

    const register = useCallback(() => {
        if ("Notification" in window) {
            // Request permission from the user to send notifications
            Notification.requestPermission().then((permission) => {
                if (permission === "granted") {
                    // If permission is granted, register the service worker
                    registerServiceWorker();
                } else if (permission === "denied") {
                    console.error("User rejected to allow notifications.");
                } else {
                    console.error("User still has not givevn an answer about notifications.");
                }
            });
        } else {
            console.error("Push notifications not supported.");
            notify({
                level: "error",
                title: "Sorry, push notifications are not supported on this device.",
            });
        }
    }, [registerServiceWorker]);

    const [subscription, setSubscription] = useState<any>();
    useEffect(() => {
        if (navigator && "serviceWorker" in navigator && subscriptions) {
            navigator.serviceWorker.getRegistration().then((r) => {
                if (!r) return;

                r.pushManager.getSubscription().then((s) => {
                    if (s?.endpoint) {
                        setSubscription(subscriptions.find((sub) => s.endpoint === sub.endpoint));
                    }
                });
            });
        }
    }, [subscriptions]);

    if (subscription?.subscribed) {
        return (
            <div className="col text-center mt-5 vh-50">
                <div className="mx-3 mt-5 mb-1">
                    We'll stop sending you a push notification whenever a new Bill of the Week is released.
                </div>
                <div className="mb-5">
                    <Button onClick={disableNotifications} variant="outline-danger">
                        Disable Notifications
                    </Button>
                </div>
                <div>
                    <p>
                        If you don't receive a notification make sure that notifications are permitted for this browser
                        in your device settings.
                    </p>
                    <Button variant="outline-primary" onClick={test}>
                        Test Notifications
                    </Button>
                </div>
            </div>
        );
    } else if (navigator && "serviceWorker" in navigator) {
        return (
            <div className="col text-center mt-5 vh-50">
                <div className="mx-3 my-5">
                    We'll send you a push notification whenever a new Bill of the Week is released.
                </div>
                <div>
                    <Button variant="primary" size="lg" onClick={register}>
                        Enable Notifications
                    </Button>
                </div>
            </div>
        );
    } else {
        return (
            <div className="col text-center mt-5 vh-50">
                <div className="mx-3 my-5">
                    Your current browser window or tab does not support notifications, are you using a private tab?
                </div>
            </div>
        );
    }
};

export default Notifications;
