[[_TOC_]]
# External Secrets Operator: How to setup ESO as a service

# Overview


> The [External Secrets Operator](https://external-secrets.io/v0.6.1/) extends Kubernetes with Custom Resources, which define where secrets live and how to synchronize them. The controller fetches secrets from an external API and creates Kubernetes secrets. If the secret from the external API changes, the controller will reconcile the state in the cluster and update the secrets accordingly. -- ESO Docs.

# Design Considerations

External Secrets Operator provides different modes of operation, depending on use cases.

In a multi-tenant setting, the ESO Operator can be deployed cluster wide, in the `openshift-operators` namespace for example. This makes the Operator life cycle management easier in that only one instance and version of it is deployed on the cluster. Hence, the tenants focus on providing their workload secrets specifications using the `ExternalSecret, SecretStore` Custom Resources (CRs)  to have their secrets pulled from AWS.


![ESO as a Service](assets/eso-as-a-service-diagram.PNG)


## Deployment

Three (3) helm charts are utilized to deploy this solution. Note I try to simulate a corporate environment whereby digital security mandates all container Images be pulled from a private/internal registry.


Following charts will be deployed in this order:

- **eso-operator-install**: Deploys the ESO operator and its CRDs (OperatorGroup, Subscription) in the `openshift-operators` namespace.

- **eso-operator-patch**: Deploys the resources needed to apply patches to the operator. This chart deploys an `OperatorConfig` resource which references a private container image; while the `CronJob` periodically patches the operator controller manager deployment to reference another private container image.
- **eso-secrets-sync**: Deploys the CRs (`ExternalSecret, SecretStore`) needed to integrate with AWS as well as creating kubernetes secrets backed by one or more `AWS Secret Manager` buckets.

    - `Secret`: Kubernetes object for storing the AWS IAM User credentials
    - `SecretStore`: ESO custom resource that references the `Secret`.
    - `ExternalSecret`: ESO custom resource for defining the relationship between AWS Secret Manager buckets `{key, value}` pairs and the "to be" created kubernetes secrets.

# Implementation

Screen captures and code snippets show sensitive data. This is done intentionally to facilitate understanding. The clusters will be destroyed by the time this content goes live.

# Prerequisites

- Up and running OCP 4.7+ cluster
- Access to an AWS account
- Secret Manager bucket created, required groups and policies applied
- IAM user with rights to at least read secret manager buckets
- AWS_ACCESS_KEY, AWS_SECRET_ACCESS_KEY details
- Service Account with edit access to deployment namespaces
- `podman` or `docker` or `skopeo`, `oc` or `kubectl` installed on your workstation

# Procedure

## I. AWS Secrets Manager Setup


### 1. Create the **AWS Secrets Manager** buckets

Product Service Empty Bucket
![Product Service Empty Bucket](assets/product-service-bucket-empty.png)


Shipping Service Empty Bucket
![Shipping Service Empty Bucket](assets/shipping-service-bucket-empty.png)


### 2. Place secrets data into the buckets following the `{"key": "value"}` pair format.

| IMPORTANT: For multiline strings such as certificates, properties and config files, ensure secrets values are `Base64` encoded to keep formatting. This is to avoid whitespace characters being added during storage. |
| --- |

For example to encode/decode a plaintext file, execute this command:

```
# Encode to base64
cat cleartextFile.txt | base64 > encodedFile.txt

# Decode from base64
cat encodedFile.txt | base64 -d > cleartextFile.txt
```


**Before secrets are stored**

![Product Service Bucket](assets/product-service-bucket.png)


**After secrets are stored**

Product Service Stored Secrets
![Product Service Bucket Stored](assets/product-service-bucket-stored.png)

Shipping Service Stored Secrets
![Shipping Service Bucket Stored](assets/shipping-service-bucket-stored.png)


### 3. Create IAM Policy

We will create the `eso-demo-iam` IAM User and grant it Read access to the `non-prod/eso-demo/product-service/secrets` and `non-prod/eso-demo/shipping-service/secrets` **AWS Secrets Manager** buckets.

IAM Policy with **Read** permission to the two (2) buckets. 

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetResourcePolicy",
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret",
                "secretsmanager:ListSecretVersionIds"
            ],
            "Resource": [
                "arn:aws:secretsmanager:us-east-1:804277090895:secret:non-prod/eso-demo/product-service/secrets-1R6JAf",
                "arn:aws:secretsmanager:us-east-1:804277090895:secret:non-prod/eso-demo/shipping-service/secrets-apkTYz"
            ]
        },
        {
            "Effect": "Allow",
            "Action": "secretsmanager:ListSecrets",
            "Resource": "*"
        }
    ]
}
```
<br>

### 4. Create IAM User and assign it the Policy above

Pay close attention to the checkbox.
![IAM User Add Step1](assets/iam-user-add-step1.png)

Pay close attention to the selected option on the right most tile
![IAM User Add Policy](assets/iam-user-add-policy.png)

Preview of user to be created
![IAM User Add Review](assets/iam-user-add-review.png)

User created, `Access key ID` and `Secret access key` printed
![IAM User Add Creds](assets/iam-user-add-creds.png)

Take note of the **Access key ID** and **Secret access key** info.


---

## II. External Secrets Operator Charts Deployment

We will now proceed with installing the operator and custom resources.

The setup simulates an environment whereby company digital security policy stipulates that only container images coming from the corporate private registry or OpenShift internal registry are allowed.

The [eso-operator-patch](https://github.com/luqmanbarry/external-secrets-operator-guide/tree/master/eso-operator-patch) chart is created to address this requirement. The chart deploys a `CronJob` resource among others which will periodically replace the default github container registry (ghcr.io) image defined in the `ClusterServiceVersion` by a private image pushed via `skopeo` into the OpenShift cluster `eso-build` namespace.

Clone the [guide repository](https://github.com/luqmanbarry/external-secrets-operator-guide) and use the repo folder as home directory.


### 1. Push Operator Images to internal registry

Registry format: `<INTERNAL_REGISTRY_SVC>:<PORT>/<IMAGE_NAMESPACE>/<IMAGE_STREAM_NAME>:<IMAGE_STREAM_TAG>`

- Operator Controller Manager Image: 
  - Public Image: `ghcr.io/external-secrets/external-secrets-helm-operator:v0.6.1`
  - Internal Image: `image-registry.openshift-image-registry.svc:5000/eso-build/external-secrets-helm-operator:v0.6.1`
- OperatorConfig Image:
  - Public Image: `ghcr.io/external-secrets/external-secrets:v0.6.1`
  - Internal Image: `image-registry.openshift-image-registry.svc:5000/eso-build/external-secrets:v0.6.1`


Before images were copied to internal registry **eso-build** namespace.

![eso-build Empty](assets/eso-build-empty.png)

Get public route of OpenShift internal registry

```
oc get route default-route -ojsonpath='{.spec.host}' -n openshift-image-registry

