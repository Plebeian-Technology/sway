import { useState } from "react";

export interface IUsePaginationReturn<T> {
    page: number;
    pageCount: number;
    pageItems: T[];
    hasPrevious: boolean;
    hasNext: boolean;
    goToPage: (page: number) => void;
    goToPrevious: () => void;
    goToNext: () => void;
}

// @lat: [[pagination#Clamping the page during render, not in an effect]]
export const usePagination = <T>(items: readonly T[], pageSize: number): IUsePaginationReturn<T> => {
    const [page, setPage] = useState(1);

    const pageCount = Math.max(1, Math.ceil(items.length / pageSize));
    const currentPage = page > pageCount ? 1 : page;
    if (currentPage !== page) {
        setPage(currentPage);
    }

    const start = (currentPage - 1) * pageSize;
    const pageItems = items.slice(start, start + pageSize);

    const goToPage = (target: number) => {
        setPage(Math.min(Math.max(1, target), pageCount));
    };

    return {
        page: currentPage,
        pageCount,
        pageItems,
        hasPrevious: currentPage > 1,
        hasNext: currentPage < pageCount,
        goToPage,
        goToPrevious: () => goToPage(currentPage - 1),
        goToNext: () => goToPage(currentPage + 1),
    };
};
