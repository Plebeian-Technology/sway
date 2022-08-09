#!/usr/bin/env bash

working=$(pwd)

if [ -d ${working}/../packages/types ]; then
    if [ -d ${working}/../packages/constants ]; then
        echo "Pre-install destroy constants and types and rsync from parent directories. PWD is - ${working}"
        rm -rf lib

        # Sway Types

        rm -rf types
        mkdir -p types
        rsync -avz ${working}/../packages/types/index.d.ts ${working}/types/.
        rsync -avz ${working}/../packages/types/package.json ${working}/types/.
        rsync -avz ../package-lock.json ./types/.

        # Sway Constants

        cd ${working}/../packages/constants
        npm i
        cd ${working}

        rm -rf constants
        mkdir -p constants
        rsync -avz  --include="*.ts" --include="*.json" --exclude="*" exclude="tsconfig.json" ${working}/../packages/constants/* ./constants/.
        rsync -avz ${working}/../packages/constants/package.json ${working}/constants/.
        rsync -avz ${working}/../packages/constants/locales.json ${working}/constants/.
        rsync -avz ../package-lock.json ./constants/.
        cd ${working}/constants
        echo ""
        echo "Building constants package using functions tsconfig"
        echo ""
        ${working}/node_modules/typescript/bin/tsc index.ts --module commonjs --target es2017 --outDir dist --resolveJsonModule --skipLibCheck --strict --esModuleInterop
        mkdir -p ${working}/lib/constants
        rsync -avz -d ${working}/constants/dist/* ${working}/lib/constants/.
        cd ${working}

        # Sway Utils

        cd ${working}/../packages/utils
        npm i
        cd ${working}

        rm -rf utils
        mkdir -p utils
        rsync -avz  --include="*.ts" --include="*.json" --exclude="*" exclude="tsconfig.json" ${working}/../packages/utils/* ./utils/.
        rsync -avz -d ${working}/../packages/utils/src ${working}/utils/.
        rsync -avz ${working}/../packages/utils/package.json ${working}/utils/.
        rsync -avz ../package-lock.json ./utils/.
        cd ${working}/utils
        echo ""
        echo "Building utils package using functions tsconfig"
        echo ""
        ${working}/node_modules/typescript/bin/tsc index.ts --module commonjs --target es2017 --outDir dist --resolveJsonModule --skipLibCheck --strict --esModuleInterop
        mkdir -p ${working}/lib/utils
        rsync -avz -d ${working}/utils/dist/* ${working}/lib/utils/.
        cd ${working}


        # Sway Fire

        cd ${working}/../packages/fire
        npm i
        cd ${working}

        rm -rf fire
        mkdir -p fire
        rsync -avz  --include="*.ts" --include="*.json" --exclude="*" exclude="tsconfig.json" ${working}/../packages/fire/* ./fire/.
        rsync -avz -d ${working}/../packages/fire/src ./fire/.
        rsync -avz ${working}/../packages/fire/package.json ${working}/fire/.
        rsync -avz ../package-lock.json ${working}/fire/.
        cd ${working}/fire
        echo ""
        echo "Building fire package using functions tsconfig"
        echo ""
        ${working}/node_modules/typescript/bin/tsc index.ts --module commonjs --target es2017 --outDir dist --resolveJsonModule --skipLibCheck --strict --esModuleInterop
        mkdir -p ${working}/lib/fire
        rsync -avz -d ${working}/fire/dist/* ${working}/lib/fire/.
        cd ${working}
    fi
fi
