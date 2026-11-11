import { preserveOpenPageOnWorkerUpdate } from "app/frontend/service-worker/registerSW";
import { useEffect } from "react";
import toast from "react-hot-toast";
import { useRegisterSW } from "virtual:pwa-register/react";
import { trackOfflineEvent } from "app/frontend/sway_utils/offlineTelemetry";

export const SWUpdateToast = (): null => {
    const { needRefresh, updateServiceWorker } = useRegisterSW({ onNeedReload: preserveOpenPageOnWorkerUpdate });
    const [isNeeded] = needRefresh;

    useEffect(() => {
        if (!isNeeded) return;
        trackOfflineEvent("sw_update_prompt_shown");
        const id = toast(
            (t) => (
                <output>
                    New version available.{" "}
                    <button
                        type="button"
                        onClick={() => {
                            toast.dismiss(t.id);
                            trackOfflineEvent("sw_update_prompt_accepted");
                            updateServiceWorker(false)
                                .then(() => window.location.reload())
                                .catch(console.error);
                        }}
                        className="cursor-pointer border-none bg-transparent p-0 font-semibold text-primary"
                    >
                        Reload
                    </button>
                </output>
            ),
            // @lat: [[toasts#Toast position is owned by the mounted Toaster]]
            { duration: Infinity },
        );
        return () => {
            toast.dismiss(id);
        };
    }, [isNeeded, updateServiceWorker]);

    return null;
};

export default SWUpdateToast;
