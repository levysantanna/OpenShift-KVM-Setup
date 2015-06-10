#!/bin/bash

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

RHN_USER_NAME=${1:-rhn-support-USER}
RHN_PASSWORD=${2:-PASSWORD}

if [[ $RHN_USER_NAME == "rhn-support-USER" ]] || [[ $RHN_PASSWORD == "PASSWORD" ]]; then 
   echo "RHN Username and Password required as firts or second argument to script!"
   exit 1
fi 

WEB_SERVER_PORT="8080"
WEB_SERVER_IP=${3:-`ip addr | grep -A 2 "enp.*\:\|wlp.*" | grep -Eo  "inet (([0-9]{1,3}\.){3}[0-9]{1,3})" | awk '{print $2}' | head -n 1`}
read -p "Is the auto selected IP for your system ($WEB_SERVER_IP) correct? [yes]: " IP_CORRECT
IP_CORRECT=${IP_CORRECT:-yes}
if [[ $IP_CORRECT == "Y" ]] || [[ $IP_CORRECT == "y" ]] || [[ $IP_CORRECT == "YES" ]] || [[ $IP_CORRECT == "Yes" ]] || [[ $IP_CORRECT == "yes" ]]; then
    echo " Using $WEB_SERVER_IP:$WEB_SERVER_PORT for local webserver (during kickstart process)."
else
    if [[ -z $3 ]]; then 
        read -p " Please manualy set the IP of your system or use a sane default! [192.168.100.1]: " WEB_SERVER_IP
        WEB_SERVER_IP=${WEB_SERVER_IP:-192.168.100.1}
    fi
fi


DOMAIN=${4:-example.com}
APP_DOMAIN="cloudapps.${DOMAIN}"
MASTER_FQDN="ose-master.${DOMAIN}"
NODE1_FQDN="ose-node1.${DOMAIN}"
NODE2_FQDN="ose-node2.${DOMAIN}"
WORKSTATION_FQDN="ose-workstation.${DOMAIN}"
ROOT_PASSWORD="redhat"
USER_PASSWORD="$ROOT_PASSWORD"
IPA_PASSWORD="${ROOT_PASSWORD}1234"

DISK_SIZE="10G"
RAM_SIZE="2048"

DOWNLOAD_URI="http://porkchop.redhat.com/released/RHEL-7/7.1/Server/x86_64/iso/RHEL-7.1-20150219.1-Server-x86_64-dvd1.iso"
LIBVIRT_IMG="/var/lib/libvirt/images/RHEL-7.1_OSE.iso"

beta_training_repo="https://github.com/openshift/training.git"
beta_installer_repo="https://github.com/detiber/openshift-ansible.git -b v3-beta4"

#### DON'T EDIT BELOW HERE
SIMPLE_WEB_PID=""

function ctrl_c() {
    echo "** CTRL-C Triggered Exiting!"
    if [[ -n $SIMPLE_WEB_PID ]]; then
        echo " Killing SimpleWeb Server"
        kill $SIMPLE_WEB_PID
    fi
    exit 1 
}

sudo -v ; RESULT=$?
if [[ $RESULT -eq 0 ]]; then 
    echo "Sudo Rights Confirmed! Continuing.."
else
    echo "Script Requires User have sudo rights, may have issues setting up virtual enviornment." 
fi

for package in virt-install; do 
    if [[ $(rpm -q $package --quiet; echo $?) -eq 0 ]]; then
        echo " $package is installed!"
    else
        echo "WARNING: $package is not installed. Please install it to continue!"
        exit 1
    fi
done    

