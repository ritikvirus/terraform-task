# Example Docker Image

This folder defines a small Docker image we can use for testing. It contains a Node.js web app that returns the text it
finds in two places:

1. The environment variable `SERVER_TEXT`. This is passed in via Terraform, so we can use it to tell when a new version
   of the code is deployed.
1. A file it downloads from the S3 path defined in the environment variable `S3_TEST_FILE`. This file is uploaded to
   S3, so we can use it to tell if ECS Task IAM Roles are working.

If either environment variable is not set, the server returns the text "Hello world!'.

This image has been pushed to the gruntwork Docker Hub account under the name `gruntwork/docker-test-webapp`.

## Build the image

```
docker build -t gruntwork/docker-test-webapp .
```

## Run the image

```
docker run --rm -it -p 3000:3000 gruntwork/docker-test-webapp
```
