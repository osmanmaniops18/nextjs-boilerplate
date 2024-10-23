#!/usr/bin/env bash
set -e

# Update the host, port, user, and password to match your Supabase configuration
source ./wait-for-it.sh aws-0-ap-southeast-1.pooler.supabase.com:6543

# Run database migrations and seeds after confirming that Supabase is available
npm run migration:run
npm run seed:run:relational
npm run start:prod
