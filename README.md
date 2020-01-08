# Building a local Salt development lab with libvirt on Fedora 31

_my eventual goal is to publish this as a blog post - lots of cleanup needed :)_

In my IT career, I've done a lot of Salt state development. I love the cloud - but I hate paying for stuff I don't need to pay for. Since my laptop has more CPU cores and RAM than the first VMware server I stood up back in 2008 did _ugh. this needs work_

My laptop has more CPU cores and RAM than my first VMware server did. In my heart, I'm cheap - so I see no reason to pay hourly fees for EC2 instances when I can run it locally for no additional cost.

This guide will take you through getting your Fedora 31 workstation set up so you can do local Salt state development.

## Installation

Install the necessary packages:

`sudo dnf install bridge-utils libvirt virt-install qemu-kvm libguestfs-tools-c`

Start libvirt:

`sudo systemctl start libvirtd && sudo systemctl enable libvirtd`

Grant your user access to libvirt:

`sudo usermod -aG libvirt <username>`

Add this to your local `libvirt.conf` file:

`echo 'uri_default = "qemu:///system"' | tee ~/.config/libvirt/libvirt.conf`

You'll want to reboot now (sorry). This will allow you to run `virsh` commands as a non-root user.

Run `virsh net-edit default` and make a few changes:

- `domain name` configures libvirt's dnsmasq to be authoritative for the `laptop.lab` DNS zone
- the `dns` section adds the dnsmasq equivalent of an A record for the salt master
- Also notice that the `range start` directive has been changed (previously it handed out addresses starting at `.2`)
- You don't have to use the values I've got on my system, obviously - but make sure you change the DNS and IP information in later commands if you change them here.

~~~
$ virsh net-dumpxml default
<network>
  <name>default</name>
  <uuid>17ae5689-a807-4974-a084-d4e138dc96de</uuid>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='virbr0' stp='on' delay='0'/>
  <mac address='52:54:00:c3:81:9d'/>
  <domain name='laptop.lab' localOnly='yes'/>
  <dns>
    <host ip='192.168.124.10'>
      <hostname>salt.laptop.lab</hostname>
    </host>
  </dns>
  <ip address='192.168.124.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.124.15' end='192.168.124.254'/>
    </dhcp>
  </ip>
</network>
~~~

After modifying the config, reload the network configuration:

~~~
virsh net-destroy default
virsh net-start default
~~~

## Host configuration

First, set up NetworkManager to use dnsmasq:

~~~
cat << EOF | sudo tee /etc/NetworkManager/conf.d/localdns.conf
[main]
dns=dnsmasq
EOF
~~~

Next, set up the dnsmasq instance for NetworkManager to forward DNS requests for `laptop.lab` to the dnsmasq instance that libvirt will launch:

~~~
cat << EOF | sudo tee /etc/NetworkManager/dnsmasq.d/lab.conf
server=/laptop.lab/192.168.124.1
EOF
~~~

The NFS server setup is fairly simple:

~~~
echo -e "/home/xthor/git/salt-top\t192.168.124.10(ro,no_root_squash)\n" | sudo tee /etc/exports.d/salt-master.exports

sudo systemctl enable nfs-server
sudo systemctl start nfs-server
~~~

I like to modify the SSH config so that it doesn't store host keys for my local lab. After all, they're supposed to be cattle, not pets.

~~~
# laptop lab
Host 192.168.124.*
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel QUIET

Host *.laptop.lab
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel QUIET
~~~

Finally, adjust your firewall rules, or the salt master will hang trying to mount

~~~
sudo firewall-cmd --permanent --direct --passthrough ipv4 -I INPUT -i virbr0 -j ACCEPT
sudo firewall-cmd --reload
~~~

## Cloud images

I love `cloud-init`. For local development, I find it a lot easier to use and understand than some of the alternatives (like `vagrant`).