IMG=false
while [[ $IMG == false ]]; do 
    echo "Checking to see if you have $LIBVIRT_IMG so that the script can use it! {Loop until this is obtained. ctrl+c to exit loop"
    if [[ -f $LIBVIRT_IMG ]]; then
       echo "Image $LIBVIRT_IMG was found.. {continuing}!" 
       IMG=true
       break
    else
       echo "You will need to get a Red Hat Enterprise 7.1 ISO from https://access.redhat.com/downloads/content/69/ver=/rhel---7/7.1/x86_64/product-downloads to continue."
       echo " Once Downloaded, plaece move and save the file as $LIBVIRT_IMG"

       read -p "  Do you want the script to make sure selinx and file ownershift of $LIBVIRT_IMG are correct now? [yes]: " PERM_CORRECT
       PERM_CORRECT=${PERM_CORRECT:-yes}
       if [[ $PERM_CORRECT == "Y" ]] || [[ $PERM_CORRECT == "y" ]] || [[ $PERM_CORRECT == "YES" ]] || [[ $PERM_CORRECT == "Yes" ]] || [[ $PERM_CORRECT == "yes" ]]; then
           sudo chmod 644 ${LIBVIRT_IMG}
           sudo chown qemu:qemu ${LIBVIRT_IMG}
           sudo restorecon -rv /var/lib/libvirt/images/
           IMG=true
       fi 
    fi
done 

echo "Creating Files"
if [[ -a ose_template_kickstart.ks ]]; then
    echo " File ose_template_kickstart.ks already exists!"
else
    echo " Creating ose_template_kickstart.ks"
    echo "
lang en_US
keyboard us
timezone America/New_York --isUtc
rootpw $ROOT_PASSWORD
# rootpw $1$3bZ38OOk$rRJy1WZNp0pwT4mtovdqp/ --iscrypted
#platform x86, AMD64, or Intel EM64T
reboot
text
cdrom
bootloader --location=mbr --append="rhgb quiet crashkernel=auto"
zerombr
clearpart --all --initlabel
autopart
auth --passalgo=sha512 --useshadow
selinux --enforcing
firewall --enabled
firstboot --disable
#network --onboot yes --device eth0 --noipv6 --bootproto=static --ip=192.168.100.2 --netmask=255.255.255.0 --gateway=192.168.100.1 --nameserver=192.168.100.1 --hostname=$MASTER_FQDN
#network --onboot yes --device eth0 --noipv6 --bootproto=static --ip=192.168.100.3 --netmask=255.255.255.0 --gateway=192.168.100.1 --nameserver=192.168.100.1 --hostname=$NODE1_FQDN
#network --onboot yes --device eth0 --noipv6 --bootproto=static --ip=192.168.100.4 --netmask=255.255.255.0 --gateway=192.168.100.1 --nameserver=192.168.100.1 --hostname=$NODE2_FQDN
#network --onboot yes --device eth0 --noipv6 --bootproto=static --ip=192.168.100.5 --netmask=255.255.255.0 --gateway=192.168.100.1 --nameserver=192.168.100.1 --hostname=$WORKSTATION_FQDN
%post
/usr/sbin/subscription-manager register --username ${RHN_USER_NAME} --password ${RHN_PASSWORD} --autosubscribe
/usr/sbin/subscription-manager repos --disable="*"
/usr/sbin/subscription-manager repos --enable="rhel-7-server-rpms" --enable="rhel-server-7-ose-beta-rpms" --enable="rhel-7-server-extras-rpms" --enable "rhel-7-server-optional-rpms"
yum -y install http://dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-5.noarch.rpm
sed -i -e "s/^enabled=1/enabled=0/" /etc/yum.repos.d/epel.repo
yum -y --enablerepo=epel install ansible sshpass
yum -y remove NetworkManager*
yum -y install deltarpm wget vim-enhanced net-tools bind-utils screen git httpd-tools docker
systemctl start docker
docker pull registry.access.redhat.com/openshift3_beta/ose-haproxy-router:v0.4.3.2
docker pull registry.access.redhat.com/openshift3_beta/ose-deployer:v0.4.3.2
docker pull registry.access.redhat.com/openshift3_beta/ose-sti-builder:v0.4.3.2
docker pull registry.access.redhat.com/openshift3_beta/ose-docker-builder:v0.4.3.2
docker pull registry.access.redhat.com/openshift3_beta/ose-pod:v0.4.3.2
docker pull registry.access.redhat.com/openshift3_beta/ose-docker-registry:v0.4.3.2
docker pull registry.access.redhat.com/openshift3_beta/sti-basicauthurl:latest
docker pull registry.access.redhat.com/openshift3_beta/ruby-20-rhel7
docker pull registry.access.redhat.com/openshift3_beta/mysql-55-rhel7
docker pull openshift/hello-openshift:v0.4.3
docker pull openshift/ruby-20-centos7
sed -i 's/DNS1=192.168.100.1/DNS1=192.168.100.5/' /etc/sysconfig/network-scripts/ifcfg-eth0
%end
%packages
@base
%end
" > ose_template_kickstart.ks
fi

