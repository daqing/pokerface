FROM scratch
# TARGETARCH is declared so buildx's per-platform value reaches the COPY;
# the example ships one static binary per architecture (see README.md).
ARG TARGETARCH
COPY hello-linux-${TARGETARCH} /hello
ENV PORT=8080
ENTRYPOINT ["/hello"]
