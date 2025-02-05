const JUSTIFY = {
    "space-around": "justify-content-around",
    "space-between": "justify-content-between",
    "flex-start": "justify-content-start",
    "flex-end": "justify-content-end",
    center: "justify-content-center",
    initial: "initial",
};

const ALIGN = {
    stretch: "align-items-stretch",
    baseline: "align-items-between",
    "flex-start": "align-items-start",
    "flex-end": "align-items-end",
    center: "align-items-center",
    initial: "initial",
};
interface IProps {
    children: React.ReactNode;
    style?: React.CSSProperties;
    className?: string;
    justifyContent?: "space-around" | "space-between" | "flex-start" | "flex-end" | "center" | "initial";
    alignItems?: "stretch" | "baseline" | "flex-start" | "flex-end" | "center" | "initial";
    onClick?: () => void;
}

const FlexColumnDiv: React.FC<IProps> = ({ children, style, className, justifyContent, alignItems, onClick }) => {
    return (
        <div
            className={`d-flex flex-column ${ALIGN[alignItems || "initial"]} ${
                JUSTIFY[justifyContent || "initial"]
            } ${className || ""}`}
            style={style}
            onClick={onClick}
        >
            {children}
        </div>
    );
};

export default FlexColumnDiv;