if [[ -a ose_network.xml ]]; then
    echo " File ose_network.xml already exists!"
else
    echo " Creating ose_network.xml"
    echo "
<network>  
  <name>openshift</name>  
  <uuid>fc43091e-ce20-4af4-973b-99468b9f3d8a</uuid>  
  <forward mode='nat'>  
    <nat>  
      <port start='1024' end='65535'/>  
    </nat>  
  </forward>  
  <bridge name='virbr100' stp='on' delay='0'/>  
  <mac address='52:54:00:29:3d:d7'/>  
  <domain name='$DOMAIN'/>  
  <dns>
    <forwarder addr='8.8.8.8'/> 
    <host ip='192.168.100.2'>  
      <hostname>$MASTER_FQDN</hostname>  
    </host>  
    <host ip='192.168.100.3'>  
      <hostname>$NODE1_FQDN</hostname>  
    </host>  
    <host ip='192.168.100.4'>  
      <hostname>$NODE2_FQDN</hostname>  
    </host>  
    <host ip='192.168.100.5'>  
      <hostname>$WORKSTATION_FQDN</hostname>  
    </host>  
  </dns>  
  <ip address='192.168.100.1' netmask='255.255.255.0'>  
    <dhcp>  
      <range start='192.168.100.2' end='192.168.100.20'/>  
      <host mac='52:54:00:b3:3d:1a' name='$MASTER_FQDN' ip='192.168.100.2'/>  
      <host mac='52:54:00:b3:3d:1b' name='$NODE1_FQDN' ip='192.168.100.3'/>  
      <host mac='52:54:00:b3:3d:1c' name='$NODE2_FQDN' ip='192.168.100.4'/>  
      <host mac='52:54:00:b3:3d:1d' name='$WORKSTATION_FQDN' ip='192.168.100.5'/>  
    </dhcp>  
  </ip>  
</network>  
" > ose_network.xml
fi 

read -p "  Do you want to clear 192.168.100.0/24 addresses from your local $HOME/.ssh/known_hosts? [yes]: " CLEAR_IPS
CLEAR_IPS=${CLEAR_IPS:-yes}
if [[ $CLEAR_IPS == "Y" ]] || [[ $CLEAR_IPS == "y" ]] || [[ $CLEAR_IPS == "YES" ]] || [[ $CLEAR_IPS == "Yes" ]] || [[ $CLEAR_IPS == "yes" ]]; then
    sed "/192.168.100/d" -i $HOME/.ssh/known_hosts
fi

echo "Setting up KVM Network"
sudo virsh net-list | grep openshift > /dev/null ; RESULT=$? 
if [[ $RESULT -eq 0 ]]; then 
    echo " OpenShift Network already created skipping!" 
    sudo virsh net-list | grep openshift
else 
    sudo virsh net-define ose_network.xml
    sudo virsh net-start openshift
    echo " OpenShift Network created: "
    sudo virsh net-list | grep openshift
fi

echo "Opening $WEB_SERVER_PORT on firewall (using firewalld)"
DEFAULT_ZONE=$(sudo firewalld --get-default-zone)
sudo firewall-cmd --zone=$DEFAULT_ZONE --add-port $WEB_SERVER_PORT/tcp


