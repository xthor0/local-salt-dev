#!/bin/bash

# the idea here:
# download the image for each OS
# update the image
# prep two versions: one with Salt, and one without

declare -a images
images[0]="https://cloud-images.ubuntu.com/bionic/current/bionic-server-cloudimg-amd64.img"
images[1]="https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2c"
images[2]="http://cdimage.debian.org/cdimage/openstack/current-10/debian-10-openstack-amd64.qcow2"
images[3]="http://cdimage.debian.org/cdimage/openstack/current-9/debian-9-openstack-amd64.qcow2"

prep_dir=${HOME}/vms/cloudimage/prep

test -d ${prep_dir} || mkdir -p ${prep_dir}
if [ $? -ne 0 ]; then
    echo "Unable to create ${prep_dir} -- exiting."
    exit 255
fi

# make sure either axel or wget is installed
test -x $(which axel)
if [ $? -eq 0 ]; then
    dlcmd=axel
else
    test -x $(which wget)
    if [ $? -eq 0 ]; then
        dlcmd=wget
    else
        echo "You need either wget or axel installed. Exiting."
        exit 255
    fi
fi

# also make sure we have virt-sysprep
test -x $(which virt-sysprep)
if [ $? -ne 0 ]; then
    echo "Unable to locate virt-sysprep - please install it."
    exit 255
fi

pushd ${prep_dir}

# download and prep each image
for url in ${images[@]}; do 
    echo "Downloading image from ${url}"
    test -f $(filename ${url}) || ${dlcmd} -q ${url}
    if [ $? -ne 0 ]; then
        echo "Error downloading from ${url} -- exiting."
        exit 255
    fi

    filename=$(basename ${url})
    case ${filename} in
        *bionic*) nametemplate=bionic;;
        *CentOS-7*) nametemplate=centos7;;
        *debian-10*) nametemplate=debian10;;
        *debian-9*) nametemplate=debian9;;
    esac

    # copy the downloaded image to new images
    img_salted=${nametemplate}_salt_$(date +%Y%m%d).qcow2
    img=${nametemplate}_$(date +%Y%m%d).qcow2
    cp ${filename} ${img}
    cp ${filename} ${img_salted}

    # virt-sysprep the images
    ## non-salt image
    virt-sysprep -a ${img} --network --update --selinux-relabel --touch /etc/cloud/cloud-init.disabled --ssh-inject root --root-password password:toor

    ## salt image
    virt-sysprep -a ${img_salted} --network --update --selinux-relabel --touch /etc/cloud/cloud-init.disabled --ssh-inject root --root-password password:toor --install curl --run-command 'curl -L https://bootstrap.saltstack.com -o /tmp/install_salt.sh && bash /tmp/install_salt.sh -P -X'

    # these should immediately be usable:
    # virt-install --virt-type=kvm --name ${vmname} --ram ${memory} --vcpus ${cpu} --os-variant=${variant} --network=bridge=virbr0,model=virtio --graphics vnc --disk path=${HDD_IMG},cache=writeback --import --noautoconsole
done 