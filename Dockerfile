# syntax = docker/dockerfile:1.4

ARG NODE_VERSION=22.11.0-bookworm

# build assets & compile TypeScript

FROM --platform=$BUILDPLATFORM node:${NODE_VERSION} AS native-builder

ENV COREPACK_DEFAULT_TO_LATEST=0

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
	--mount=type=cache,target=/var/lib/apt,sharing=locked \
	rm -f /etc/apt/apt.conf.d/docker-clean \
	; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache \
	&& apt-get update \
	&& apt-get install -yqq --no-install-recommends \
	build-essential

RUN corepack enable && corepack prepare pnpm@10.0.0 --activate

WORKDIR /misskey

COPY --link ["pnpm-lock.yaml", "pnpm-workspace.yaml", "package.json", "./"]
COPY --link ["scripts", "./scripts"]
COPY --link ["packages/backend/package.json", "./packages/backend/"]
COPY --link ["packages/frontend-shared/package.json", "./packages/frontend-shared/"]
COPY --link ["packages/frontend/package.json", "./packages/frontend/"]
COPY --link ["packages/frontend-embed/package.json", "./packages/frontend-embed/"]
COPY --link ["packages/sw/package.json", "./packages/sw/"]
COPY --link ["packages/misskey-js/package.json", "./packages/misskey-js/"]
COPY --link ["packages/misskey-reversi/package.json", "./packages/misskey-reversi/"]
COPY --link ["packages/misskey-bubble-game/package.json", "./packages/misskey-bubble-game/"]

ARG NODE_ENV=production

RUN --mount=type=cache,target=/root/.local/share/pnpm/store,sharing=locked \
	pnpm i --frozen-lockfile --aggregate-output

COPY --link . ./

RUN git submodule update --init
RUN pnpm build
RUN rm -rf .git .gitmodules

# build native dependencies for target platform

FROM --platform=$TARGETPLATFORM node:${NODE_VERSION} AS target-builder

ENV COREPACK_DEFAULT_TO_LATEST=0

RUN apt-get update \
	&& apt-get install -yqq --no-install-recommends \
	build-essential

RUN corepack enable && corepack prepare pnpm@10.0.0 --activate

WORKDIR /misskey

COPY --link ["pnpm-lock.yaml", "pnpm-workspace.yaml", "package.json", "./"]
COPY --link ["scripts", "./scripts"]
COPY --link ["packages/backend/package.json", "./packages/backend/"]
COPY --link ["packages/misskey-js/package.json", "./packages/misskey-js/"]
COPY --link ["packages/misskey-reversi/package.json", "./packages/misskey-reversi/"]
COPY --link ["packages/misskey-bubble-game/package.json", "./packages/misskey-bubble-game/"]

ARG NODE_ENV=production

RUN --mount=type=cache,target=/root/.local/share/pnpm/store,sharing=locked \
	pnpm i --frozen-lockfile --aggregate-output

FROM --platform=$TARGETPLATFORM node:${NODE_VERSION}-slim AS runner

ARG UID="991"
ARG GID="991"
ENV COREPACK_DEFAULT_TO_LATEST=0

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
	ffmpeg tini curl libjemalloc-dev libjemalloc2 \
	&& ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so \
	&& corepack enable \
	&& corepack prepare pnpm@10.0.0 --activate \
	&& groupadd -g "${GID}" misskey \
	&& useradd -l -u "${UID}" -g "${GID}" -m -d /misskey misskey \
	&& find / -type d -path /sys -prune -o -type d -path /proc -prune -o -type f -perm /u+s -ignore_readdir_race -exec chmod u-s {} \; \
	&& find / -type d -path /sys -prune -o -type d -path /proc -prune -o -type f -perm /g+s -ignore_readdir_race -exec chmod g-s {} \; \
	&& apt-get clean \
	&& rm -rf /var/lib/apt/lists

USER misskey
WORKDIR /misskey

# add package.json to add pnpm
COPY --chown=misskey:misskey ./package.json ./package.json
RUN corepack install

COPY --chown=misskey:misskey --from=target-builder /misskey/node_modules ./node_modules
COPY --chown=misskey:misskey --from=target-builder /misskey/packages/backend/node_modules ./packages/backend/node_modules
COPY --chown=misskey:misskey --from=target-builder /misskey/packages/misskey-js/node_modules ./packages/misskey-js/node_modules
COPY --chown=misskey:misskey --from=target-builder /misskey/packages/misskey-reversi/node_modules ./packages/misskey-reversi/node_modules
COPY --chown=misskey:misskey --from=target-builder /misskey/packages/misskey-bubble-game/node_modules ./packages/misskey-bubble-game/node_modules
COPY --chown=misskey:misskey --from=native-builder /misskey/built ./built
COPY --chown=misskey:misskey --from=native-builder /misskey/packages/misskey-js/built ./packages/misskey-js/built
COPY --chown=misskey:misskey --from=native-builder /misskey/packages/misskey-reversi/built ./packages/misskey-reversi/built
COPY --chown=misskey:misskey --from=native-builder /misskey/packages/misskey-bubble-game/built ./packages/misskey-bubble-game/built
COPY --chown=misskey:misskey --from=native-builder /misskey/packages/backend/built ./packages/backend/built
COPY --chown=misskey:misskey --from=native-builder /misskey/fluent-emojis /misskey/fluent-emojis
COPY --chown=misskey:misskey . ./

# Ensure .git directory is removed
RUN rm -rf .git .gitmodules

ENV LD_PRELOAD=/usr/local/lib/libjemalloc.so
ENV NODE_ENV=production
ENV COREPACK_INTEGRITY_KEYS=0
HEALTHCHECK --interval=5s --retries=20 CMD ["/bin/bash", "/misskey/healthcheck.sh"]
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["pnpm", "run", "migrateandstart"]