read -p "  Do you want to setup / kickstart VM's [yes]: " VM_SETUP
VM_SETUP=${VM_SETUP:-yes}
if [[ $VM_SETUP == "Y" ]] || [[ $VM_SETUP == "y" ]] || [[ $VM_SETUP == "YES" ]] || [[ $VM_SETUP == "Yes" ]] || [[ $VM_SETUP == "yes" ]]; then
    echo "Starting SimpleWeb Server on $WEB_SERVER_PORT"
    python -m SimpleHTTPServer $WEB_SERVER_PORT & SIMPLE_WEB_PID=$!
    sleep 2
    
    echo "Creating OSE vm's"
    COUNT=2
    for system in master node1 node2 workstation; do 
        echo " Creating $system"
        sed -e "/192.168.100.${COUNT}/ s/^#*//" ose_template_kickstart.ks > ose_${system}_kickstart.ks
        sudo qemu-img create -f qcow2 /var/lib/libvirt/images/ose-${system}.qcow2 $DISK_SIZE
        sudo virt-install -v --name ose-${system} --disk path=/var/lib/libvirt/images/ose-${system}.qcow2,size=10 --ram $RAM_SIZE -w network=openshift,model=virtio --noautoconsole -l ${LIBVIRT_IMG} --os-variant="rhel7" --extra-args "ks=http://${WEB_SERVER_IP}:${WEB_SERVER_PORT}/ose_${system}_kickstart.ks"
        echo -n "  Kickstarting $system "
        echo "" 
        ((COUNT=COUNT+1))
    done
    echo " VM's will still be building! Use 'virt-manager' to check progress." 
    echo "  VM's will powerdown when complete! Please wait.... "
    
    sleep 90 
    
    echo "Killing SimpleWeb Server"
    kill -9 $SIMPLE_WEB_PID; SIMPLE_WEB_PID=""
    sleep 2
    echo ""
    
    STATE="UP"
    while [[ $STATE == "UP" ]]; do
       sudo virsh list --all  
       if [[ $(ps -ef | grep qemu | grep -Eo "\-name ose-(master|node1|node2|workstation)" | wc -l) -ne 0 ]]; then
          read -p "VM's are still running please wait, untill they are stoped! Press \"enter\" to check again": 
       else
          STATE="DOWN"
       fi
    done
    
    echo "Restarting Systems" 
    for system in master node1 node2 workstation; do
        sudo virsh start ose-$system
    done
    
    sleep 60
    echo "Waiting for systems to boot up ... " 
fi

