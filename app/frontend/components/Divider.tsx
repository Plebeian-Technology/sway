export default function Divider({ style }: Readonly<{ style?: React.CSSProperties }>) {
    return (
        <hr
            style={{ maxWidth: "30%", height: "2px", ...style }}
            className="bg-primary text-primary border-primary my-5 mx-auto"
        />
    );
}
