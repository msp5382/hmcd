# Clone base image from Bun

FROM alpine:3.18 AS build

# https://github.com/oven-sh/bun/releases
ARG BUN_VERSION=latest

#      build it from source. This is a temporary solution.
#      See: https://github.com/sgerrand/alpine-pkg-glibc

# https://github.com/sgerrand/alpine-pkg-glibc/releases
# https://github.com/sgerrand/alpine-pkg-glibc/issues/176
ARG GLIBC_VERSION=2.34-r0

# https://github.com/oven-sh/bun/issues/5545#issuecomment-1722461083
ARG GLIBC_VERSION_AARCH64=2.26-r1

RUN apk --no-cache add \
      ca-certificates \
      curl \
      dirmngr \
      gpg \
      gpg-agent \
      unzip \
    && arch="$(apk --print-arch)" \
    && case "${arch##*-}" in \
      x86_64) build="x64-baseline";; \
      aarch64) build="aarch64";; \
      *) echo "error: unsupported architecture: $arch"; exit 1 ;; \
    esac \
    && version="$BUN_VERSION" \
    && case "$version" in \
      latest | canary | bun-v*) tag="$version"; ;; \
      v*)                       tag="bun-$version"; ;; \
      *)                        tag="bun-v$version"; ;; \
    esac \
    && case "$tag" in \
      latest) release="latest/download"; ;; \
      *)      release="download/$tag"; ;; \
    esac \
    && curl "https://github.com/oven-sh/bun/releases/$release/bun-linux-$build.zip" \
      -fsSLO \
      --compressed \
      --retry 5 \
      || (echo "error: failed to download: $tag" && exit 1) \
    && for key in \
      "F3DCC08A8572C0749B3E18888EAB4D40A7B22B59" \
    ; do \
      gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys "$key" \
      || gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "$key" ; \
    done \
    && curl "https://github.com/oven-sh/bun/releases/$release/SHASUMS256.txt.asc" \
      -fsSLO \
      --compressed \
      --retry 5 \
    && gpg --batch --decrypt --output SHASUMS256.txt SHASUMS256.txt.asc \
      || (echo "error: failed to verify: $tag" && exit 1) \
    && grep " bun-linux-$build.zip\$" SHASUMS256.txt | sha256sum -c - \
      || (echo "error: failed to verify: $tag" && exit 1) \
    && unzip "bun-linux-$build.zip" \
    && mv "bun-linux-$build/bun" /usr/local/bin/bun \
    && rm -f "bun-linux-$build.zip" SHASUMS256.txt.asc SHASUMS256.txt \
    && chmod +x /usr/local/bin/bun \
    && cd /tmp \
    && case "${arch##*-}" in \
      x86_64) curl "https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VERSION}/glibc-${GLIBC_VERSION}.apk" \
        -fsSLO \
        --compressed \
        --retry 5 \
        || (echo "error: failed to download: glibc v${GLIBC_VERSION}" && exit 1) \
      && mv "glibc-${GLIBC_VERSION}.apk" glibc.apk \
      && curl "https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VERSION}/glibc-bin-${GLIBC_VERSION}.apk" \
        -fsSLO \
        --compressed \
        --retry 5 \
        || (echo "error: failed to download: glibc-bin v${GLIBC_VERSION}" && exit 1) \
      && mv "glibc-bin-${GLIBC_VERSION}.apk" glibc-bin.apk ;; \
      aarch64) curl "https://raw.githubusercontent.com/squishyu/alpine-pkg-glibc-aarch64-bin/master/glibc-${GLIBC_VERSION_AARCH64}.apk" \
        -fsSLO \
        --compressed \
        --retry 5 \
        || (echo "error: failed to download: glibc v${GLIBC_VERSION_AARCH64}" && exit 1) \
      && mv "glibc-${GLIBC_VERSION_AARCH64}.apk" glibc.apk \
      && curl "https://raw.githubusercontent.com/squishyu/alpine-pkg-glibc-aarch64-bin/master/glibc-bin-${GLIBC_VERSION_AARCH64}.apk" \
        -fsSLO \
        --compressed \
        --retry 5 \
        || (echo "error: failed to download: glibc-bin v${GLIBC_VERSION_AARCH64}" && exit 1) \
      && mv "glibc-bin-${GLIBC_VERSION_AARCH64}.apk" glibc-bin.apk ;; \
      *) echo "error: unsupported architecture '$arch'"; exit 1 ;; \
    esac

FROM alpine

# Disable the runtime transpiler cache by default inside Docker containers.
# On ephemeral containers, the cache is not useful
ARG BUN_RUNTIME_TRANSPILER_CACHE_PATH=0
ENV BUN_RUNTIME_TRANSPILER_CACHE_PATH=${BUN_RUNTIME_TRANSPILER_CACHE_PATH}

COPY --from=build /tmp/glibc.apk /tmp/
COPY --from=build /tmp/glibc-bin.apk /tmp/
COPY --from=build /usr/local/bin/bun /usr/local/bin/

RUN addgroup -g 1000 bun \
    && adduser -u 1000 -G bun -s /bin/sh -D bun \
    && apk --no-cache --force-overwrite --allow-untrusted add \
      /tmp/glibc.apk \
      /tmp/glibc-bin.apk \
    && rm /tmp/glibc.apk \
    && rm /tmp/glibc-bin.apk \
    && ln -s /usr/local/bin/bun /usr/local/bin/bunx \
    && which bun \
    && which bunx \
    && bun --version

USER root

RUN echo "http://ftp.halifax.rwth-aachen.de/alpine/v3.16/community" >> /etc/apk/repositories \
    && apk update

RUN apk add docker docker-cli-compose

# install git 
RUN apk add git

RUN git config --global credential.helper 'store --file /etc/.config/git/credentials'
RUN git config --global credential.useHttpPath true

# HMCD Runtime

COPY . .

RUN bun install

CMD ["bun", "run", "index.ts"]

