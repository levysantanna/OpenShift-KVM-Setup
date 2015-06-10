# OpenShift-KVM-Setup
Creates a KVM enviornment that can be used as a basline for OpenShift

To use the script you should simply need to run: 

```
# bash ose_kvm_setup.sh RHN_USERNAME RHN_PASSWORD 
```

The only pre-req for the scrpt is that you have a RHEL 7.1 iso saved to the LIBVIRT_IMG (/var/lib/libvirt/images/RHEL-7.1_OSE.iso) file name. 

- The script will check that you have this and hald in a loop with instructions on where to get it. 
