#!/usr/bin/env zsh

echo ""
echo "seeds - build.sh - install constants, utils and fire packages"
echo ""
npm i ../constants ../utils ../fire

echo ""
echo "seeds - build.sh - destroy dist"
echo ""
rm -rf dist

echo ""
echo "seeds - build.sh - config passed to tsc for compilation from tsconfig at $PWD/tsconfig.json:"
echo ""
tsc --project $PWD/tsconfig.json --showConfig | jq -c .

echo ""
echo "seeds - build.sh - build seeds with tsconfig at $PWD/tsconfig.json"
echo ""
tsc --project $PWD/tsconfig.json