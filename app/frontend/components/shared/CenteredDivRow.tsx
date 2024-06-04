const CenteredDivRow: React.FC<{
    children: React.ReactNode;
    style?: React.CSSProperties;
    onClick?: (e: React.MouseEvent<HTMLDivElement>) => void;
}> = ({ children, onClick, style }) => {
    return (
        <div
            onClick={onClick ? onClick : () => null}
            className={"row g-0 d-flex justify-content-center align-items-center"}
            style={style}
        >
            {children}
        </div>
    );
};

export default CenteredDivRow;
