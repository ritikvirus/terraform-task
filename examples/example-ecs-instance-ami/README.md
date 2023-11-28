# Example ECS Instance AMI

This folder contains a [Packer template](https://www.packer.io/) we use to create the [Amazon Machine Images
(AMIs)](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AMIs.html) that run on each EC2 Instance in our ECS Cluster.
Each instance is based on the [ECS-Optimized Amazon Linux AMI](https://aws.amazon.com/marketplace/pp/B00U6QTYI2/),
which has the [ECS Container Agent](http://docs.aws.amazon.com/AmazonECS/latest/developerguide/ECS_agent.html)
installed that knows how to talk to the ECS Cluster. Each instance also has a script on it from the [ecs-scripts
module](/modules/ecs-scripts) that knows how to configure the instance with the proper ECS Cluster name and Docker
registry authentication details.

## Build the AMI

1. Install [Packer](https://www.packer.io/).
1. Set up your [AWS credentials as environment variables](https://www.packer.io/docs/builders/amazon.html).
1. Set the `GITHUB_OAUTH_TOKEN` environment variable to a valid GitHub auth token with "repo" access. You can generate
   one here: https://github.com/settings/tokens
1. Run `packer build build.json` to create a new AMI in your AWS account. Note down the ID of this new AMI.