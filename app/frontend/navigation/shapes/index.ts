import type { TShapeKey } from "app/frontend/navigation/placeholderRegistry";
import GenericShape from "app/frontend/navigation/shapes/GenericShape";
import HomeShape from "app/frontend/navigation/shapes/HomeShape";
import ListShape from "app/frontend/navigation/shapes/ListShape";
import DetailShape from "app/frontend/navigation/shapes/DetailShape";
import FormShape from "app/frontend/navigation/shapes/FormShape";
import DocumentShape from "app/frontend/navigation/shapes/DocumentShape";
import DashboardShape from "app/frontend/navigation/shapes/DashboardShape";
import SettingsShape from "app/frontend/navigation/shapes/SettingsShape";
import CreatorShape from "app/frontend/navigation/shapes/CreatorShape";

export const SHAPE_COMPONENTS: Record<TShapeKey, React.FC> = {
    home: HomeShape,
    list: ListShape,
    detail: DetailShape,
    form: FormShape,
    document: DocumentShape,
    dashboard: DashboardShape,
    settings: SettingsShape,
    creator: CreatorShape,
    generic: GenericShape,
};
