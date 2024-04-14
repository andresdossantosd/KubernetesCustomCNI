# KubernetesCustomCNI



## Kubernetes CNI (Container Network Interface) 101
We would use this approach to build our own CNI for a kubernetes cluster <br />
![Alt text](/images/1_u01ilFzfMjMm_TXZt2Lyiw.webp?raw=true "Kubernetes CNI basics")<br />
## Our own architecture describe on this repo
It is really useful to have some architecture diagram to explain what we are doing, so<br />
this image help us clarify what it is really going on on the cni-scriptv2.sh. So follow,<br />
this image to understand the script<br />
![Alt text](/images/example.drawio.png?raw=true "Optional Title")

## What's next ?
Well, there are a lot of things to do next. One of them is to develop an IPAM system,to <br />
control pod ip assignment during the execution of cni-scriptv2.sh. Additionally, consider <br />
how to assign network routes to different pods that use other kubernetes namespaces rather <br />
than the default namespace.<br />