# OUTPUT
default-route-openshift-image-registry.apps.cluster-lmttg.lmttg.sandbox2014.opentlc.com
```


Run `skopeo` commands to copy images from github container registry (ghcr.io) to internal registry.

```
# Controller Manager Image
skopeo copy docker://ghcr.io/external-secrets/external-secrets-helm-operator:v0.6.1 \
    docker://default-route-openshift-image-registry.apps.cluster-lmttg.lmttg.sandbox2014.opentlc.com/eso-build/external-secrets-helm-operator:v0.6.1 \
    --dest-username $(oc whoami) \
    --dest-password $(oc whoami -t) \
    --override-os linux

# OperatorConfig Image
skopeo copy docker://ghcr.io/external-secrets/external-secrets:v0.6.1 \
    docker://default-route-openshift-image-registry.apps.cluster-lmttg.lmttg.sandbox2014.opentlc.com/eso-build/external-secrets:v0.6.1 \
    --dest-username $(oc whoami) \
    --dest-password $(oc whoami -t) \
    --override-os linux
```
<br>

After images are pushed to internal registry in **eso-build** namespace
![eso-build Images](assets/eso-build-images.png)


We are now ready to deploy the Operator and its custom resources.


### 2. Install the [eso-operator-install](https://github.com/luqmanbarry/external-secrets-operator-guide/tree/master/eso-operator-install) chart

The chart creates `Subscription` and `OperatorGroup` CRs. The `OperatorGroup` template is disabled by default because it is getting deployed in the `openshift-operators` namespace which has one already. Set the `operator.globalOperatorGroupExists: false` in the chart [values.yaml](https://github.com/luqmanbarry/external-secrets-operator-guide/blob/master/eso-operator-install/values.yaml) file if you want to include it in the chart deployment.

```
helm upgrade --install eso-operator-install ./eso-operator-install -n openshift-operators
```
<br>

After successful installation, the Operator is available in `eso-demo` despite having been deployed in a different namespace.

![ESO Installed](assets/eso-installed.png)


### 3. Install the [eso-operator-patch](https://github.com/luqmanbarry/external-secrets-operator-guide/tree/master/eso-operator-patch) chart

Before we proceeding with chart installation, let's grant service accounts in the `openshift-operators` namespace permission to pull images from `eso-build` namespace.

```
OPERATOR_NS=openshift-operators
IMAGE_NS=eso-build

oc policy add-role-to-group \
    system:image-puller system:serviceaccounts:${OPERATOR_NS} \
    --rolebinding-name=eso-image-pullers \
    --namespace=${IMAGE_NS}
```
<br>

Here's the [values.yaml](https://github.com/luqmanbarry/external-secrets-operator-guide/blob/master/eso-operator-patch/values.yaml) files, pay close attention to the Image repositories.

```
operator:
  imagePatchCronJob:
    # The service account and associated roles must be created first.
    serviceAccountName: eso-images-patch-sa
    # CronJob will run every 5min
    patchSchedule: '10 * * * *'
  
  operatorConfig:
    deploymentName: "external-secrets-operator"
    image: 
      # Public Container Image 
      #repository: ghcr.io/external-secrets/external-secrets
      # Private Container Image -- Make sure you replace 'eso-build' by your namespace
      repository: image-registry.openshift-image-registry.svc:5000/eso-build/external-secrets
      pullPolicy: IfNotPresent
      tag: 'v0.6.1'

  controllerManager:
    deploymentName: "external-secrets-operator-controller-manager"
    image:
      # Public Container Image 
      #repository: ghcr.io/external-secrets/external-secrets-helm-operator
      # Private Container Image -- Make sure you replace 'eso-build' by your namespace
      repository: image-registry.openshift-image-registry.svc:5000/eso-build/external-secrets-helm-operator
      pullPolicy: IfNotPresent
      tag: 'v0.6.1'
