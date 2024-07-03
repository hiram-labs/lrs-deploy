# -- Stage 1: Build the application
FROM ubuntu:18.04 as BUILDER

# assists ./nginx.conf file envsubst
ENV DOLLAR=$
ENV DEBIAN_FRONTEND=noninteractive

RUN echo 'APT::Install-Suggests "0";' >> /etc/apt/apt.conf.d/00-docker
RUN echo 'APT::Install-Recommends "0";' >> /etc/apt/apt.conf.d/00-docker

RUN set -uex \
    && apt-get update \
    && apt-get install -y git curl gnupg ca-certificates python3 python build-essential xvfb apt-transport-https gettext \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && NODE_MAJOR=16 \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" \
        | tee /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y nodejs

COPY .env /tmp/.env
COPY nginx.conf /tmp/nginx.conf

WORKDIR /opt

RUN git clone --depth 1 --branch xrtemis https://github.com/hiram-labs/lrs-core.git \
    && cd lrs-core \
    && cp /tmp/.env .\
    && npm ci \
    && npm run build-all \
    && rm -rf ./node_modules/.cache \
    && cd $OLDPWD

RUN git clone --depth 1 --branch xrtemis https://github.com/hiram-labs/lrs-xapi-service.git \
    && cd lrs-xapi-service \
    && cp /tmp/.env .\
    && npm ci \
    && npm run build \
    && rm -rf ./node_modules/.cache \
    && cd $OLDPWD

RUN set -a && . /tmp/.env && set +a \
    && envsubst < /tmp/nginx.conf > /tmp/lrs.nginx.conf




# -- Stage 2: Create cli service image
FROM node:16-alpine as CLI

WORKDIR /app
COPY --from=BUILDER /opt/lrs-core/package.json /opt/lrs-core/package-lock.json ./
COPY --from=BUILDER /opt/lrs-core/node_modules ./node_modules
COPY --from=BUILDER /opt/lrs-core/cli/dist ./cli/dist
COPY --from=BUILDER /opt/lrs-core/lib ./lib
COPY --from=BUILDER /tmp/.env ./
COPY certs/* /etc/ssl/certs/
COPY lrsctl.sh ./

RUN npm prune --production \
    && chmod +x lrsctl.sh \
    && ln -s /app/lrsctl.sh /usr/local/bin/lrsctl

ENTRYPOINT [ "lrsctl" ]
CMD [ "help" ]



# -- Stage 3: Create web service image
FROM node:16-alpine as WEB

RUN apk update \
    && apk add nginx

WORKDIR /app/lrs-core
COPY --from=BUILDER /opt/lrs-core/package.json /opt/lrs-core/package-lock.json ./
COPY --from=BUILDER /opt/lrs-core/node_modules ./node_modules
COPY --from=BUILDER /opt/lrs-core/cli/dist ./cli/dist
COPY --from=BUILDER /opt/lrs-core/worker/dist ./worker/dist
COPY --from=BUILDER /opt/lrs-core/api/dist ./api/dist
COPY --from=BUILDER /opt/lrs-core/ui/dist ./ui/dist

WORKDIR /app/lrs-xapi-service
COPY --from=BUILDER /opt/lrs-xapi-service/package.json /opt/lrs-xapi-service/package-lock.json ./
COPY --from=BUILDER /opt/lrs-xapi-service/node_modules ./node_modules
COPY --from=BUILDER /opt/lrs-xapi-service/dist ./xapi/dist


WORKDIR /app
COPY --from=BUILDER /opt/lrs-core/lib ./lib
COPY --from=BUILDER /tmp/lrs.nginx.conf /etc/nginx/http.d/
COPY --from=BUILDER /tmp/.env ./
COPY certs/* /etc/ssl/certs/
COPY pm2.json lrsctl.sh ./

RUN npm install -g pm2 \
    && pm2 logrotate -u root \
    && cd /app/lrs-core \
    && npm prune --production \
    && cd /app/lrs-xapi-service \
    && npm prune --production \
    && cd /app \
    && chmod +x lrsctl.sh \
    && ln -s /app/lrsctl.sh /usr/local/bin/lrsctl \
    && ln -s /app/.env /app/lrs-core/.env \
    && ln -s /app/.env /app/lrs-xapi-service/.env \
    && rm /etc/nginx/http.d/default.conf \
    && mkdir -p /app/storage/tmp

EXPOSE 80
ENTRYPOINT [ "lrsctl", "start" ]