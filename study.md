# Building a Real-time Video Streaming Server with FFmpeg

In the world of modern web applications, real-time video streaming has become a cornerstone of user engagement and interaction. Whether it's live broadcasts, video conferencing, or interactive gaming, the ability to transmit video content with minimal latency is essential.

In this case study, I'll detail the development of an RTMP (Real-Time Messaging Protocol) streaming server using FFmpeg, a versatile multimedia framework. This server enables the reception of video streams from various clients and their subsequent broadcast to other connected clients in real time. For your development convienence, the server was containerized using [Docker](#dockerization), and a devcontainer was provided utilizing [Ubuntu-22.04 (Jammy)](https://github.com/microsoft/vscode-dev-containers/blob/main/containers/ubuntu/README.md).


## Project Goals
1. Real-time Streaming: Enable the reception and broadcasting of video streams with minimal delay.
1. Security: Implement TLS encryption using Stunnel to secure video transmission.
1. Scalability: Design a server architecture capable of handling multiple concurrent streams and clients.
1. Facebook Integration: Enable the option to stream video content directly to Facebook.
1. Monitoring and Control: Provide real-time statistics and control mechanisms for the streaming process.

## Technology Stack
- FFmpeg: A comprehensive multimedia framework for handling audio and video data.
- Bash Scripting: Used to automate tasks within the Unix/Linux environment.
- NGINX: A high-performance web server and reverse proxy, configured as a media streaming server.
- Stunnel: An open-source proxy that adds TLS encryption to network connections.
- Facebook API: Integrated for seamless interaction with the Facebook platform.

## Technical Approach (Overview)
The RTMP server was designed to act as an intermediary between clients wishing to stream video and clients wishing to consume that video content. Leveraging FFmpeg's capabilities, the server would decode incoming video streams, transcode them if necessary, and then re-encode them for distribution. NGINX, configured as an RTMP server, handled the transmission of video streams to clients using the RTMP protocol. Stunnel was employed to secure the connection to Facebook using TLS encryption.

### Server Architecture
The streaming server was designed with a modular architecture to ensure flexibility and maintainability:
- Client Interaction: Clients, such as webcams or streaming software, initiate connections to the server using the RTMP protocol.
NGINX RTMP Module: The heart of the server, this module receives incoming RTMP streams, manages client sessions, and handles the distribution of video data.
- FFmpeg Processing: FFmpeg performs the heavy lifting of decoding, transcoding (if needed), and re-encoding video streams to ensure compatibility and optimal quality for viewers.
- Stunnel (TLS Encryption): When streaming to Facebook, Stunnel establishes a secure TLS-encrypted tunnel, safeguarding the video data during transmission.
- Storage: Recorded video segments and HLS playlists are stored on disk, enabling video-on-demand (VOD) functionality.
- Monitoring and Control: NGINX provides real-time statistics on active streams and clients, along with control mechanisms for managing the streaming process.

### Implementation Steps
A Linux server was provisioned to host the RTMP server.
FFmpeg, NGINX with the RTMP module, and Stunnel were installed and configured.

#### NGINX Configuration
The NGINX configuration file ([nginx/nginx.conf](nginx/nginx.conf)) was created to enable RTMP streaming and define applications for handling live streams and Facebook integration. Security measures were implemented to restrict access to publishing and playback based on IP addresses.

The documentation used as reference for the NGINX configuration can be found from [parki/nginx-rtmps](https://github.com/parki/nginx-rtmps), [arut/nginx-rtmp-module](https://github.com/arut/nginx-rtmp-module), and [dreamsxin/nginx-rtmp-wiki](https://github.com/dreamsxin/nginx-rtmp-wiki). A summary of the configuration is provided below:

```nginx
worker_processes auto;
rtmp_auto_push on;
rtmp_auto_push_reconnect 1s;
env PATH;
error_log /dev/stderr debug;

events {
  worker_connections 1024;
}

http {
  include             mime.types;
  default_type        application/octet-stream;
  sendfile            on;
  keepalive_timeout   65;

  server {
    location /stat {
      rtmp_stat all;
      rtmp_stat_stylesheet stat.xsl;
    }

    location /stat.xsl {
      alias /usr/local/nginx/html/stat.xsl;
    }

    location /control {
      rtmp_control all;
    }

    error_page  500 502 503 504 /50x.html;

    location = /50x.html {
      root html;
    }
  }
}

rtmp {
  access_log /dev/stdout;

  server {
    listen 1935;
    listen [::]:1935 ipv6only=on;

    chunk_size 4096;

    hls on;
    hls_path /app/streams/;
    allow play 127.0.0.1;

    application live {
      live on;
      allow publish 127.0.0.1;

      recorder rec1 {
        record manual;
        record_path /app/recordings/;
        record_unique on;
        record_interval 30s;
      }

      # Verify the stream key with another service
      # on_publish http://api-container/app/broadcast/authorize;

      # Push the stream to Facebook using Stunnel
      push rtmp://127.0.0.1/facebook;
    }

    application facebook {
      live on;
      record off;
      exec_push ffmpeg -i rtmp://127.0.0.1:1935/live/$name -c:v copy -c:a copy -f flv rtmp://127.0.0.1:19350/app/$name;
    }
  }
}

```

#### Stunnel Configuration
Stunnel was configured to create a secure TLS tunnel between the server and Facebook's RTMP ingestion endpoint.

```conf
socket      = l:TCP_NODELAY=1
socket      = r:TCP_NODELAY=1
output      = /etc/stunnel/stunnel.log
cert        = /certs/server.crt
key         = /certs/server.key
compression = deflate
debug       = 7

[facebook]
client      = yes
accept      = 127.0.0.1:19350
connect     = live-api-s.facebook.com:443
checkHost   = live-api-s.facebook.com
verifyChain = no
```

#### Dockerization
For reproducability a multi-step [Dockerfile](Dockerfile) was created to download the desired NGINX and RTMP module versions, compile them, copies NGINX and Stunnel configurations.

Build the Dockerfile and run the container:

```bash
docker build -t rtmp-server .
docker run -d -p 1935:1935 -p 8080:8080 rtmp-server
```

The supported build arguments are:

`NGINX_VERSION`: The version of Nginx to build. Default is `nginx-1.19.0`.
`NGINX_RTMP_MODULE_VERSION`: The version of the Nginx RTMP module to build. Default is `1.2.1`.

And to use them:

```bash
docker build \
  --build-arg DEBIAN_VERSION=bullseye \
  --build-arg NGINX_VERSION=nginx-1.19.0 \
  --build-arg NGINX_RTMP_MODULE_VERSION=1.2.1 \
  -t rtmp-server \
  .
```

Alternatively, the [docker-compose.yml](docker-compose.yml) file can be used to build and run the container:

```bash
docker compose up -d
```
