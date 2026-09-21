# ---- build stage -----------------------------------------------------
FROM golang:1.22-alpine AS build
WORKDIR /src

COPY go.mod main.go ./

# go.sum isn't committed (see the comment in go.mod) — `go mod tidy`
# resolves the dependency graph and writes it here, inside the throwaway
# build stage, so there's nothing stale to fall out of sync in git.
# CGO_ENABLED=0 produces a fully static binary: required for the
# distroless "static" base image below, which has no libc at all.
RUN go mod tidy && \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w" -o /out/demo-service .

# ---- final stage -------------------------------------------------------
# distroless/static: no shell, no package manager, no libc — about as
# small an attack surface as a container image gets. The ":nonroot" tag
# runs as uid/gid 65532, matching podSecurityContext.runAsUser/runAsGroup
# in charts/microservice/values.yaml.
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/demo-service /demo-service
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/demo-service"]
