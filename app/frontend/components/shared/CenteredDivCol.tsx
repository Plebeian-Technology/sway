const CenteredDivCol: React.FC<{
    children: React.ReactNode;
    style?: React.CSSProperties;
    onClick?: (e: React.MouseEvent<HTMLDivElement>) => void;
}> = ({ children, onClick, style }) => {
    return (
        <div
            onClick={onClick ? onClick : () => null}
            // className={`${classes.div} centered-div-col`}
            className={"col d-flex justify-content-center align-items-center"}
            style={style}
        >
            {children}
        </div>
    );
};

export default CenteredDivCol;
