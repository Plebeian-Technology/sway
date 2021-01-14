import { useSelector } from "react-redux";
import { sway } from "sway";

interface INotificationState {
    notification: sway.ISwayNotification;
}

const notificationState = (state: sway.IAppState): INotificationState =>
    state.notification;

export const useNotification = () => {
    return useSelector(notificationState);
};
