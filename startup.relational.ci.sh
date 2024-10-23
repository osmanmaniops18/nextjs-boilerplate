#!/usr/bin/env bash
set -e

source ./NestJS/wait-for-it.sh postgres:6543
npm run migration:run
npm run seed:run:relational
npm run start:prod > prod.log 2>&1 &
/opt/wait-for-it.sh maildev:1080
/opt/wait-for-it.sh localhost:3000
npm run lint
npm run test:e2e -- --runInBand
