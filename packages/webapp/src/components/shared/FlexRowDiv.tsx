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
    className?: string;
    style?: React.CSSProperties;
    justifyContent?:
        | "space-around"
        | "space-between"
        | "space-evenly"
        | "flex-start"
        | "flex-end"
        | "center"
        | "initial";
    alignItems?:
        | "space-around"
        | "space-between"
        | "space-evenly"
        | "flex-start"
        | "flex-end"
        | "center"
        | "initial";
}

const FlexRowDiv: React.FC<IProps> = ({
    children,
    className,
    style,
    justifyContent,
    alignItems,
}) => {
    return (
        <div
            className={`d-flex flex-row ${ALIGN[alignItems || "initial"]} ${
                JUSTIFY[justifyContent || "initial"]
            } ${className || ""}`}
            style={style}
        >
            {children}
        </div>
    );
};

export default FlexRowDiv;