read -p "  Do you want to run the post VM's setup [yes]: " POST_SETUP
POST_SETUP=${POST_SETUP:-yes}
if [[ $POST_SETUP == "Y" ]] || [[ $POST_SETUP == "y" ]] || [[ $POST_SETUP == "YES" ]] || [[ $POST_SETUP == "Yes" ]] || [[ $POST_SETUP == "yes" ]]; then
    USR_SETUP="NO"
    read -p "  Do you want to setup 'joe' and 'alice' users? [yes]: " USER_AUTH_SETUP
    USER_AUTH_SETUP=${USER_AUTH_SETUP:-yes}
    if [[ $USER_AUTH_SETUP == "Y" ]] || [[ $USER_AUTH_SETUP == "y" ]] || [[ $USER_AUTH_SETUP == "YES" ]] || [[ $USER_AUTH_SETUP == "Yes" ]] || [[ $USER_AUTH_SETUP == "yes" ]]; then
       USR_SETUP="YES"
    fi
    
    echo " Installing IPA on workstation! Because we need DNS, and it provides other cool things!" 
    echo "  Login to ose-workstation with: $ROOT_PASSWORD"
    
    ssh -t root@192.168.100.5 "sed -i '/nameserver/i \nameserver 192.168.100.1' /etc/resolv.conf; yum install -y ipa-server bind bind-dyndb-ldap ipa-admintools; ipa-server-install --realm=${DOMAIN^^} --domain=${DOMAIN} --ds-password=$IPA_PASSWORD --master-password=$IPA_PASSWORD --admin-password=$IPA_PASSWORD --hostname=$WORKSTATION_FQDN --no-ntp --idstart=80000 --setup-dns --forwarder=8.8.8.8 --zonemgr=admin@$DOMAIN --ssh-trust-dns -U; firewall-cmd --zone=public --add-port 80/tcp --add-port 443/tcp --add-port 389/tcp --add-port 636/tcp --add-port 88/tcp --add-port 464/tcp --add-port 53/tcp --add-port 88/udp --add-port 464/udp --add-port 53/udp --permanent; firewall-cmd --reload; echo \"    IPA Installed and Configured, sign in with $IPA_PASSWORD to complete DNS setup!\"; kinit admin; COUNT=2; for host in master node1 node2 workstation; do ipa dnsrecord-add example.com ose-\$host --a-rec 192.168.100.\$COUNT; ipa dnsrecord-add 100.168.192.in-addr.arpa. \$COUNT --ptr-rec=ose-\$host.example.com.; ((COUNT=COUNT+1)); done; ipa dnsrecord-add example.com *.cloudapps --a-rec 192.168.100.2; if [[ \"$USR_SETUP\" == \"YES\" ]]; then echo \"Creating user joe, enter password:\"; ipa user-add joe --first=Joe --last=Smith --manager=admin --email=jsmith@example.com --homedir=/home/joe --password; echo \"Creating user alice, enter password:\"; ipa user-add alice --first=Alice --last=Smith --manager=admin --email=asmith@example.com --homedir=/home/alice --password; ipa group-add developers --desc=\"Developers\"; ipa group-add-member developers --users=joe,alice ;fi; systemctl reboot"
    echo "  Rebooting Workstation!"
    
    NDS_SETUP="NO"
    read -p "  Do you want to setup ansible to install your nodes as well? [yes]: " NODES_SETUP
    NODES_SETUP=${NODES_SETUP:-yes}
    if [[ $NODES_SETUP == "Y" ]] || [[ $NODES_SETUP == "y" ]] || [[ $NODES_SETUP == "YES" ]] || [[ $NODES_SETUP == "Yes" ]] || [[ $NODES_SETUP == "yes" ]]; then
       NDS_SETUP="YES"
    fi
    
    echo " This will setup an ssh key on $MASTER_FQDN and install v3 training materials."
    if [[ $NDS_SETUP == "YES" ]]; then echo "  This will also pre-configure ansible's hosts file with your nodes"; fi 
    echo "  Login to ose-master with: $ROOT_PASSWORD"
    
    ssh -t root@192.168.100.2 "ssh-keygen; git clone $beta_training_repo; git clone $beta_installer_repo && cp -r /root/training/beta3/ansible/* /etc/ansible/; sed -e \"s/ose3-master.example.com/$MASTER_FQDN/g\" -i /etc/ansible/hosts; if [[ \"$NDS_SETUP\" == \"YES\" ]]; then sed -e \"s/\#ose3-node\[1\:2\].example.com/ose-node\[1\:2\].$DOMAIN/g\" -i /etc/ansible/hosts; fi; if [[ \"$USR_SETUP\" == \"YES\" ]]; then touch /etc/openshift-passwd; for developer in joe alice; do htpasswd -b /etc/openshift-passwd \$developer $USER_PASSWORD; done; fi;"
    
    read -p "  Do you want to put in local /etc/host entries for ose-master and ose-workstation? [yes]: " HOSTS_SETUP
    HOSTS_SETUP=${HOSTS_SETUP:-yes}
    if [[ $HOSTS_SETUP == "Y" ]] || [[ $HOSTS_SETUP == "y" ]] || [[ $HOSTS_SETUP == "YES" ]] || [[ $HOSTS_SETUP == "Yes" ]] || [[ $HOSTS_SETUP == "yes" ]]; then
       sudo sed -i "1i 192.168.100.2 $MASTER_FQDN" /etc/hosts
       sudo sed -i "1i 192.168.100.5 $WORKSTATION_FQDN" /etc/hosts
    fi
fi 

read -p "Clean up kickstart and libvirt network files [yes]: " CLEAN_UP
CLEAN_UP=${CLEAN_UP:-yes}
if [[ $CLEAN_UP == "Y" ]] || [[ $CLEAN_UP == "y" ]] || [[ $CLEAN_UP == "YES" ]] || [[ $CLEAN_UP == "Yes" ]] || [[ $CLEAN_UP == "yes" ]]; then
    echo "Cleaning Up Files"
    echo " Cleaning up ose_*_kickstart.ks"
    rm *.ks
    echo " Cleaning up ose_network.xml"
    rm *.xml
fi 
