// @lat: [[bills-test-category-filter-design#Why categoryFilterHref.ts builds the URL the way it does]]
export const CATEGORY_PARAM = "categories";

const categoryFilterHref = (selected: string[], pathname: string, search: string): string => {
    const params = new URLSearchParams(search);

    if (selected.length) {
        params.set(CATEGORY_PARAM, selected.join(","));
    } else {
        params.delete(CATEGORY_PARAM);
    }

    const query = params.toString();
    return `${pathname}${query ? `?${query}` : ""}`;
};

export default categoryFilterHref;
