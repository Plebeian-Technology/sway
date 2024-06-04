import { useRef, useState, useLayoutEffect } from "react";
import { IDimensions } from "./useOpenCloseElement";

export const useDimensions = (): [
    IDimensions,
    React.Dispatch<React.SetStateAction<IDimensions>>,
    React.RefObject<HTMLDivElement>,
] => {
    const containerRef = useRef<HTMLDivElement | null>(null);

    const [dimensions, setDimensions] = useState({
        width: 1200 / 3,
        height: 1200 / 4,
    });

    const offsetWidth = containerRef.current?.offsetWidth;

    useLayoutEffect(() => {
        if (containerRef.current) {
            setDimensions({
                width: Math.round(containerRef?.current?.offsetWidth) / 3,
                height: Math.round(containerRef?.current?.offsetWidth) / 4,
            });
        }
    }, [offsetWidth]);

    return [dimensions, setDimensions, containerRef];
};
