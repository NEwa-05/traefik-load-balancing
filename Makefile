LOCAL_BIN=~/.local/bin/
PACKER_VERSION=1.8.2
TERRAFORM_PLUGIN_DIR=~/.terraform.d/plugins
TERRAFORM_VERSION=1.2.3
TERRAFORM_LIBVIRT_VERSION=0.6.14
TERRAFORM_ANSIBLE_VERSION=2.5.0
ANSIBLE_VERSION=2.9.6
LIBVIRT_HYPERVISOR_URI="qemu:///system"
LIBVIRT_TEMPLATE_POOL="templates"
LIBVIRT_IMAGES_POOL="images"
LIBVIRT_IMAGE_NAME="debian11-traefik.qcow2"
ROOT_PASSWORD="traefik"
$(eval SSH_IDENTITY=$(shell find ~/.ssh/ -name 'id_*' -not -name '*.pub' | head -n 1))
CLUSTER=1
TRAEFIKEE_LICENSE="N/A"
POOL_TEMPLATE_STATUS := $(shell virsh -c $(LIBVIRT_HYPERVISOR_URI) pool-info $(LIBVIRT_TEMPLATE_POOL) 1>&2 2> /dev/null; echo $$?)
POOL_IMAGE_STATUS := $(shell virsh -c $(LIBVIRT_HYPERVISOR_URI) pool-info $(LIBVIRT_IMAGE_POOL) 1>&2 2> /dev/null; echo $$?)

all:

myenv: create-env install-packer install-terraform install-terraform-plugins install-ansible

create-env:
	test -d $(LOCAL_BIN)|| mkdir -p $(LOCAL_BIN)
	echo ${PATH} | grep $(LOCAL_BIN) || (echo 'export PATH=$$PATH:~/.local/bin/' >> ~/.bashrc; . ~/.bashrc)

install-packer:
	test -f $(LOCAL_BIN)packer || \
	(curl https://releases.hashicorp.com/packer/$(PACKER_VERSION)/packer_$(PACKER_VERSION)_linux_amd64.zip -o /tmp/packer_$(PACKER_VERSION)_linux_amd64.zip; \
	unzip /tmp/packer_$(PACKER_VERSION)_linux_amd64.zip -d $(LOCAL_BIN); \
	rm -f /tmp/packer_$(PACKER_VERSION)_linux_amd64.zip); \
	chmod +x $(LOCAL_BIN)packer

install-terraform:
	test -f $(LOCAL_BIN)terraform || \
	(curl -q https://releases.hashicorp.com/terraform/$(TERRAFORM_VERSION)/terraform_$(TERRAFORM_VERSION)_linux_amd64.zip -o /tmp/terraform_$(TERRAFORM_VERSION)_linux_amd64.zip; \
	unzip /tmp/terraform_$(TERRAFORM_VERSION)_linux_amd64.zip -d $(LOCAL_BIN); \
	rm -f /tmp/terraform_$(TERRAFORM_VERSION)_linux_amd64.zip); \
	chmod +x $(LOCAL_BIN)terraform

install-ansible:
	pip3 freeze | grep ansible==$(ANSIBLE_VERSION) || pip3 install ansible kubernetes openshift

