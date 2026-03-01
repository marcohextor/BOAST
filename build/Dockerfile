FROM docker.io/library/golang:alpine
ENV CGO_ENABLED=0 GOOS=linux
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN apk update && apk upgrade && apk add --no-cache make
ARG SKIP_TEST=0
RUN if [ "$SKIP_TEST" = "0" ]; then make test; fi
RUN make
EXPOSE 53/udp 80 443 2096 8080 8443
CMD ["./boast"]
