if (window.history.pushState) {
    const SCROLL_RESTORATION_TIMEOUT_MS = 3000;
    const TRY_TO_SCROLL_INTERVAL_MS = 50;

    const originalPushState = window.history.pushState.bind(window.history);
    const originalReplaceState = window.history.replaceState.bind(window.history);

    window.history.pushState = function () {
        const newStateOfCurrentPage = Object.assign({}, window.history.state, {
            __scrollX: window.scrollX,
            __scrollY: window.scrollY,
        });
        originalReplaceState.call(window.history, newStateOfCurrentPage, "");

        originalPushState.apply(window.history, arguments);
    };

    window.history.replaceState = function (state, ...otherArgs) {
        const newState = Object.assign(
            {},
            {
                __scrollX: window.history.state && window.history.state.__scrollX,
                __scrollY: window.history.state && window.history.state.__scrollY,
            },
            state,
        );

        originalReplaceState.apply(window.history, [newState].concat(otherArgs));
    };

    let timeoutHandle = null;
    let scrollBarWidth = null;

    const tryToScrollTo = (scrollTarget) => {
        clearTimeout(timeoutHandle);

        const body = document.body;
        const html = document.documentElement;
        if (!scrollBarWidth) {
            scrollBarWidth = getScrollbarWidth();
        }

        const documentWidth = Math.max(
            body.scrollWidth,
            body.offsetWidth,
            html.clientWidth,
            html.scrollWidth,
            html.offsetWidth,
        );
        const documentHeight = Math.max(
            body.scrollHeight,
            body.offsetHeight,
            html.clientHeight,
            html.scrollHeight,
            html.offsetHeight,
        );

        if (
            (documentWidth + scrollBarWidth - window.innerWidth >= scrollTarget.x &&
                documentHeight + scrollBarWidth - window.innerHeight >= scrollTarget.y) ||
            Date.now() > scrollTarget.latestTimeToTry
        ) {
            window.scrollTo(scrollTarget.x, scrollTarget.y);
        } else {
            timeoutHandle = setTimeout(() => tryToScrollTo(scrollTarget), TRY_TO_SCROLL_INTERVAL_MS);
        }
    };

    const onPopState = () => {
        const state = window.history.state;

        if (state && Number.isFinite(state.__scrollX) && Number.isFinite(state.__scrollY)) {
            setTimeout(() =>
                tryToScrollTo({
                    x: state.__scrollX,
                    y: state.__scrollY,
                    latestTimeToTry: Date.now() + SCROLL_RESTORATION_TIMEOUT_MS,
                }),
            );
        }
    };

    function getScrollbarWidth() {
        const outer = document.createElement("div");
        outer.style.visibility = "hidden";
        outer.style.width = "100px";
        outer.style.msOverflowStyle = "scrollbar";

        document.body.appendChild(outer);

        const widthNoScroll = outer.offsetWidth;
        outer.style.overflow = "scroll";

        const inner = document.createElement("div");
        inner.style.width = "100%";
        outer.appendChild(inner);

        const widthWithScroll = inner.offsetWidth;

        outer.parentNode.removeChild(outer);

        return widthNoScroll - widthWithScroll;
    }

    window.addEventListener("popstate", onPopState, true);
}
