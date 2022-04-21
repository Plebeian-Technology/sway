import { ToastContentProps } from "react-toastify";

const SwayToast = ({
    title,
    message,
    tada,
}: {
    closeToast: () => void;
    toastProps: ToastContentProps;
    title: string;
    tada: boolean;
    message?: string;
}) => {
    return (
        <div>
            <p>{title}</p>
            {message && <p>{message}</p>}
        </div>
    );
};

export default SwayToast;
