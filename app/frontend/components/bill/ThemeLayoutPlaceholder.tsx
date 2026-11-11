import DetailShape from "app/frontend/navigation/shapes/DetailShape";
import ListShape from "app/frontend/navigation/shapes/ListShape";

// @lat: [[system-shape#What a reader sees during the round trip#Why the theme-layout Suspense fallback reuses the same shapes]]
interface IProps {
    shape?: "detail" | "list";
    className?: string;
}

const ThemeLayoutPlaceholder: React.FC<IProps> = ({ shape = "detail", className }) => {
    const Shape = shape === "list" ? ListShape : DetailShape;

    return (
        <output aria-live="polite" className={className}>
            <span className="sr-only">Loading page content…</span>
            <Shape />
        </output>
    );
};

export default ThemeLayoutPlaceholder;
