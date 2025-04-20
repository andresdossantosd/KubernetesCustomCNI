# KubernetesCustomCNI

## Kubernetes CNI (Container Network Interface) 101
We would use this approach to build our own CNI for a kubernetes cluster 
![Alt text](/images/1_u01ilFzfMjMm_TXZt2Lyiw.webp?raw=true "Kubernetes CNI basics")

## Our own architecture describe on this repo
It is really useful to have some architecture diagram to explain what we are doing, so this image help us clarify what it is really going on on the cluster-cni-custom.sh. 

So follow, this image to understand the script
![Alt text](/images/example.drawio.png?raw=true "Optional Title")

## What's next ?
Well, there are a lot of things to do next. One of them is to develop an IPAM system,to control pod ip assignment during the execution of cluster-cni-custom.sh. 

Additionally, consider how to assign network routes to different pods that use other kubernetes namespaces rather than the default namespace.