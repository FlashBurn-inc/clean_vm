#!/usr/bin/env bash

	#font
	n=$(tput sgr0);
	bold=$(tput bold);

	#path
	way=$(cd "$(dirname "$0")"; pwd)
	source "$way/config"

apt install -y qemu-kvm libvirt-bin virtinst bridge-utils genisoimage
echo ${bold}"Work dir - $way"${n}
MAC=52:54:00:`(date; cat /proc/interrupts) | md5sum | sed -r 's/^(.{6}).*$/\1/; s/([0-9a-f]{2})/\1:/g; s/:$//;'`


echo ${bold}"Generating libvirt-networks"${n}
mkdir -p "$way/networks"
#cleanvm
echo ${bold}"cleanvm.xml"${n}
cat << cleanvm > $way/networks/$EXTERNAL_NET_NAME.xml
<network>
  <name>$EXTERNAL_NET_NAME</name>
  <forward mode="nat">
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <ip address='$EXTERNAL_NET_HOST_IP' netmask='$EXTERNAL_NET_MASK'>
    <dhcp>
      <range start='$EXTERNAL_NET.2' end='$EXTERNAL_NET.254'/>
      <host mac='$MAC' name='$VM1_NAME' ip='$VM1_EXTERNAL_IP'/>
    </dhcp>
  </ip>
</network>

cleanvm

cat $way/networks/$EXTERNAL_NET_NAME.xml

#management net
echo ${bold}"management.xml"${n}
cat << management > $way/networks/$MANAGEMENT_NET_NAME.xml
<network>
  <forward dev='$HOST_IF' mode='route'>
    <interface dev='$HOST_IF'/>
  </forward>
  <name>$MANAGEMENT_NET_NAME</name>
    <ip address='$MANAGEMENT_HOST_IP' netmask='$MANAGEMENT_NET_MASK'/>
</network>

management

cat $way/networks/$MANAGEMENT_NET_NAME.xml
sleep 3

echo ${bold}"Activating networks"${n}
virsh net-destroy $EXTERNAL_NET_NAME
virsh net-undefine $EXTERNAL_NET_NAME
virsh net-define $way/networks/$EXTERNAL_NET_NAME.xml
virsh net-start $EXTERNAL_NET_NAME
virsh net-define $way/networks/$MANAGEMENT_NET_NAME.xml
virsh net-start $MANAGEMENT_NET_NAME

#ssh
echo ${bold}"Generating SSH-keys"${n}
SSH_KEY=$(echo "$SSH_PUB_KEY" | sed 's/.pub//')
echo "$SSH_KEY"
echo -e "n" | ssh-keygen -t rsa -N "" -f $SSH_KEY


echo -e ${bold}"\nDownload Ubuntu cloud image and prepare disk"${n}
mkdir -p /var/lib/libvirt/images/$VM1_NAME
wget -O $VM1_HDD $VM_BASE_IMAGE

echo ${bold}"Creating config-drives"${n}
#meta-data vm1
mkdir -p "$way/config-drives/$VM1_NAME-config"
echo ${bold}"meta-data $VM1_NAME"${n}
cat << metadatavm1 > $way/config-drives/$VM1_NAME-config/meta-data
hostname: $VM1_NAME
local-hostname: $VM1_NAME
network-interfaces: |
  auto $VM1_EXTERNAL_IF
  iface $VM1_EXTERNAL_IF inet dhcp
  dns-nameservers $VM_DNS

  auto $VM1_MANAGEMENT_IF
  iface $VM1_MANAGEMENT_IF inet static
  address $VM1_MANAGEMENT_IP
  network $MANAGEMENT_NET_IP
  netmask $MANAGEMENT_NET_MASK
  broadcast ${MANAGEMENT_NET}.255

metadatavm1

cat $way/config-drives/$VM1_NAME-config/meta-data

#user-data vm1
echo ${bold}"user-data $VM1_NAME"${n}
cat << userdatavm1 > $way/config-drives/$VM1_NAME-config/user-data
#cloud-config
password: qwertyuiop
chpasswd: { expire: False }
ssh_authorized_keys:
  - $(cat  $SSH_PUB_KEY)

userdatavm1

cat $way/config-drives/$VM1_NAME-config/user-data

#make ISO
echo ${bold}"Make ISO"${n}
mkisofs -o $VM1_CONFIG_ISO -V cidata -r -J --quiet $way/config-drives/$VM1_NAME-config

echo ${bold}"Creating VMs"${n}
qemu-img resize $VM1_HDD +2G
virt-install \
  --connect qemu:///system \
  --virt-type=$VM_VIRT_TYPE \
  --name $VM1_NAME \
  --ram $VM1_MB_RAM \
  --vcpus=$VM1_NUM_CPU \
  --$VM_TYPE \
  --os-type=linux --os-variant=ubuntu16.04 \
  --disk path=$VM1_HDD,format=qcow2,bus=virtio,cache=none \
  --disk path=$VM1_CONFIG_ISO,device=cdrom \
  --network network=$EXTERNAL_NET_NAME,mac=$MAC \
  --network network=$MANAGEMENT_NET_NAME \
  --graphics vnc,port=-1 \
  --noautoconsole --quiet --import

echo ${bold}"Done"${n}