install-terraform-plugins:
	test -d $(TERRAFORM_PLUGIN_DIR)/github.com/dmacvicar/libvirt/$(TERRAFORM_LIBVIRT_VERSION)/linux_amd64/ || mkdir -p $(TERRAFORM_PLUGIN_DIR)/github.com/dmacvicar/libvirt/$(TERRAFORM_LIBVIRT_VERSION)/linux_amd64/; \
	test -f $(TERRAFORM_PLUGIN_DIR)/github.com/dmacvicar/libvirt/$(TERRAFORM_LIBVIRT_VERSION)/linux_amd64/terraform-provider-libvirt || \
	(curl -L https://github.com/dmacvicar/terraform-provider-libvirt/releases/download/v$(TERRAFORM_LIBVIRT_VERSION)/terraform-provider-libvirt_$(TERRAFORM_LIBVIRT_VERSION)_linux_amd64.zip -o /tmp/terraform-provider-libvirt-$(TERRAFORM_LIBVIRT_VERSION).zip && mkdir -p $(TERRAFORM_PLUGIN_DIR)/github.com/dmacvicar/libvirt/0.6.14/linux_amd64 && unzip -j /tmp/terraform-provider-libvirt-$(TERRAFORM_LIBVIRT_VERSION).zip terraform-provider-libvirt_v$(TERRAFORM_LIBVIRT_VERSION) -d $(TERRAFORM_PLUGIN_DIR)/github.com/dmacvicar/libvirt/0.6.14/linux_amd64/ && mv $(TERRAFORM_PLUGIN_DIR)/github.com/dmacvicar/libvirt/0.6.14/linux_amd64/terraform-provider-libvirt_v$(TERRAFORM_LIBVIRT_VERSION) $(TERRAFORM_PLUGIN_DIR)/github.com/dmacvicar/libvirt/0.6.14/linux_amd64/terraform-provider-libvirt && rm -f /tmp/terraform-provider-libvirt-$(TERRAFORM_LIBVIRT_VERSION).zip); \
	test -f $(TERRAFORM_PLUGIN_DIR)/terraform-provisioner-ansible || \
	(curl -L https://github.com/radekg/terraform-provisioner-ansible/releases/download/v$(TERRAFORM_ANSIBLE_VERSION)/terraform-provisioner-ansible-linux-amd64_v$(TERRAFORM_ANSIBLE_VERSION) -o $(TERRAFORM_PLUGIN_DIR)/terraform-provisioner-ansible && chmod +x $(TERRAFORM_PLUGIN_DIR)/terraform-provisioner-ansible)

image: build-image upload-image

build-image:
	rm -rf  packer/output
	$(eval CRYPTED_PASSWORD = $$(shell openssl passwd -6 "$(ROOT_PASSWORD)"))
	sed -i -r 's@^(d-i passwd\/root-password-crypted password).*@\1 $(CRYPTED_PASSWORD)@g' packer/preseed/debian11.txt
	cd packer && ROOT_PASSWORD=$(ROOT_PASSWORD) SSH_PUB_KEY="$(shell cat $(SSH_IDENTITY).pub)" packer build base.json

upload-image:
        ifneq ($(POOL_TEMPLATE_STATUS), 0)
            virsh -c $(LIBVIRT_HYPERVISOR_URI) pool-define-as $(LIBVIRT_TEMPLATE_POOL) dir - - - - "/tmp/$(LIBVIRT_TEMPLATE_POOL)" && virsh -c $(LIBVIRT_HYPERVISOR_URI) pool-build $(LIBVIRT_TEMPLATE_POOL) && virsh -c $(LIBVIRT_HYPERVISOR_URI) pool-start $(LIBVIRT_TEMPLATE_POOL) && virsh -c $(LIBVIRT_HYPERVISOR_URI) pool-autostart $(LIBVIRT_TEMPLATE_POOL)
        endif
        ifneq ($(POOL_IMAGE_STATUS), 0)
            virsh -c $(LIBVIRT_HYPERVISOR_URI) pool-define-as $(LIBVIRT_IMAGES_POOL) dir - - - - "/tmp/$(LIBVIRT_IMAGES_POOL)" && virsh -c $(LIBVIRT_HYPERVISOR_URI) pool-build $(LIBVIRT_IMAGES_POOL) && virsh pool-start $(LIBVIRT_IMAGES_POOL) && virsh -c $(LIBVIRT_HYPERVISOR_URI) pool-autostart $(LIBVIRT_IMAGES_POOL)
        endif
        $(eval  size = $(shell stat -Lc%s packer/output/debian11))
        - virsh -c $(LIBVIRT_HYPERVISOR_URI) vol-list $(LIBVIRT_TEMPLATE_POOL) | grep $(LIBVIRT_IMAGE_NAME) && virsh -c $(LIBVIRT_HYPERVISOR_URI) vol-delete --pool $(LIBVIRT_TEMPLATE_POOL) $(LIBVIRT_IMAGE_NAME)
        virsh -c $(LIBVIRT_HYPERVISOR_URI) vol-create-as $(LIBVIRT_TEMPLATE_POOL) $(LIBVIRT_IMAGE_NAME) $(size) --format qcow2 && \
        virsh -c $(LIBVIRT_HYPERVISOR_URI) vol-upload --pool $(LIBVIRT_TEMPLATE_POOL) $(LIBVIRT_IMAGE_NAME)  packer/output/debian11
import-kube-nodes:
	[ $(CLUSTER) -eq 3 ] && { \
	cd terraform ; \
	[ -f cluster2.tfstate ] && ! [ -f cluster3.tfstate ] && { \
	cp cluster2.tfstate cluster2.tfstate.copy; \
	for i in 3 4 5 ; do \
		terraform state mv -state=cluster2.tfstate.copy -state-out=cluster3.tfstate libvirt_domain.vm[$$i] libvirt_domain.vm[$$((i+1))]; \
	done; \
	rm -f cluster2.tfstate.copy ; \
	} \
	} || echo "not importing"

create-vms: import-kube-nodes
	cd terraform && terraform init && terraform apply -auto-approve -var "libvirt_uri=$(LIBVIRT_HYPERVISOR_URI)" -var "ssh_key=$(SSH_IDENTITY)" -var-file="cluster$(CLUSTER).tfvars" -state="cluster$(CLUSTER).tfstate"

run-playbook: create-vms
	cd ansible && ansible-playbook -u root -i traefik_inventory -e "traefikee_license_key=$(TRAEFIKEE_LICENSE_KEY)" site.yml
