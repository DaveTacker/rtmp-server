ARG DEBIAN_VERSION='bullseye'

# Stage 1 - Build the image
FROM buildpack-deps:${DEBIAN_VERSION} AS builder
LABEL maintainer="Dave Tacker <david.tacker@gmail.com>"
LABEL description="Docker image for Nginx with RTMP module, FFmpeg, and Stunnel."

ARG NGINX_VERSION='1.19.0'
ARG NGINX_RTMP_MODULE_VERSION='1.2.1'
ARG FFMPEG_VERSION='4.2.1'

# Download and decompress Nginx
RUN mkdir -p /tmp/build/nginx && \
    cd /tmp/build/nginx && \
    wget -O nginx-${NGINX_VERSION}.tar.gz https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && \
    tar -zxf nginx-${NGINX_VERSION}.tar.gz

# Download and decompress RTMP module
RUN mkdir -p /tmp/build/nginx-rtmp-module && \
    cd /tmp/build/nginx-rtmp-module && \
    wget -O nginx-rtmp-module-${NGINX_RTMP_MODULE_VERSION}.tar.gz https://github.com/arut/nginx-rtmp-module/archive/v${NGINX_RTMP_MODULE_VERSION}.tar.gz && \
    tar -zxf nginx-rtmp-module-${NGINX_RTMP_MODULE_VERSION}.tar.gz

# Build and install Nginx
RUN cd /tmp/build/nginx/nginx-${NGINX_VERSION} && \
    ./configure \
    --sbin-path=/usr/local/sbin/nginx \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --pid-path=/var/run/nginx/nginx.pid \
    --lock-path=/var/lock/nginx/nginx.lock \
    --http-log-path=/var/log/nginx/access.log \
    --http-client-body-temp-path=/tmp/nginx-client-body \
    --with-http_ssl_module \
    --with-threads \
    --with-ipv6 \
    --with-stream \
    --with-stream_ssl_module \
    --add-module=/tmp/build/nginx-rtmp-module/nginx-rtmp-module-${NGINX_RTMP_MODULE_VERSION} \
    --with-cc-opt="-Wimplicit-fallthrough=0" && \
    make -j $(getconf _NPROCESSORS_ONLN) && \
    make install

# Copy the stat.xsl file to the HTML directory
RUN cp /tmp/build/nginx-rtmp-module/nginx-rtmp-module-${NGINX_RTMP_MODULE_VERSION}/stat.xsl /usr/local/nginx/html/stat.xsl

# Download ffmpeg source
RUN cd /tmp/build && \
    wget http://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.gz && \
    tar -zxf ffmpeg-${FFMPEG_VERSION}.tar.gz && \
    rm ffmpeg-${FFMPEG_VERSION}.tar.gz

# Install dependencies to build FFmpeg
RUN apt-get update && \
    apt-get install -y \
    # FFmpeg dependencies
    yasm libmp3lame-dev librtmp-dev libtheora-dev libvorbis-dev libvpx-dev libx264-dev libx265-dev libfreetype6-dev

# Build ffmpeg
RUN cd /tmp/build/ffmpeg-${FFMPEG_VERSION} && \
    ./configure \
    --enable-version3 \
    --enable-gpl \
    --enable-small \
    --enable-libx264 \
    --enable-libx265 \
    --enable-libvpx \
    --enable-libtheora \
    --enable-libvorbis \
    --enable-librtmp \
    --enable-postproc \
    --enable-swresample \
    --enable-libfreetype \
    --enable-libmp3lame \
    --disable-debug \
    --disable-doc \
    --disable-ffplay \
    --extra-libs="-lpthread -lm" && \
    make -j $(getconf _NPROCESSORS_ONLN) && \
    make install

# Stage 2 - Create the final image
FROM debian:bullseye-slim

# Copy the newly compiled NGINX binary
COPY --from=builder /usr/local /usr/local
COPY --from=builder /etc/nginx /etc/nginx
COPY --from=builder /var/log/nginx /var/log/nginx
COPY --from=builder /var/lock /var/lock
COPY --from=builder /var/run/nginx /var/run/nginx

# Install dependencies
RUN export DEBIAN_FRONTEND='noninteractive' && \
    apt update && \
    apt install -y \
    ca-certificates openssl stunnel curl \
    # FFmpeg dependencies
    libpcre3-dev librtmp1 libtheora0 libvorbis-dev libmp3lame0 libvpx-dev libx264-dev libx265-dev
    # yasm libmp3lame-dev librtmp-dev libtheora-dev libvorbis-dev libvpx-dev libx264-dev libx265-dev libxcb-shm0-dev libfreetype6-dev

# Clean up the apt cache
RUN rm -rf /var/lib/apt/lists/*

# Copy the NGINX config file
COPY ./src/nginx/conf.nginx /etc/nginx/nginx.conf

# Copy stunnel config
RUN mkdir -p /etc/stunnel
COPY ./src/stunnel/stunnel.conf /etc/stunnel/stunnel.conf

# [OPTIONAL] Copy the HTML players
COPY ./players /usr/local/nginx/html/players

# Forward NGINX logs to Docker
RUN ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log && \
    ln -sf /dev/stdout /etc/stunnel/stunnel.log

# Set the working directory
WORKDIR /app

# Create directories for logs, recordings, and streams
RUN mkdir -p /mnt/logs && \
    mkdir -p /mnt/recordings && \
    mkdir -p /mnt/streams

EXPOSE 1935
EXPOSE 80

# Use bash as the default shell
RUN rm /bin/sh && ln -s /bin/bash /bin/sh
# SHELL ["/bin/bash", "-c"]

# Start stunnel and NGINX in the foreground when the container starts
CMD ["/bin/bash", "-c", "stunnel;nginx -g 'daemon off;'"]
