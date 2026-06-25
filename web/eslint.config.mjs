import antfu from "@antfu/eslint-config";

export default antfu(
    {
        formatters: true,
        ignores: ["**/build/**", "**/dist/**", "**/node_modules/**"],
        jsonc: false,
        jsx: false,
        markdown: false,
        react: false,
        stylistic: {
            indent: 4,
            quotes: "double",
            semi: true,
        },
        typescript: true,
        vue: false,
        yaml: false,
    },
    {
        rules: {
            "ts/consistent-type-definitions": "off",
            "ts/no-explicit-any": "error",
            "ts/no-unused-vars": [
                "error", {
                    args: "all",
                    argsIgnorePattern: "^_",
                    caughtErrors: "all",
                    caughtErrorsIgnorePattern: "^_",
                    destructuredArrayIgnorePattern: "^_",
                    ignoreRestSiblings: true,
                    varsIgnorePattern: "^_",
                },
            ],
        },
    },
);
