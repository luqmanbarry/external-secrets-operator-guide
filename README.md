[[_TOC_]]
# External Secrets Operator: A guide on how to set it up with AWS Secrets Manager

# Overview


> The External Secrets Operator extends Kubernetes with Custom Resources, which define where secrets live and how to synchronize them. The controller fetches secrets from an external API and creates Kubernetes secrets. If the secret from the external API changes, the controller will reconcile the state in the cluster and update the secrets accordingly. -- ESO Docs.

Uniq identifiers shown in the screen captures are not classified as sensitive. The clusters will be destroyed by the time this content goes live.

# Design Considerations

External Secrets Operator provides different modes of operation to fulfill ogranizational needs.

In a multi-tenant setting, the ESO Operator can be deployed cluster wide in the `openshift-operators` namespace. This makes the Operator life cycle management easier in that only one instance and version of it is depoyed on the cluster. Hence, the tenants focus on providing their workload secrets specifications via the 3 (`ExtrnalSecret, SecretStore, Secret`) Custom Resources  to have their secrets synchronized.


![ESO as a Service](assets/eso-as-a-service-diagram.PNG)


## Deployment

Three (3) helm charts are utilized to deploy this solution. Note I tried to simulate a private enterprise whereby it is required for all container Images used by the operator pods to be stored in a private registry.


Following charts will be deployed:

- **eso-operator-install**: Deploys the ESO operator and its CRDs (OperatorGroup, Subscription) in the `openshift-operators` namespace.

- **eso-operator-patch**: Deploys the resources needed to apply patches to the operator. This chart deploys an `OperatorConfig` resource which references a private container image; while the `CronJob` periodically patches the operator controller manager deployment to reference another privately staged container image.
- **eso-secrets-sync**: Deploys the CRs (Secret, SecretStore, ExternalSecret) needed to integrate with AWS as well as creating kubernetes secrets backed by one or more `AWS Secret Manager` buckets.

    - `Secret`: Kubernetes object for storing the AWS IAM User credentials
    - `SecretStore`: ESO custom resource that references the `Secret`.
    - `ExternalSecret`: ESO custom resources for specifying relationship between AWS Secret Manager buckets {key, value} pairs and to be created kubernetes secrets.

# Implementation

## Prerequisites

- Up and running OCP 4.7+ cluster
- Access to an AWS account
- Secret Manager bucket created, required groups and inbound/outbound policies applied
- IAM user with rights to at least read secret manager buckets
- AWS_ACCESS_KEY, AWS_SECRET_ACCESS_KEY details
- Service Account with edit access to target namespace

## Procedure



### 1. Create the **AWS Secrets Manager** buckets

Product Service Empty Bucket

![Product Service Empty Bucket](assets/product-service-bucket-empty.png)

Shipping Service Empty Bucket

![Shipping Service Empty Bucket](assets/shipping-service-bucket-empty.png)


### 2. Place sensive data into the buckets following the `{"key": "value"}` pair format.

| IMPORTANT: For multiline strings such as certificates, properties and config files, ensure secrets values are encoded to `Base64` to keep formatting. This is to avoid whitespace characters being added during storage. |
| --- |

For example to encode/decode  file, execute this command:

```
# Encoding to base64
cat cleartextFile.txt | base64 > encodedFile.txt

# Decoding from base64
cat encodedFile.txt | base64 -d > cleartextFile.txt
```

**Before secrets are stored**

![Product Service Bucket](assets/product-service-bucket.png)


**After secrets are stored**

Product Service Stored Secrets

![Product Service Bucket Stored](assets/product-service-bucket-stored.png)

Shipping Service Stored Secrets

![Shipping Service Bucket Stored](assets/shipping-service-bucket-stored.png)

### 3. Create two IAM Users, one for product-service and another for shipping-service






