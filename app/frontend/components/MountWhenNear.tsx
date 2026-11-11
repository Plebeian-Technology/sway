import { useEffect, useRef, useState } from "react";

interface IProps {
    children: React.ReactNode;
    placeholderClassName?: string;
    rootMargin?: string;
}

const DEFAULT_ROOT_MARGIN = "800px 0px";
const DEFAULT_PLACEHOLDER_CLASS_NAME = "min-h-96";

const canObserve = (): boolean => typeof IntersectionObserver !== "undefined";

// @lat: [[legislator-card-mounting#Mounting is decided by a client-side observer]]
const MountWhenNear: React.FC<IProps> = ({
    children,
    placeholderClassName = DEFAULT_PLACEHOLDER_CLASS_NAME,
    rootMargin = DEFAULT_ROOT_MARGIN,
}) => {
    const [isNear, setIsNear] = useState<boolean>(() => !canObserve());
    const placeholderRef = useRef<HTMLDivElement | null>(null);

    useEffect(() => {
        if (isNear) return;

        const element = placeholderRef.current;
        if (!element) return;

        const observer = new IntersectionObserver(
            (entries) => {
                if (!entries.some((entry) => entry.isIntersecting)) return;

                setIsNear(true);
                observer.disconnect();
            },
            { rootMargin },
        );

        observer.observe(element);

        return () => observer.disconnect();
    }, [isNear, rootMargin]);

    if (isNear) return <>{children}</>;

    return (
        <div
            ref={placeholderRef}
            aria-hidden="true"
            data-testid="mount-when-near-placeholder"
            className={placeholderClassName}
        />
    );
};

export default MountWhenNear;
