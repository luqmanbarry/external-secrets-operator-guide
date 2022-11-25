#!/bin/bash

NAMESPACE="openshift-operators"

set -e

helm upgrade --install eso-operator-install ./eso-operator-install -n $NAMESPACE
sleep 30
oc get sub,csv,ip,serviceaccount,deployment,pod,service -n $NAMESPACE | grep external

set +e