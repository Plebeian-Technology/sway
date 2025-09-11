export default (() => {
    return {
        trailingComma: "all",
        tabWidth: 4,
        printWidth: 120,
        singleQuote: false,
        bracketSpacing: true,
        arrowParens: "always",
        plugins: ["@prettier/plugin-ruby"],
        overrides: [
            {
                files: "**/*.rb",
                options: {
                    printWidth: 80,
                    tabWidth: 2,
                    singleQuote: true,
                },
            },
            {
                files: "**/*.rbi",
                options: {
                    printWidth: 80,
                    tabWidth: 2,
                    singleQuote: true,
                },
            },
            {
                files: "**/*.rake",
                options: {
                    printWidth: 80,
                    tabWidth: 2,
                    singleQuote: true,
                },
            },
        ],
    };
})();
