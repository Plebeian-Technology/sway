import { useCallback, useEffect, useRef, useState } from "react";
import { Info } from "lucide-react";
import { Popover, PopoverContent, PopoverTrigger } from "app/frontend/components/ui/popover";
import { cn } from "app/frontend/lib/utils";
import { FEATURE_NOTES, type TFeatureNoteKey } from "app/frontend/components/admin/creator/featureNotes";

const HOVER_GRACE_MS = 150;

interface IProps {
    note: TFeatureNoteKey;
    className?: string;
}

// @lat: [[bill-creator-shell#The Bill Creator shell#Why a feature note opens in a popover]]
const FeatureInfo: React.FC<IProps> = ({ note, className }) => {
    const entry = FEATURE_NOTES[note];
    const [isOpen, setIsOpen] = useState<boolean>(false);
    const openedByHover = useRef<boolean>(false);
    const closeTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
    const contentRef = useRef<HTMLDivElement | null>(null);

    const cancelScheduledClose = useCallback(() => {
        if (closeTimer.current !== null) {
            clearTimeout(closeTimer.current);
            closeTimer.current = null;
        }
    }, []);

    useEffect(() => cancelScheduledClose, [cancelScheduledClose]);

    const scheduleClose = useCallback(() => {
        cancelScheduledClose();
        closeTimer.current = setTimeout(() => {
            closeTimer.current = null;
            if (openedByHover.current) {
                setIsOpen(false);
            }
        }, HOVER_GRACE_MS);
    }, [cancelScheduledClose]);

    const handlePointerEnter = (event: React.PointerEvent<HTMLElement>) => {
        if (event.pointerType === "touch") {
            return;
        }
        cancelScheduledClose();
        if (!isOpen) {
            openedByHover.current = true;
            setIsOpen(true);
        }
    };

    const handlePointerLeave = (event: React.PointerEvent<HTMLElement>) => {
        if (event.pointerType === "touch") {
            return;
        }
        if (event.buttons > 0) {
            return;
        }
        scheduleClose();
    };

    const handleTriggerClick = (event: React.MouseEvent<HTMLButtonElement>) => {
        event.preventDefault();
        cancelScheduledClose();
        if (isOpen && !openedByHover.current) {
            setIsOpen(false);
            return;
        }
        if (isOpen) {
            openedByHover.current = false;
            contentRef.current?.focus();
            return;
        }
        openedByHover.current = false;
        setIsOpen(true);
    };

    const handleOpenChange = (nextOpen: boolean) => {
        cancelScheduledClose();
        openedByHover.current = false;
        setIsOpen(nextOpen);
    };

    return (
        <Popover open={isOpen} onOpenChange={handleOpenChange}>
            <PopoverTrigger asChild>
                <button
                    type="button"
                    aria-label={`Why this exists: ${entry.feature}`}
                    data-testid={`feature-info-${note}`}
                    onClick={handleTriggerClick}
                    onPointerEnter={handlePointerEnter}
                    onPointerLeave={handlePointerLeave}
                    className={cn(
                        "-my-3.5 inline-flex cursor-pointer items-center justify-center rounded-full px-2 py-3.5 align-middle text-muted-foreground transition-colors sm:-my-2 sm:py-2",
                        "hover:text-foreground focus-visible:text-foreground focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring",
                        className,
                    )}
                >
                    <Info className="size-4" aria-hidden />
                </button>
            </PopoverTrigger>
            <PopoverContent
                ref={contentRef}
                data-testid={`feature-info-content-${note}`}
                className="text-xs leading-snug border-2"
                onOpenAutoFocus={(event) => {
                    if (openedByHover.current) {
                        event.preventDefault();
                    }
                }}
                onCloseAutoFocus={(event) => {
                    if (openedByHover.current) {
                        event.preventDefault();
                        openedByHover.current = false;
                    }
                }}
                onPointerEnter={cancelScheduledClose}
                onPointerLeave={handlePointerLeave}
            >
                {entry.note}
            </PopoverContent>
        </Popover>
    );
};

export default FeatureInfo;
