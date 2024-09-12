FROM node:18 as builder

WORKDIR /calcom

# Hardcoded environment variables
ARG NEXT_PUBLIC_LICENSE_CONSENT=agree
ARG CALCOM_TELEMETRY_DISABLED=1
ARG DATABASE_URL=postgresql://unicorn_user:magical_password@database:5432/calendso
ARG NEXTAUTH_SECRET=secret
ARG CALENDSO_ENCRYPTION_KEY=secret
ARG MAX_OLD_SPACE_SIZE=4096
ARG NEXT_PUBLIC_API_V2_URL=http://localhost:5555/api/v2

# Set environment variables with hardcoded values
ENV NEXT_PUBLIC_WEBAPP_URL=http://localhost:4000 \
    NEXT_PUBLIC_API_V2_URL=http://localhost:5555/api/v2 \
    NEXT_PUBLIC_LICENSE_CONSENT=agree \
    CALCOM_TELEMETRY_DISABLED=1 \
    DATABASE_URL=postgresql://unicorn_user:magical_password@database:5432/calendso \
    DATABASE_DIRECT_URL=postgresql://unicorn_user:magical_password@database:5432/calendso \
    NEXTAUTH_SECRET=secret \
    CALENDSO_ENCRYPTION_KEY=secret \
    NODE_OPTIONS=--max-old-space-size=$MAX_OLD_SPACE_SIZE \
    BUILD_STANDALONE=true

COPY calcom/package.json calcom/yarn.lock calcom/.yarnrc.yml calcom/playwright.config.ts calcom/turbo.json calcom/git-init.sh calcom/git-setup.sh ./
COPY calcom/.yarn ./.yarn
COPY calcom/apps/web ./apps/web
COPY calcom/apps/api/v2 ./apps/api/v2
COPY calcom/packages ./packages
COPY calcom/tests ./tests

RUN yarn config set httpTimeout 1200000
RUN npx turbo prune --scope=@calcom/web --docker
RUN yarn install
# RUN yarn db-deploy
RUN yarn --cwd packages/prisma seed-app-store
# Build and make embed servable from web/public/embed folder
RUN yarn --cwd packages/embeds/embed-core workspace @calcom/embed-core run build
RUN yarn --cwd apps/web workspace @calcom/web run build

RUN rm -rf node_modules/.cache .yarn/cache apps/web/.next/cache

FROM node:18 as builder-two

WORKDIR /calcom
ARG NEXT_PUBLIC_WEBAPP_URL=http://localhost:4000

ENV NODE_ENV production

COPY calcom/package.json calcom/.yarnrc.yml calcom/turbo.json ./
COPY calcom/.yarn ./.yarn
COPY --from=builder /calcom/yarn.lock ./yarn.lock
COPY --from=builder /calcom/node_modules ./node_modules
COPY --from=builder /calcom/packages ./packages
COPY --from=builder /calcom/apps/web ./apps/web
COPY --from=builder /calcom/packages/prisma/schema.prisma ./prisma/schema.prisma
COPY scripts scripts

ENV NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL \
    BUILT_NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL

RUN scripts/replace-placeholder.sh http://NEXT_PUBLIC_WEBAPP_URL_PLACEHOLDER ${NEXT_PUBLIC_WEBAPP_URL}

FROM node:18 as runner

WORKDIR /calcom
COPY --from=builder-two /calcom ./
ARG NEXT_PUBLIC_WEBAPP_URL=http://localhost:4000
ENV NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL \
    BUILT_NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL

ENV NODE_ENV production
EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=30s --retries=5 \
    CMD wget --spider http://localhost:4000 || exit 1

CMD ["/calcom/scripts/start.sh"]
