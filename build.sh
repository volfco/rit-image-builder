#!/bin/bash


qemu-img convert -f qcow2 $(echo $1) -O vmdk $(echo $1".vmdk")
#source admin-openrc.sh
#openstack image create $(echo $1) --insecure --disk-format vmdk --container-format bare --min-disk 5 --min-ram 512 --property vmware_disktype="sparse" --file $(echo $1".vmdk")