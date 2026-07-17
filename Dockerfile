# hadolint ignore=DL3006
ARG TRIVY_VERSION=0.72.0
ARG COSIGN_VERSION=3.1.1
ARG GH_VERSION=2.96.0
ARG CRANE_VERSION=0.21.7
ARG YQ_VERSION=4.53.3
ARG RUNNER_VERSION=2.335.1
ARG DOTNET_CHANNEL=LTS
ARG GOLANG_VERSION=1.26.5

# hadolint ignore=DL3006
# hadolint ignore=DL3002
FROM summerwind/actions-runner:v${RUNNER_VERSION}-ubuntu-24.04 AS base

LABEL org.opencontainers.image.source="https://github.com/guilhermelinosp/arc-runner"
LABEL org.opencontainers.image.description="Custom ARC runner with podman, buildah, skopeo, trivy, cosign, gh, crane, dotnet, golang"
LABEL org.opencontainers.image.version="${RUNNER_VERSION}"

# hadolint ignore=DL3002
USER root

ENV DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm

# hadolint ignore=DL3008
RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    jq \
    unzip \
    gnupg \
    wget \
    tar \
    gzip \
    bash \
    openssh-client \
    podman \
    buildah \
    skopeo \
    fuse-overlayfs \
    slirp4netns \
    uidmap \
    containernetworking-plugins \
    netavark \
    aardvark-dns \
    && apt-get remove --purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true \
    && apt-get autoremove --purge -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN mkdir -p /opt/tools/bin

# Rootless podman configuration for runner user
# subuid/subgid maps runner -> 65536 subordinate IDs for rootless containers
# policy.json allows pulling from any registry (no signature verification for CI)
RUN echo 'runner:100000:65536' > /etc/subuid && \
    echo 'runner:100000:65536' > /etc/subgid && \
    echo '{"default":[{"type":"insecureAcceptAnything"}]}' > /etc/containers/policy.json

FROM base AS yq

ARG YQ_VERSION

RUN curl -fsSLo /usr/local/bin/yq \
    "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" && \
    chmod +x /usr/local/bin/yq

FROM base AS trivy

ARG TRIVY_VERSION

RUN curl -fsSLO "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" && \
    tar -xzf "trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" -C /usr/local/bin trivy && \
    chmod +x /usr/local/bin/trivy && \
    rm -f "trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"

FROM base AS cosign

ARG COSIGN_VERSION

RUN curl -fsSLO "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-amd64" && \
    install -m 755 cosign-linux-amd64 /usr/local/bin/cosign && \
    rm -f cosign-linux-amd64

FROM base AS gh

ARG GH_VERSION

RUN curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" -o /tmp/gh.tar.gz && \
    tar -xzf /tmp/gh.tar.gz -C /tmp && \
    install -m 755 "/tmp/gh_${GH_VERSION}_linux_amd64/bin/gh" /usr/local/bin/gh && \
    rm -rf /tmp/gh*

FROM base AS crane

ARG CRANE_VERSION

RUN curl -fsSLO "https://github.com/google/go-containerregistry/releases/download/v${CRANE_VERSION}/go-containerregistry_Linux_x86_64.tar.gz" && \
    tar -xzf "go-containerregistry_Linux_x86_64.tar.gz" -C /tmp && \
    install -m 755 /tmp/crane /usr/local/bin/crane && \
    rm -rf /tmp/go-containerregistry* /tmp/crane

FROM base AS dotnet

ARG DOTNET_CHANNEL

# Download installer to a file (avoids pipe-to-bash), then run
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh && \
    bash /tmp/dotnet-install.sh --channel ${DOTNET_CHANNEL} --install-dir /usr/share/dotnet && \
    ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet && \
    rm -f /tmp/dotnet-install.sh

FROM base AS golang

ARG GOLANG_VERSION

RUN curl -fsSL "https://go.dev/dl/go${GOLANG_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tar.gz && \
    tar -xzf /tmp/go.tar.gz -C /usr/local && \
    rm -f /tmp/go.tar.gz

FROM base AS final

LABEL org.opencontainers.image.base.name="summerwind/actions-runner:v${RUNNER_VERSION}-ubuntu-24.04"

COPY --from=yq /usr/local/bin/yq /usr/local/bin/yq
COPY --from=trivy /usr/local/bin/trivy /usr/local/bin/trivy
COPY --from=cosign /usr/local/bin/cosign /usr/local/bin/cosign
COPY --from=gh /usr/local/bin/gh /usr/local/bin/gh
COPY --from=crane /usr/local/bin/crane /usr/local/bin/crane
COPY --from=dotnet /usr/share/dotnet /usr/share/dotnet
COPY --from=golang /usr/local/go /usr/local/go

# Credential helper for podman login (shared with podman-docker via ~/.docker/config.json)
RUN mkdir -p /home/runner/.gnupg /home/runner/.docker && \
    chmod 700 /home/runner/.gnupg && \
    chown -R runner:runner /home/runner && \
    ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet

# Prevent summerwind entrypoint from trying to start dockerd (which doesn't exist anymore)
ENV START_DOCKERD=false

ENV RUNNER_WORK_DIRECTORY=/home/runner/_work
ENV RUNNER_TEMP=/home/runner/_temp
ENV RUNNER_TOOL_CACHE=/home/runner/_tool
ENV PATH="${PATH}:/opt/tools/bin:/usr/share/dotnet:/usr/local/go/bin"

# .NET CI hygiene: disable telemetry, logo and first-run experience
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_NOLOGO=1
ENV DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1

# Go CI hygiene: writable cache/path for the runner user, sane defaults
ENV GOPATH=/home/runner/go
ENV GOCACHE=/home/runner/.cache/go-build
ENV GOFLAGS=-mod=mod

WORKDIR /home/runner
USER runner
