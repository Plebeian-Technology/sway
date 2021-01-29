/** @format */

module.exports = {
    root: true,
    env: {
        browser: true,
        es6: true,
        node: true,
    },
    extends: [
        "eslint:recommended",
        "plugin:@typescript-eslint/recommended",
        "plugin:import/errors",
        "plugin:import/warnings",
    ],
    parser: "@typescript-eslint/parser",
    parserOptions: {
        project: "tsconfig.json",
        sourceType: "module",
    },
    plugins: ["@typescript-eslint", "import"],
    rules: {
        "@typescript-eslint/adjacent-overload-signatures": "error",
        "@typescript-eslint/no-empty-function": "error",
        "@typescript-eslint/no-empty-interface": "warn",
        "@typescript-eslint/no-floating-promises": "error",
        "@typescript-eslint/no-namespace": "error",
        "@typescript-eslint/no-unnecessary-type-assertion": "error",
        "@typescript-eslint/prefer-for-of": "warn",
        "@typescript-eslint/triple-slash-reference": "error",
        "@typescript-eslint/unified-signatures": "warn",
        "constructor-super": "error",
        eqeqeq: ["warn", "always"],
        "import/no-deprecated": "warn",
        "import/no-extraneous-dependencies": "error",
        "import/no-unassigned-import": "warn",
        "no-cond-assign": "error",
        "no-duplicate-case": "error",
        "no-duplicate-imports": "error",
        "no-empty": [
            "error",
            {
                allowEmptyCatch: true,
            },
        ],
        "no-invalid-this": "error",
        "no-new-wrappers": "error",
        "no-param-reassign": "error",
        "no-redeclare": "error",
        "no-sequences": "error",
        "no-shadow": "off",
        "@typescript-eslint/no-shadow": ["error"],
        "no-throw-literal": "error",
        "no-unsafe-finally": "error",
        "no-unused-labels": "error",
        "no-var": "warn",
        "no-void": "error",
        "prefer-const": "warn",
    },
    settings: {
        jsdoc: {
            tagNamePreference: {
                returns: "return",
            },
        },
        "import/no-extraneous-dependencies": [
            "error",
            {
                devDependencies: true,
                optionalDependencies: false,
                peerDependencies: false,
            },
        ],
        "import/resolver": {
            typescript: {
                alwaysTryTypes: true, // always try to resolve types under `<root>@types` directory even it doesn't contain any source code, like `@types/unist`
            },
            node: {
                extensions: [".js", ".jsx", ".ts", ".tsx"],
            },
        },
    },
};
