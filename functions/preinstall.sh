#!/usr/bin/env bash

if [ -d ../packages/types ]; then
    if [ -d ../packages/constants ]; then
        working=$(pwd)
        echo "Pre-install destroy constants and types and rsync from parent directories."
        rm -rf lib

        rm -rf types
        mkdir -p types
        rsync -avz ../packages/types/index.d.ts ./types/.
        rsync -avz ../packages/types/package.json ./types/.
        rsync -avz ../packages/types/tsconfig.json ./types/.
        rsync -avz ../package-lock.json ./types/.

        cd ../packages/constants
        npm i
        npm run build
        # find ./constants -type f -name "*.ts" -delete
        cd ${working}

        rm -rf constants
        mkdir -p constants
        rsync -avz --include="*.ts" --exclude="*" ../constants/* ./constants/.
        rsync -avz -d ../packages/constants/dist ./constants/.
        rsync -avz ../packages/constants/package.json ./constants/.
        rsync -avz ../packages/constants/locales.json ./constants/.
        rsync -avz ../package-lock.json ./constants/.

        cd ../packages/utils
        npm i
        npm run build
        # find ./utils -type f -name "*.ts" -delete
        cd ${working}

        rm -rf utils
        mkdir -p utils
        rsync -avz --include="*.ts" --exclude="*" ../utils/* ./utils/.
        rsync -avz -d ../packages/utils/src ./utils/.
        rsync -avz -d ../packages/utils/dist ./utils/.
        rsync -avz ../packages/utils/package.json ./utils/.

        rsync -avz ../package-lock.json ./utils/.
        cd ../packages/fire
        npm i
        npm run build
        # find ./fire -type f -name "*.ts" -delete
        cd ${working}

        rm -rf fire
        mkdir -p fire
        rsync -avz --include="*.ts" --exclude="*" ../fire/* ./fire/.
        rsync -avz -d ../packages/fire/src ./fire/.
        rsync -avz -d ../packages/fire/dist ./fire/.
        rsync -avz ../packages/fire/package.json ./fire/.
    fi
        rsync -avz ../package-lock.json ./fire/.
fi
