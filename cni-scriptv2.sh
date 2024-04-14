#!/bin/bash

case $CNI_COMMAND in 
ADD)
    if [ -f /tmp/last_allocated_ip ]; then
        n=`cat /tmp/last_allocated_ip`
    else
        n=1
    fi

    # Read input parameters from STDIN
    podcidr=$(cat /dev/stdin | jq -r ".podcidr")

    # Extract subnet address and prefix length
    subnet=$(echo "$podcidr" | cut -d '/' -f1)
    prefix_length=$(echo "$podcidr" | cut -d '/' -f2)

    # Convert subnet address to array separated by dots
    IFS='.' read -r -a subnet_array <<< "$subnet"

    # Increment the last octet of the subnet address
    subnet_array[3]='235'
    
    # Subnet address construction
    subnet="${subnet_array[0]}.${subnet_array[1]}.${subnet_array[2]}.${subnet_array[3]}"

    # Pod GATEWAY IP
    podcidr_gw="${subnet}/${prefix_length}"

    # Pod namespace IP
    # If it reach 255, there are no more IP to allocate
    # TODO: IPAM SERVICE
    ip=$(echo $podcidr | sed "s:0/24:$(($n+1)):g")
    if [ ${ip} -eq "235" ]; then
        exit 1
    fi
    
    # Save the IP on file so it could be tracked
    echo $(($n+1)) > /tmp/last_allocated_ip

    # Create a bridge or if it is created, turn it up
    ip link add cni0 type bridge 

    # Up bridge
    ip link set cni0 up 

    # Add IP to bridge
    ip addr add "${podcidr_gw}" dev cni0 

    # Link veth to the bridge
    host_ifname="veth$n"

    # Link Pod namespace network interface to bridge interface host_ifname
    ip link add $CNI_IFNAME type veth peer name $host_ifname 

    # Enable bridge interface
    ip link set $host_ifname up 

    # Wire host_ifname veth as a bridge interface
    ip link set $host_ifname master cni0 

    # Create network namespace folder, so using control groups we could join the Pod new namespace with other processes.
    mkdir -p /var/run/netns/
    ln -sfT $CNI_NETNS /var/run/netns/$CNI_CONTAINERID

    # Link Pod network interface to the Pod network namepsace (it hasnt been linked before)
    ip link set $CNI_IFNAME netns $CNI_CONTAINERID 

    # Enable Pod network interface, on the Pod namespace.
    ip netns exec $CNI_CONTAINERID ip link set $CNI_IFNAME up 

    # Link Pod ip to Pod network interface, on the Pod namespace.
    ip netns exec $CNI_CONTAINERID ip addr add $ip/24 dev $CNI_IFNAME 

    # Add route to Pod network interface, on the Pod namespace, to the bridge.
    ip netns exec $CNI_CONTAINERID ip route add default via $subnet 

    # Obtain MAC addr
    mac=$(ip netns exec $CNI_CONTAINERID ip link show eth0 | awk '/ether/ {print $2}')
    address="${ip}/24"
    template_res='
{
    "cniVersion": "1.0.0",
    "interfaces": [
        {
            "name": "%s",
            "mac": "%s",
            "sandbox": "%s"
        }
    ],
    "ips": [
        {
            "version": "4",
            "address": "%s",
            "gateway": "%s",
            "interface": 0
        }
    ]
}'
    # Send template via stdout to the CNI plugin so it can handle state
    printf "${template_res}" $CNI_IFNAME $mac $CNI_NETNS $address $subnet
    
    # NAT traffic, so source traffic could be forwaded to the root namespace interface (sNAT)
    # Allow traffic to jump from root namepsace veth bridge interface, to root namepsace main interface (enpo3s or eth0)
    iptables --table nat -A POSTROUTING -s $podcidr -j MASQUERADE 
    iptables -t nat -A PREROUTING -p tcp --dport 80 -i enp0s3 -j DNAT --to $ip

;;
DEL)
    # Delete namespace folder
    rm -rf /var/run/netns/$CNI_CONTAINERID

;;
CHECK)
;;
VERSION)
    echo '{
    "cniVersion": "1.0.0",
    "suppoertedVersions": ["1.0.0"]
    }'
;;
*)
    echo "not supported"
    exit 1
;;

esac
