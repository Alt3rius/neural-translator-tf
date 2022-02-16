# Set the variable value in *.tfvars file or using -var="civo_token=..." CLI flag
variable "do_token" {}

# Specify required provider as maintained by civo
terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}


# Configure the Civo Provider
provider "digitalocean" {
  token = var.do_token
}

# Query xsmall instance size
data "digitalocean_sizes" "medium" {
  filter {
    key    = "vcpus"
    values = [2]
  }

  filter {
    key    = "memory"
    values = [4096]
  }

  filter {
    key    = "regions"
    values = ["fra1"]
  }

  sort {
    key       = "price_monthly"
    direction = "asc"
  }

}

data "digitalocean_sizes" "small" {
  filter {
    key    = "vcpus"
    values = [1]
  }

  filter {
    key    = "memory"
    values = [2048]
  }

  filter {
    key    = "regions"
    values = ["fra1"]
  }

  sort {
    key       = "price_monthly"
    direction = "asc"
  }

}


resource "digitalocean_ssh_key" "ed25519-key" {
  name       = "ed25519-key"
  public_key = file("~/.ssh/id_ed25519.pub")
}






resource "digitalocean_droplet" "master-0" {
  name     = "neural-translator-k3s-master0"
  tags     = ["master"]
  size     = element(data.digitalocean_sizes.small.sizes, 0).slug
  image    = "ubuntu-20-04-x64"
  ssh_keys = [digitalocean_ssh_key.ed25519-key.id]
  region   = "fra1"

}

resource "digitalocean_droplet" "master-1" {
  name     = "neural-translator-k3s-master1"
  tags     = ["master"]
  size     = element(data.digitalocean_sizes.small.sizes, 0).slug
  image    = "ubuntu-20-04-x64"
  ssh_keys = [digitalocean_ssh_key.ed25519-key.id]
  region   = "fra1"

}

resource "digitalocean_droplet" "master-2" {
  name     = "neural-translator-k3s-master2"
  tags     = ["master"]
  size     = element(data.digitalocean_sizes.small.sizes, 0).slug
  image    = "ubuntu-20-04-x64"
  ssh_keys = [digitalocean_ssh_key.ed25519-key.id]
  region   = "fra1"

}

resource "digitalocean_droplet" "worker-0" {
  name     = "neural-translator-k3s-worker0"
  tags     = ["worker"]
  size     = element(data.digitalocean_sizes.medium.sizes, 0).slug
  image    = "ubuntu-20-04-x64"
  ssh_keys = [digitalocean_ssh_key.ed25519-key.id]
  region   = "fra1"

}

resource "digitalocean_droplet" "worker-1" {
  name     = "neural-translator-k3s-worker1"
  tags     = ["worker"]
  size     = element(data.digitalocean_sizes.medium.sizes, 0).slug
  image    = "ubuntu-20-04-x64"
  ssh_keys = [digitalocean_ssh_key.ed25519-key.id]
  region   = "fra1"

}

resource "digitalocean_droplet" "worker-2" {
  name     = "neural-translator-k3s-worker2"
  tags     = ["worker"]
  size     = element(data.digitalocean_sizes.medium.sizes, 0).slug
  image    = "ubuntu-20-04-x64"
  ssh_keys = [digitalocean_ssh_key.ed25519-key.id]
  region   = "fra1"
  

}

resource "digitalocean_droplet" "loadbalancer" {
  name     = "neural-translator-loadbalancer"
  tags     = ["loadbalancer"]
  size     = element(data.digitalocean_sizes.small.sizes, 0).slug
  image    = "ubuntu-20-04-x64"
  ssh_keys = [digitalocean_ssh_key.ed25519-key.id]
  region   = "fra1"

  connection {
    type  = "ssh"
    user  = "root"
    host  = self.ipv4_address
    agent = "true"
  }



  provisioner "remote-exec" {
    inline = [
      "sleep 60",
      "sudo apt-get -y update",
      "sudo apt-get -y install nginx",
    ]
  }

  provisioner "file" {
    content     = templatefile("terraform-templates/nginx.tftpl", { master0 = digitalocean_droplet.master-0.ipv4_address, master1 = digitalocean_droplet.master-1.ipv4_address, master2 = digitalocean_droplet.master-2.ipv4_address })
    destination = "/tmp/nginx.conf"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mv /tmp/nginx.conf /etc/nginx/nginx.conf",
      "sudo systemctl restart nginx",
    ]
  }
}





resource "null_resource" "provision_master0" {
  provisioner "local-exec" {
    command = "k3sup install --user root --ip ${digitalocean_droplet.master-0.ipv4_address} --local-path $HOME/kubeconfig --context neural-translator --cluster --tls-san ${digitalocean_droplet.loadbalancer.ipv4_address} --k3s-extra-args '--disable traefik --flannel-backend=none --disable-network-policy --node-taint node-role.kubernetes.io/master=true:NoSchedule' --k3s-version=v1.21.8+k3s1"
  }
  depends_on = [
    digitalocean_droplet.loadbalancer,
    # digitalocean_firewall.kubernetes-firewall
  ]
}

resource "null_resource" "provision_master1" {
  provisioner "local-exec" {
    command = "k3sup join --user root --ip ${digitalocean_droplet.master-1.ipv4_address} --server --server-user root --server-ip ${digitalocean_droplet.master-0.ipv4_address} --k3s-extra-args '--disable traefik --flannel-backend=none --disable-network-policy --node-taint node-role.kubernetes.io/master=true:NoSchedule' --k3s-version=v1.21.8+k3s1"
  }
  depends_on = [
    digitalocean_droplet.loadbalancer,
    null_resource.provision_master0
  ]
}

