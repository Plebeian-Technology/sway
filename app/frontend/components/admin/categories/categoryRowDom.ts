// @lat: [[system-shape#System shape#One process, two languages#A component file exports components and nothing else]]

export const categoryRowDomId = (id: number) => `category-row-${id}`;

// @lat: [[admin-categories-frontend-row-and-form#Scrolling to the affected row]]
export const scrollToCategoryRow = (id: number) => {
    window.requestAnimationFrame(() => {
        document.getElementById(categoryRowDomId(id))?.scrollIntoView({ behavior: "smooth", block: "center" });
    });
};
