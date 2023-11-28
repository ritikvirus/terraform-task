# About this Dockerfile
#
# This Dockerfile was optimized to have the smallest possible Docker image size, which would make running tests faster.
# Note that you may not always want to make image size your top priority. For example, Alpine Linux is famously small
# and also famously irritating when it comes to package management. What you save in time downloading a larger image
# may be dwarfed by the additional developer time spent dealing with Alpine's edge cases.
#
# As an alternative, consider using an official Docker node image that's not based on Alpine Linux (e.g. node:7.3.0), or
# a base image of ubuntu:16.04 and installing nodejs via apt.

FROM node:16-alpine

## Install the latest version of the AWS CLI, which the Node.js app will use to download files from S3. This is done to
## verify that ECS Task IAM Roles work.
## NOTE: aws cli depends on glibc, which alpine linux doesn't have so we need to install glibc compatibility layer
##       first. See https://github.com/aws/aws-cli/issues/4685#issuecomment-615872019 for more info.
ENV GLIBC_VER=2.31-r0
RUN apk --no-cache add binutils curl \
    && curl -sL https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub -o /etc/apk/keys/sgerrand.rsa.pub \
    && curl -sLO https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VER}/glibc-${GLIBC_VER}.apk \
    && curl -sLO https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VER}/glibc-bin-${GLIBC_VER}.apk \
    && apk add --no-cache glibc-${GLIBC_VER}.apk glibc-bin-${GLIBC_VER}.apk \
    && curl -sL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip \
    && unzip awscliv2.zip \
    && aws/install \
    && rm -rf \
        awscliv2.zip \
        aws \
        /usr/local/aws-cli/v2/*/dist/aws_completer \
        /usr/local/aws-cli/v2/*/dist/awscli/data/ac.index \
        /usr/local/aws-cli/v2/*/dist/awscli/examples \
    && apk --no-cache del binutils curl \
    && rm glibc-${GLIBC_VER}.apk \
    && rm glibc-bin-${GLIBC_VER}.apk \
    && rm -rf /var/cache/apk/* \
    && aws --version

# There is a node user in the image with uid=1000 and gid=1000. It is necessary to make EFS volume example working.
USER node

COPY server.js /home/node/server.js

EXPOSE 3000

# Note: we have to use this form of CMD rather than the array version or CTRL+C doesn't work.
CMD node /home/node/server.js
