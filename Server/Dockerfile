# BlackCasino-Server – Build-Kontext ist das Repository-Hauptverzeichnis:
#   docker build -f Server/Dockerfile -t blackcasino-server .
#   docker run -p 8080:8080 -v blackcasino-data:/data blackcasino-server
FROM swift:6.0-noble AS build
WORKDIR /src
COPY Packages ./Packages
COPY Server ./Server
WORKDIR /src/Server
RUN swift build -c release --static-swift-stdlib

FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libcurl4 && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/Server/.build/release/BlackCasinoServer /usr/local/bin/BlackCasinoServer
ENV PORT=8080 DATA_DIR=/data
VOLUME /data
EXPOSE 8080
USER nobody
CMD ["BlackCasinoServer"]
