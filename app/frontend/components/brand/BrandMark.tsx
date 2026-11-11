import { cn } from "app/frontend/lib/utils";

interface IProps {
    className?: string;
}

const BrandMark: React.FC<IProps> = ({ className }) => {
    return (
        <img src="/images/sway-us-light.png" alt="Sway" className={cn("size-11 rounded-xl object-cover", className)} />
    );
};

export default BrandMark;
