# AWS setup guide

At some point, if you want to try to run your thing on Amazon cloud instances, you'll need to do some extra setup.

## Overview

For this project, we will need two compute instances. One is a standard compute instance where we will be doing most of our development, including synthesizing and generating bitstreams for the hardware design. Another is an F2 instance for when we actually need an FPGA. F2 instance is quite expensive so we make sure to never forget to stop the instance when we don't need it.

It is also helpful to create a single AWS EFS (Elastic File Storage) volume and have both instances mount that volume. This way, we effectively get rid of the need to transfer files between machines.

AWS likes to be super modular, so in the process, you will end up generating a bunch of other stuff as well. For example, when you launch an instance, it may automatically instantiate a network interface (NIC), a block-storage volume (via Elastic Block Storage or EBS), etc. Many of these are tied to the instance and automatically deleted if you "terminate" the instance (i.e. deleting the instance). We'll mention those as we go along.

## Select availability zone

Make sure you're in the correct availability zone. If you're not in the correct zone, you may not see other instances/volumes that already exist. (It's in the top right. Should be `us-east-1`, i.e.,  US East N. Virginia).

## Add your SSH key pair

Generate a SSH key pair locally if you don't already have one. (If you don't know what this means, search it up.)

Then, through EC2 console, "Network & Security", "Key Pairs", click "Actions", "Import key pair", and put in your public key.

Please name the key pair well, since the list of key pairs is shared among all users. Ideally, the key pair name should specify who you are and what the key is for (e.g. on what machine was it generated). For example, I had `tcpc-macbook`.

## Create security groups

A security group allows a bunch of instances to communicate with each other, similarly to if they were on the same network with proper firewall settings.

Security groups can't be renamed after creation so that's kinda annoying.

I recommend creating a single security group where everything related to this entire project resides.

Set an outbound rule to allow all traffic to anywhere via IPv4 (`0.0.0.0/0`).

Set an inbound rule to allow SSH connection on port 22 (through TCP, IPv4 anywhere) and NFS connection on port 2049 (also through TCP, IPv4 anywhere).

## Create a "workspace" instance

In AWS terminology, this is called **launching** a new instance.

Please name it something you would easily remember and not confuse with other existing ones.

We will use the "FPGA Developer AMI (Ubuntu)". At the time of writing, we used version 1.17.0. Internally, it is simply Ubuntu 24.04 with a bunch of extra tools installed.

I like `m6i.4xlarge` instance type. This provides us ample compute and memory to work with. You can start smaller and upgrade later.

You will have to select a key pair you added earlier. Essentially, what this does is it sets up the initial content of `~/.ssh/authorized_keys` when the instance is created.

**This is important to get right.** Once this is done, there is no way to add keys to the file, except through SSH-ing in and modifying the file yourself. If you can't SSH in, then you have to terminate the instance and launch a new one.

This AMI requires two block-storage volumes, both of which are already configured by default for you.

Volume 1 is for the AMI root, identified as `/dev/sda1`. It houses the OS and Vivado (synthesis tool) and whatnot. I think the standard 120 GiB space is good enough. It's also where your home directory resides.

You will see that there is a tick-box that essentially ties the fate of this volume to the instance. If you terminate the instance, the volume is automatically thrown out. Be careful not to leave important files in there. (Should not be an issue anyway if you are reasonable and keep most of working directory in the EFS volume, to be created.)

Volume 2 is for storing some more data. It is identified as `/dev/sdb` and mounted via `/home/centos/src/project_data`. I'm not sure why you'd ever need this, but the AMI insists on creating this, with the minimum size set to 5GiB. I generally just get rid of this volume by detaching the storage and deleting it after I launch the instance. If you don't get rid of it, make sure to tick the box to delete it automatically on instance termination or remember to delete it if you delete the instance.

After creating the instance, if you want to change its name or any of the related entities' names (e.g. volume names), you can change them by managing tags. The tag with key "Name" is what determines the name shown on the console.

Once the instance is up and running, you can click the "Connect" button in the management console. You should be able to get instructions for connecting via SSH and just follow that example roughly.

Once you're able to SSH into the instance, you're in a good shape. Make sure to stop the instance whenever you're done working. Note that stopping is not the same as terminating, which actually erases the instance and all associated block volumes.

Note that if you stop the instance and restart again, the IP and thus the DNS hostname may change, so the old SSH command will not work.

## Create an EFS volume

This is where you really wanna store your actual data, like a synthesized bitstream, a database, etc.

Note that EFS is managed via a separate console. It's the EFS console, not EC2 console.

You should be able to follow the prompts pretty easily. Again, name your volume well. Make sure it is in the same security group as the work instance.

Now, the important thing is that you need to be able to actually mount the volume from your workspace instance.

Enter the page to manage that storage volume, click on "Network", then "Manage". Add mount targets for basically all the availability zones in the region (`us-east-1a`, `us-east-1b`, etc.). Set them to the same security group.

If you haven't yet, in your security group, make sure your inbound rules do accept NFS connections.

## Mount the volume

SSH into your workspace instance. You can check all the currently mounted volumes by running
```
mount
```

To mount the EFS instance, first, create a mount point, which is just an empty directory. I like to use `/mnt/efs`. (I don't plan on using more than one EFS volume anyway.)

```
cd /mnt
sudo mkdir efs
```

Since you created the directory as root user, for convenience, you should change owner to your account.
```
sudo chown $USER /mnt/efs
```

Now, you can mount by following instructions on the EFS console. For some reason, the EFS client isn't available on the workspace instance at the time of writing, so you'll have to use the NFS client instead. Install:
```
sudo apt update
sudo apt install nfs-common
```
The command should look something like this:
```
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport fs-SOMENUMBERS.efs.us-east-1.amazonaws.com:/ efs
```

Confirm that it's mounted by running `mount` to check that it shows on the list.

You can `cd` into the directory (`cd /mnt/efs`) and try creating files in there (e.g. `touch hello.txt`). You can the unmount by running `sudo umount /mnt/efs`, check that the file disappears, remound, and then check again.

## Set up automated mounting

According to <https://docs.aws.amazon.com/efs/latest/ug/nfs-automount-efs.html>, you can modify `/etc/fstab` to include the list of mount points to automatically attach on instance restart.

Make sure to add `nofail` option to avoid instance failing to launch. You can also delete the `projectdata` mount point if you deleted that extra, annoying 5GB volume that did nothing, that you probably already deleted. Take care not to accidentally delete the first line (root volume) nor the swap volume.

For example, my added line looks like this:
```
fs-SOMENUMBERS.efs.us-east-1.amazonaws.com:/ /mnt/efs nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,nofail,_netdev 0 0
```

## Follow Amazon's tutorials

Amazon has a pretty good tutorial on how to use their FPGAs. You'll likely need to set up SDK/HDK stuff. You'll also likely need to spin up a new AWS F2 instance. Let's call that the "FPGA" instance.
The reason we do our development on a separate workspace instance is because F2 instances are _expensive_.

I haven't documented much beyond this, so good luck.
