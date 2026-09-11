# Connect qemu vm-s together

Create a custom bridged network and assing an IP address to it

~~~
ip link add name br-qemu type bridge
ip addr add 10.0.0.1/24 dev br-qemu
~~~

Create a virtual network interface (NIC) for every qemu VM and assign to the qemu bridge

~~~
ip tuntap add dev qemu-machineA mode tap
ip link set qemu-machineA master br-qemu up
~~~

Start VM with the tap device

~~~
qemu-system-x86_64 -m 4G \
-drive file=ubuntu.qcow2,if=virtio \
-cdrom ubuntu-24.04.4-live-server-amd64.iso \
-enable-kvm -cpu host \
-netdev tap,id=net0,ifname=qemu-machineA,script=no,downscript=no \
-device virtio-net-pci,netdev=net0
~~~

NAT and Forward request made from guest VMs to host WAN interface with nftables rules

~~~
nft --file nftables-bridge-nat.conf
~~~

Bonus: assign IP through DHCP server (dnsmasq running on the host machine on a docker container)

~~~
docker build -t qemu-dnsmasq dnsmasq/
docker run --rm --network host --cap-add NET_ADMIN qemu-dnsmasq
~~~
