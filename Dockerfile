FROM alpine:3.21 as builder

RUN apk update && \
    apk add zig

COPY ./ ./

RUN zig build
    
FROM scratch

COPY --from=builder /zig-out/bin/redis /bin/redis

ENTRYPOINT ["/bin/redis"]
