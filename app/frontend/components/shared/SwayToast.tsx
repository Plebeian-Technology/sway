import { ToastContentProps } from "react-toastify";

const SwayToast = ({
    title,
    message,
}: {
    closeToast: () => void;
    toastProps: ToastContentProps;
    title: string;
    tada: boolean;
    message?: string;
}) => {
    return (
        <div className="col">
            <div className="bold">{title}</div>
            {message && <div>{message}</div>}
        </div>
    );
};

export default SwayToast;