I just download pre-built images for [CentOS](https://cloud.centos.org/centos/), [Ubuntu](http://cloud-images.ubuntu.com/) or [Debian](https://cdimage.debian.org/cdimage/openstack/), build a small disk image to provision using [NoCloud](https://cloudinit.readthedocs.io/en/latest/topics/datasources/nocloud.html), and glue it all together with a little [shell script](https://github.com/xthor0/scripts). Voila - one command builds a server in seconds.

For the salt master, I create the three files for NoCloud (`user-data`, `meta-data` and `network-config`) in my `~/tmp` directory.

## Building the salt master

These two commands allow libvirt to read images stored in my home directory:

~~~
chcon -Rt virt_image_t /home/xthor/vms/

sudo setfacl -m u:qemu:rx /home/xthor/
~~~

meta-data:

~~~
instance-id: 1
local-hostname: salt.laptop.lab
~~~

user-data:

~~~
#cloud-config
users:
  - name: xthor
    passwd: $6$iqPxVYheRyr773Xb$3lk.bY8.5GdMcJOjsd45KLhT6mRvJJLqMrfJEtkeN4M6pgSK2orOw58yHUZ.38xcwEM5Au5OfKPTrNgZRamv..
    lock_passwd: false
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDSUppn5b2njEQSw8FHqyZ0OZiPD14wEejulwnQ7gxLdQYJEqXMleHx4u/9ff3/jDXoGaBFiT2LmUTnpMV8HSj4jsB4PCoFAbq4XnlnwyBx7va/8LQOMdKsjF5W6peO+DYKh+ow9YaJvctzGPebkkNvhI0YFhZod58uoO7lyTnQXkMm8DXl6q7WhNfsZZiwr7tXicUZojU0msMiDpX1JvhGow+mKym0U/6cMgozypYfNbQ2PVkfNnadslp29O5Mfd5X4U+cbACa1sUYYqOT2Zz8C4t5QFXRY1LNokmRbcqbO01bygbE4S2TDnvRz+XZmfZTuw9MMgp7JPfo6cOfDYKf xthor
timezone: America/Denver
yum_repos:
  salt-latest:
    baseurl: https://repo.saltstack.com/yum/redhat/7/$basearch/latest
    enabled: true
    failovermethod: priority
    gpgcheck: true
    gpgkey: https://repo.saltstack.com/py3/redhat/7/x86_64/latest/SALTSTACK-GPG-KEY.pub
    name: SaltStack Latest Release Channel for RHEL/Centos $releasever
packages:
  - epel-release
  - salt-master
  - salt-ssh
  - vim-enhanced
  - bash-completion
  - wget
  - rsync
  - deltarpm
package_upgrade: true
power_state:
  delay: now
  mode: reboot
  message: Rebooting for updates
  condition: True
runcmd:
    - touch /etc/cloud/cloud-init.disabled
    - 'curl https://raw.githubusercontent.com/xthor0/scripts/libvirt/bash/salt-master-local-lab.sh | bash'
~~~

A few notes:

- the `passwd:` directive is only useful to set a password so you can log in via the VNC console. You can set it yourself with this command: `mkpasswd -m sha-512 yourpasswordhere $(pwgen -s 16 1)`
- `lock_password:` also necessary so you can actually USE the password - otherwise, the password is locked in `/etc/shadow`
- I'm not normally a fan of `bash | curl` commands, but I could find no other way of running multi-line

network-config:

~~~
## /network-config on NoCloud cidata disk
## version 1 format
## version 2 is completely different, see the docs
## version 2 is not supported by Fedora
---
version: 1
config:
- type: physical
  name: eth0
  subnets:
  - type: static
    address: 192.168.124.10/24
    gateway: 192.168.124.1
    dns_nameservers:
      - 192.168.124.1
    dns_search:
      - laptop.lab
~~~

Build the cloudinit.img file:

~~~
dd if=/dev/zero of=/home/xthor/vms/salt-nocloud.img count=1 bs=1M && mkfs.vfat -n cidata /home/xthor/vms/salt-nocloud.img

mcopy -i /home/xthor/vms/salt-nocloud.img meta-data ::
mcopy -i /home/xthor/vms/salt-nocloud.img user-data ::
mcopy -i /home/xthor/vms/salt-nocloud.img network-config ::
~~~

Build the VM:

~~~
cp /storage/cloudimage/CentOS-7-x86_64-GenericCloud-1907.img /home/xthor/vms/salt-os.qcow2

virt-install --virt-type=kvm --name salt-master --ram 2048 --vcpus 2 --os-variant=centos7.0 --network=bridge=virbr0,model=virtio --graphics vnc --disk path=/home/xthor/vms/salt-os.qcow2,cache=writeback --import --disk path=/home/xthor/vms/salt-nocloud.img,cache=none --noautoconsole
~~~

Reference the script I'm writing (after it gets merged to master branch): `salt_master_libvirt.sh`

## Accessing the states

Talk here about how you should be setting up your Salt master with `gitfs`. And, if you point the NFS mountpoint at your git repo, it makes the workflow easy:

- git checkout -b feature/devwork
- do all the state writing
- test it against the minion you spun up
- and when you're done, just commit and merge! woo!

You'll also have to cover building a `top.sls` file in `/srv/salt/top/top.sls`.


# TODO

- can the Salt master spin up new VMs?
- should I run the salt master directly on the host instead of building a VM?
- build a CentOS 8 cloud image
- update the base CentOS 7 image - learn to use virt-sysprep
    - there are a LOT of CentOS 7 updates, so if we update the base image regularly, this will go faster when I spin them up

## References

https://liquidat.wordpress.com/2017/03/03/howto-automated-dns-resolution-for-kvmlibvirt-guests-with-a-local-domain/

https://cloudinit.readthedocs.io/en/latest/topics/examples.html

https://serverfault.com/questions/403561/change-amount-of-ram-and-cpu-cores-in-kvm

https://maltegerken.de/blog/2017/01/migrate-a-vm-from-virtualbox-to-libvirt/

https://www.itfromallangles.com/2011/03/14/kvm-guests-using-virt-install-to-install-vms-from-a-cd-or-iso-imag/

http://www.teipel.ws/adding-vlans-and-bridges-using-libvirt/

