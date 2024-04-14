#!/bin/bash

case $CNI_COMMAND in 
ADD)
    if [ -f /tmp/last_allocated_ip ]; then
        n=`cat /tmp/last_allocated_ip`
    else
        n=1
    fi
    touch /tmp/file1
    touch /tmp/file2
    # Read input parameters from STDIN
    podcidr=$(cat /dev/stdin | jq -r ".podcidr")
    # Extract subnet address and prefix length
    subnet=$(echo "$podcidr" | cut -d '/' -f1)
    prefix_length=$(echo "$podcidr" | cut -d '/' -f2)
    # Convert subnet address to array separated by dots
    IFS='.' read -r -a subnet_array <<< "$subnet"
    # Increment the last octet of the subnet address
    #((subnet_array[3]++))
    subnet_array[3]='235'
    # If it reach 255, there are no more IP to allocate
    # TODO: IPAM SERVICE
    if [ ${subnet_array[3]} -eq "255" ]; then
        exit 1
    fi
    # Subnet address construction
    subnet="${subnet_array[0]}.${subnet_array[1]}.${subnet_array[2]}.${subnet_array[3]}"
    # Pod GATEWAY IP
    podcidr_gw="${subnet}/${prefix_length}"
    # Pod namespace IP
    ip=$(echo $podcidr | sed "s:0/24:$(($n+1)):g")
    # Save the IP on file so it could be tracked
    echo $(($n+1)) > /tmp/last_allocated_ip

    # Create a bridge or if it is created, turn it up
    echo 'ip link add cni0 type bridge' >> /tmp/file2
    ip link add cni0 type bridge 2>> /tmp/file2

    # Up bridge
    echo 'ip link set cni0 up' >> /tmp/file2
    ip link set cni0 up 2>> /tmp/file2

    # Add IP to bridge
    echo 'ip addr add "${podcidr_gw}" dev cni0' >> /tmp/file2
    ip addr add "${podcidr_gw}" dev cni0 2>> /tmp/file2

    # Link veth to the bridge
    host_ifname="veth$n"

    # Link Pod namespace network interface to bridge interface host_ifname
    echo 'ip link add $CNI_IFNAME type veth peer name $host_ifname' >> /tmp/file2
    ip link add $CNI_IFNAME type veth peer name $host_ifname 2>> /tmp/file2

    # Enable bridge interface
    echo 'ip link set $host_ifname up' >> /tmp/file2
    ip link set $host_ifname up 2>> /tmp/file2

    # Wire host_ifname veth as a bridge interface
    echo 'ip link set $host_ifname master cni0' >> /tmp/file2
    ip link set $host_ifname master cni0 2>> /tmp/file2
    
    echo POD >> /tmp/file1

    # Create network namespace folder, so using control groups we could join the Pod new namespace with other processes.
    mkdir -p /var/run/netns/
    ln -sfT $CNI_NETNS /var/run/netns/$CNI_CONTAINERID

    # Link Pod network interface to the Pod network namepsace (it hasnt been linked before)
    echo 'ip link set $CNI_IFNAME netns $CNI_CONTAINERID' >> /tmp/file2
    ip link set $CNI_IFNAME netns $CNI_CONTAINERID 2>> /tmp/file2

    # Enable Pod network interface, on the Pod namespace.
    echo 'ip netns exec $CNI_CONTAINERID ip link set $CNI_IFNAME up' >> /tmp/file2
    ip netns exec $CNI_CONTAINERID ip link set $CNI_IFNAME up 2>> /tmp/file2

    # Link Pod ip to Pod network interface, on the Pod namespace.
    echo 'ip netns exec $CNI_CONTAINERID ip addr add $ip/24 dev $CNI_IFNAME' >> /tmp/file2
    ip netns exec $CNI_CONTAINERID ip addr add $ip/24 dev $CNI_IFNAME 2>> /tmp/file2

    # Add route to Pod network interface, on the Pod namespace, to the bridge.
    echo 'ip netns exec $CNI_CONTAINERID ip route add default via $subnet' >> /tmp/file2
    ip netns exec $CNI_CONTAINERID ip route add default via $subnet 2>> /tmp/file2

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
    
    # DEBUG RESULT
    echo "podcidr_gw =  ${podcidr_gw}" >> /tmp/file1
    echo "podcidr =   ${podcidr}" >> /tmp/file1
    echo "subnet =   ${subnet}" >> /tmp/file1
    echo "prefix_length =  ${prefix_length}" >> /tmp/file1
    echo "ip =   ${ip}" >> /tmp/file1
    echo "host_ifname =   ${host_ifname}" >> /tmp/file1
    echo "mac =  ${mac}" >> /tmp/file1
    echo "address =   ${address}" >> /tmp/file1
    echo "template_res =  ${template_res} ">> /tmp/file1
    echo "CNI_COMMAND =   ${CNI_COMMAND}" >> /tmp/file1
    echo "CNI_IFNAME =   ${CNI_IFNAME}" >> /tmp/file1
    echo "CNI_NETNS =   ${CNI_NETNS}" >> /tmp/file1
    echo "CNI_CONTAINERID =   ${CNI_CONTAINERID}" >> /tmp/file1
    
    # NAT traffic, so source traffic could be forwaded to the root namespace interface (sNAT)
    # Allow traffic to jump from root namepsace veth bridge interface, to root namepsace main interface (enpo3s or eth0)
    iptables --table nat -A POSTROUTING -s $podcidr -j MASQUERADE 2>> /tmp/file2
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