resource "null_resource" "provision_master2" {
  provisioner "local-exec" {
    command = "k3sup join --user root --ip ${digitalocean_droplet.master-2.ipv4_address} --server --server-user root --server-ip ${digitalocean_droplet.master-0.ipv4_address} --k3s-extra-args '--disable traefik --flannel-backend=none --disable-network-policy --node-taint node-role.kubernetes.io/master=true:NoSchedule' --k3s-version=v1.21.8+k3s1"
  }
  depends_on = [
    digitalocean_droplet.loadbalancer,
    null_resource.provision_master0,
    null_resource.provision_master1
  ]
}

resource "null_resource" "set_kubeconfig_context" {
  provisioner "local-exec" {
    command = "kubectl config use-context neural-translator"
  }
  depends_on = [
    digitalocean_droplet.loadbalancer,
    null_resource.provision_master0,
    null_resource.provision_master1,
    null_resource.provision_master2
  ]
}

resource "null_resource" "add_calico_cni" {
  provisioner "local-exec" {
    command = "kubectl apply -f calico/calico.yml"
  }
  depends_on = [
    null_resource.set_kubeconfig_context
  ]
}


resource "null_resource" "provision_worker0" {
  provisioner "local-exec" {
    command = "k3sup join --user root --ip ${digitalocean_droplet.worker-0.ipv4_address} --ssh-key ~/.ssh/id_ed25519 --server-user root --server-ip ${digitalocean_droplet.loadbalancer.ipv4_address} --server-ssh-port 2222 --k3s-version=v1.21.8+k3s1"
  }
  depends_on = [
    digitalocean_droplet.loadbalancer,
    null_resource.provision_master0,
    null_resource.provision_master1,
    null_resource.provision_master2,
    null_resource.add_calico_cni
  ]
}

resource "null_resource" "provision_worker1" {
  provisioner "local-exec" {
    command = "k3sup join --user root --ip ${digitalocean_droplet.worker-1.ipv4_address} --ssh-key ~/.ssh/id_ed25519 --server-user root --server-ip ${digitalocean_droplet.loadbalancer.ipv4_address} --server-ssh-port 2222 --k3s-version=v1.21.8+k3s1"
  }
  depends_on = [
    digitalocean_droplet.loadbalancer,
    null_resource.provision_master0,
    null_resource.provision_master1,
    null_resource.provision_master2,
    null_resource.add_calico_cni
  ]
}

resource "null_resource" "provision_worker2" {
  provisioner "local-exec" {
    command = "k3sup join --user root --ip ${digitalocean_droplet.worker-2.ipv4_address} --ssh-key ~/.ssh/id_ed25519 --server-user root --server-ip ${digitalocean_droplet.loadbalancer.ipv4_address} --server-ssh-port 2222 --k3s-version=v1.21.8+k3s1"
  }
  depends_on = [
    digitalocean_droplet.loadbalancer,
    null_resource.provision_master0,
    null_resource.provision_master1,
    null_resource.provision_master2,
    null_resource.add_calico_cni
  ]
}


resource "digitalocean_domain" "alteraipl" {
  name = "alterai.pl"
}

resource "digitalocean_record" "argocd_alteraipl0" {
  domain     = digitalocean_domain.alteraipl.name
  type       = "A"
  name       = "argocd"
  value      = digitalocean_droplet.worker-0.ipv4_address
  ttl        = 600
  depends_on = [digitalocean_domain.alteraipl]
}

resource "digitalocean_record" "argocd_alteraipl1" {
  domain     = digitalocean_domain.alteraipl.name
  type       = "A"
  name       = "argocd"
  value      = digitalocean_droplet.worker-1.ipv4_address
  ttl        = 600
  depends_on = [digitalocean_domain.alteraipl]
}

resource "digitalocean_record" "argocd_alteraipl2" {
  domain     = digitalocean_domain.alteraipl.name
  type       = "A"
  name       = "argocd"
  value      = digitalocean_droplet.worker-2.ipv4_address
  ttl        = 600
  depends_on = [digitalocean_domain.alteraipl]
}

resource "digitalocean_record" "root_alteraipl0" {
  domain     = digitalocean_domain.alteraipl.name
  type       = "A"
  name       = "@"
  value      = digitalocean_droplet.worker-0.ipv4_address
  ttl        = 600
  depends_on = [digitalocean_domain.alteraipl]
}

resource "digitalocean_record" "root_alteraipl1" {
  domain     = digitalocean_domain.alteraipl.name
  type       = "A"
  name       = "@"
  value      = digitalocean_droplet.worker-1.ipv4_address
  ttl        = 600
  depends_on = [digitalocean_domain.alteraipl]
}

resource "digitalocean_record" "root_alteraipl2" {
  domain     = digitalocean_domain.alteraipl.name
  type       = "A"
  name       = "@"
  value      = digitalocean_droplet.worker-2.ipv4_address
  ttl        = 600
  depends_on = [digitalocean_domain.alteraipl]
}


resource "null_resource" "install_argocd" {
  provisioner "local-exec" {
    command = "kustomize build github.com/Alt3rius/neural-translator/argocd/overlays/private-repo | kubectl apply -f -"
  }
  depends_on = [
    null_resource.provision_worker0,
    null_resource.provision_worker1,
    null_resource.provision_worker2,
    null_resource.add_calico_cni
    # digitalocean_firewall.kubernetes_firewall
  ]
}

resource "time_sleep" "wait_3_min"{
  create_duration = "3m"
  depends_on = [
    null_resource.install_argocd
  ]
}

resource "null_resource" "apply_main_application" {
  provisioner "local-exec" {
    command = "kubectl apply -f https://raw.githubusercontent.com/Alt3rius/neural-translator/main/neural-translator.yml"
  }
  depends_on = [
    null_resource.install_argocd,
    time_sleep.wait_3_min
  ]
}





