FROM golang:1.26 AS builder

WORKDIR /app

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o sre-lab .

FROM scratch

COPY --from=builder /app/sre-lab /sre-lab

ENTRYPOINT ["/sre-lab"]