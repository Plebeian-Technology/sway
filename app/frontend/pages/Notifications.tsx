import { router } from "@inertiajs/react";
import { useAxiosGet, useAxiosPost } from "app/frontend/hooks/useAxios";
import { handleError, logDev } from "app/frontend/sway_utils";
import { useCallback } from "react";
import { Button } from "react-bootstrap";
import { sway } from "sway";

interface IProps {
    user: sway.IUser;
    swayLocale: sway.ISwayLocale;
    push: sway.notifications.IPush
}

const Notifications: React.FC<IProps> = ({ user, push: subscription }) => {
    const { post } = useAxiosPost<sway.notifications.IPush>("/notifications/push");
    const { get: destroy } = useAxiosGet<sway.notifications.IPush>("/notifications/push/0", { skipInitialRequest: true, method: "delete" });

    const disableNotifications = useCallback(() => {
        destroy().then(() => router.reload()).catch(handleError)
    }, [])

    const saveSubscription = useCallback(
        (subscription: PushSubscription) => {
            // Extract necessary subscription data
            const endpoint = subscription.endpoint;
            const p256dh = btoa(
                String.fromCharCode.apply(
                    null,
                    // @ts-ignore
                    new Uint8Array(subscription.getKey("p256dh") as ArrayBuffer),
                ),
            );
            const auth = btoa(
                String.fromCharCode.apply(
                    null,
                    // @ts-ignore
                    new Uint8Array(subscription.getKey("auth") as ArrayBuffer),
                ),
            );

            // Send the subscription data to the server
            post({ endpoint, p256dh, auth, })
                .then((result) => {
                    if (result) {
                        logDev("Subscription successfully saved on the server.");
                        router.reload()
                    } else {
                        console.error("Error saving subscription on the server.");
                    }
                })
                .catch((error) => {
                    console.error("Error sending subscription to the server:", error);
                });
        },
        [post, user.id],
    );

    const registerServiceWorker = useCallback(() => {
        // Check if the browser supports service workers
        if ("serviceWorker" in navigator) {
            // Register the service worker script (service_worker.js)
            navigator.serviceWorker
                .register("service_worker.js")
                .then((serviceWorkerRegistration) => {
                    // Check if a subscription to push notifications already exists
                    serviceWorkerRegistration.pushManager.getSubscription().then((existingSubscription) => {
                        if (!existingSubscription) {
                            // If no subscription exists, subscribe to push notifications
                            serviceWorkerRegistration.pushManager
                                .subscribe({
                                    userVisibleOnly: true,
                                    // @ts-ignore
                                    applicationServerKey: window.VAPID_PUBLIC_KEY,
                                })
                                .then((subscription) => {
                                    // Save the subscription on the server
                                    saveSubscription(subscription);
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
                    console.warn("User rejected to allow notifications.");
                } else {
                    console.warn("User still didn't give an answer about notifications.");
                }
            });
        } else {
            console.warn("Push notifications not supported.");
        }
    }, [registerServiceWorker]);

    if (subscription?.subscribed) {
        return (
            <div className="col text-center mt-5 vh-50">
                <div className="mx-3 my-5">
                    We'll send you a push notification whenever a new Bill of the Week is released.
                </div>
                <div>
                    <Button onClick={disableNotifications} variant="outline-danger">Disable Notifications</Button>
                </div>
            </div>
        );
    } else {
        return (
            <div className="col text-center mt-5 vh-50">
                <div className="mx-3 my-5">
                    We'll send you a push notification whenever a new Bill of the Week is released.
                </div>
                <div>
                    <Button variant="primary" onClick={register}>Enable Notifications</Button>
                </div>
            </div>
        );
    }
};

export default Notifications;
