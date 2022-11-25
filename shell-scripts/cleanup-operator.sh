#!/bin/bash

NAMESPACE="openshift-operators"

helm uninstall eso-operator-install -n $NAMESPACE || true
helm uninstall eso-operator-patch -n $NAMESPACE || true

oc delete csv/external-secrets-operator.v0.6.1 -n $NAMESPACE
oc delete sub/external-secrets-operator -n $NAMESPACE

oc delete crd clusterexternalsecrets.external-secrets.io \
    clustersecretstores.external-secrets.io \
    externalsecrets.external-secrets.io \
    operatorconfigs.operator.external-secrets.io \
    secretstores.external-secrets.io 

oc delete operator/external-secrets-operator.openshift-operators -n $NAMESPACE