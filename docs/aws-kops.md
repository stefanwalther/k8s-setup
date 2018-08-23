# Creating a Kubernetes Cluster: AWS (kops)

## Prerequisites

## Running the script

The script located at `./scripts/aws-kops.sh` provides the following commands:

`./aws-kops.sh up` - Creates a new k8s cluster.
`./aws-kops.sh create_env` - Creates a sample .env file.`
`./aws-kops.sh init_helm` - Initializes helm.
`./aws-kops.sh destroy` - Destroys the given cluster.

## Configuration

The following settings need to be set before running the script:

- `S3_BUCKET_NAME` - Name of the s3 bucket to use.
- `S3_BUCKET_REGION` - Region to use for the s3 bucket (e.g. `us-west-1`).
- `KOPS_CLUSTER_NAME` - Name of the k8s cluster (e.g. `my-cluster`).
- `NODE_COUNT` - ... (e.g. `3`)
- `NODE_SIZE` - ... (eg. `t2.medium`)

There are two ways of running the script:

Set environment variables explicitly:

```
$ S3_BUCKET_NAME=foo \
  S3_BUCKET_REGION=bar \
  ... \
  ./aws-kops.sh up
```

Using a `.env` file setting the environment variables:

```
$ ./aws-kps.sh -e ./aws-kops.env up
```

Hint: use `./aws-kops.sh create_env` to create a boilerplate of the .env file.


## `up`

`up` performs the following tasks:

- Create a S3 bucket to store the kops state
- Create a cluster definition
- Create the cluster based on the previously created definition
- Wait for the cluster to be ready
- Deploy the k8s dashboard
- Echo the required information to access the k8s-dashboard

## `create_env`

`create_env` performs the following tasks:

- Create a `./aws-kops.env` file with all environment variables needed.
  Note: This file is by default excluded from git as defined in `.gitignore`

## `destroy`

`destroy` performs the following tasks