```
<br>

Install the helm chart

```
helm upgrade --install eso-operator-patch ./eso-operator-patch -n openshift-operators
```
<br>

After Installation
![OperatorConfig Installed](assets/operator-config-installed.png)

Resources created as a result
![OperatorConfig Resources](assets/operator-config-resources.png)

We are now ready to deploy the CRs that will synchronize our secrets from **AWS Secrets Manager**.

---


## III. Secrets Synchronization

The [eso-secrets-sync](https://github.com/luqmanbarry/external-secrets-operator-guide/tree/master/eso-secrets-sync) chart will deploy `ExternalSecret, SecretStore` that will authenticate to AWS using the `eso-demo-iam` IAM User, fetch and create kubernetes `Secrets` as specified in the [values.yaml](https://github.com/luqmanbarry/external-secrets-operator-guide/blob/master/eso-secrets-sync/values.yaml) file.

Each list item under `provider.aws.externalSecrets.apps` references one application or AWS Secrets Manager bucket.

For example:

```
provider:
  aws:
    region: us-east-1
    accessKey: "AKIA3WQVGPJHS4IJQG64"
    secretAccessKey: "EZUQOTIvg03PS7y2YboBl+uWmemET804qy2Qowlt"
    authSecretName: eso-aws-authn-secret 
    externalSecrets:
      apps:
      - name: product-service
        enabled: true
        project: eso-demo
        # Default value is 1h
        refreshInterval: 30m
        # Possible Values: "Opaque", "kubernetes.io/dockerconfigjson", "kubernetes.io/tls", "kubernetes.io/ssh-auth"
        secretType: Opaque
        localSecretName: product-service-secret
        remoteSecretBucket: "non-prod/eso-demo/product-service/secrets"
        keySets:
        # templateKey: Replace dots(.) by underscores; use snake case(substr1_substr2_substr3)
        - remoteKey: "mysql.username"
          isRemoteValueB64Encoded: false
          templateKey: "mysql_username"
          localSecretKey: "mysql.username"
      - name: shipping-service
        enabled: true
        project: eso-demo
        # Default value is 1h
        refreshInterval: 10m
        # Possible Values: "Opaque", "kubernetes.io/dockerconfigjson", "kubernetes.io/tls", "kubernetes.io/ssh-auth"
        secretType: Opaque
        localSecretName: shipping-service-secret
        remoteSecretBucket: "non-prod/eso-demo/shipping-service/secrets"
        keySets:
        # templateKey: Replace dots(.) by underscores; use snake case(substr1_substr2_substr3)
        - remoteKey: "mongodb.username"
          isRemoteValueB64EncodedIn: false
          templateKey: "mongodb_username"
          localSecretKey: "mongodb.username"
```
<br>

1. Install [eso-secrets-sync](https://github.com/luqmanbarry/external-secrets-operator-guide/tree/master/eso-secrets-sync) chart

The chart is deployed alongside apps that are going to use the generated secrets objects. In this demo that namespace is `eso-demo`.

Before chart deployment
![ExternalSecrets Empty](assets/eso-esecret-empty.png)

```
helm upgrade --install eso-secrets-sync ./eso-secrets-sync -n eso-demo
```
<br>

After chart deployment
![ExternalSecrets Ready](assets/eso-esecret-ready.png)

Product Service secrets `{key, value}` pairs generated.
![ExternalSecrets Owned Secret](assets/eso-secrets-ready-product.png)

Shipping Service secrets `{key, value}` pairs generated.
![ExternalSecrets Owned Secret](assets/eso-secrets-ready-shipping.png)

As you can see, we are able to have secrets created with their contents coming from **AWS Secrets Manager**. The `ExternalSecret` CR restores secrets upon deletion, modification of fetched `{key, value}` pairs.

# Summary

In this guide we've demonstrated how to:

- Create AWS Secrets Manager Bucket
- Place properties in the bucket
- Create IAM User and assign it a policy with **Read** permissions to specific buckets
- Deploy the `external-secrets-operator` at the cluster level
- Deploy resources with goal injecting customizations (reference private/internal registry) into the Operator created objects. Note, there are other ways to achieve the same goals.
- Create kubernetes secrets by merely specifying `app:bucket` relationship in a CR yaml file.

# Sources
- [External Secrets Operator Docs](https://external-secrets.io/v0.6.1/)
- [Guide Repository](https://github.com/luqmanbarry/external-secrets-operator-guide)
- [IAM Policy example for AWS Secrets Manager](https://docs.aws.amazon.com/mediaconnect/latest/ug/iam-policy-examples-asm-secrets.html)



















