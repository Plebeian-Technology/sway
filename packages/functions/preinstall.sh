
#!/usr/bin/env bash

if [ -d ../types ]; then
    if [ -d ../constants ]; then
        working=$(pwd)
        echo "Pre-install destroy constants and types and rsync from parent directories."
        rm -rf lib constants types fire #package-lock.json node_modules

        mkdir -p types
        rsync -avz ../types/index.d.ts ./types/.
        rsync -avz ../types/package.json ./types/.
        rsync -avz ../types/package-lock.json ./types/.
        rsync -avz ../types/tsconfig.json ./types/.

        cd ../constants
        npm i
        npm run build
        cd ${working}

        mkdir -p constants
        rsync -avz --include="*.ts" --exclude="*" ../constants/* ./constants/.
        rsync -avz -d ../constants/dist ./constants/.
        rsync -avz ../constants/package.json ./constants/.
        rsync -avz ../constants/package-lock.json ./constants/.

        cd ../fire
        npm i
        npm run build
        cd ${working}

        mkdir -p fire
        rsync -avz --include="*.ts" --exclude="*" ../fire/* ./fire/.
        rsync -avz -d ../fire/src ./fire/.
        rsync -avz -d ../fire/dist ./fire/.
        rsync -avz ../fire/package.json ./fire/.
        rsync -avz ../fire/package-lock.json ./fire/.
    fi
fi
