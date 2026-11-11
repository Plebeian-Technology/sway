import { cn } from "app/frontend/lib/utils";
import { sway } from "sway";

// @lat: [[bill-category-tags-design#BillCategoryTags.tsx]]
interface IProps {
    categories?: sway.IBill["categories"];
    className?: string;
}

const BillCategoryTags: React.FC<IProps> = ({ categories, className }) => {
    if (!categories?.length) return null;

    return (
        <div className={cn("flex flex-wrap gap-2", className)}>
            {categories.map((name) => (
                <span
                    key={name}
                    className="rounded-full border-neo border-border bg-surface-3 px-3 py-1 text-xs font-semibold text-muted-foreground shadow-neo"
                >
                    {name}
                </span>
            ))}
        </div>
    );
};

export default BillCategoryTags;
