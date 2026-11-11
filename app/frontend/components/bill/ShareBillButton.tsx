import { useForm } from "@inertiajs/react";
import copy from "copy-to-clipboard";
import { Share2 } from "lucide-react";
import { useCallback } from "react";
import type { sway } from "sway";

import { Button } from "app/frontend/components/ui/button";
import { useUser } from "app/frontend/hooks/users/useUser";
import { ROUTES } from "app/frontend/sway_constants";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { notify } from "app/frontend/sway_utils";

interface IProps {
    bill: sway.IBill;
    className?: string;
}

const ShareBillButton: React.FC<IProps> = ({ bill, className }) => {
    const user = useUser();
    const form = useForm({ bill_id: bill.id });

    const shareOrCopy = useCallback(
        async (shareUrl: string) => {
            if (typeof navigator !== "undefined" && typeof navigator.share === "function") {
                try {
                    await navigator.share({
                        title: bill.title,
                        url: shareUrl,
                    });
                    return;
                } catch (err: unknown) {
                    if (
                        typeof err === "object" &&
                        err !== null &&
                        "name" in err &&
                        (err as { name: unknown }).name === "AbortError"
                    ) {
                        return;
                    }
                }
            }

            try {
                const copied = await copy(shareUrl);
                if (copied) {
                    notify({ level: "info", title: PARITY_COPY.bill.shareCopied });
                }
            } catch {
                return;
            }
        },
        [bill.title],
    );

    const handleClick = useCallback(() => {
        if (form.processing) {
            return;
        }

        const fallbackUrl = `${window.location.origin}/bills/${bill.id}`;
        if (!user) {
            shareOrCopy(fallbackUrl).catch(() => {});
            return;
        }

        form.transform(() => ({ bill_id: bill.id }));
        form.post(ROUTES.userBillShares, {
            preserveScroll: true,
            onSuccess: (page) => {
                const billSharePath = (page?.props as unknown as sway.IPageProps)?.flash?.bill_share_path;
                const shareUrl = billSharePath ? `${window.location.origin}${billSharePath}` : fallbackUrl;
                shareOrCopy(shareUrl).catch(() => {});
            },
            onError: () => {
                shareOrCopy(fallbackUrl).catch(() => {});
            },
        });
    }, [user, bill.id, form, shareOrCopy]);

    return (
        <Button
            type="button"
            variant="outline"
            className={className}
            data-testid="btn-share-bill"
            disabled={form.processing}
            onClick={handleClick}
        >
            <Share2 className="mr-2 size-4" aria-hidden="true" />
            {PARITY_COPY.bill.shareBill}
        </Button>
    );
};

export default ShareBillButton;
