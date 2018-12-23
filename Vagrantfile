# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure(2) do |config|
  # Box
  config.vm.box = "ubuntu/xenial64"

  # Box Configurations - more power!
  config.vm.provider :virtualbox do |v|
    v.customize ["modifyvm", :id, "--memory", 1024]
    v.customize ["modifyvm", :id, "--cpus", 1]
    v.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    v.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
  end

  # SSH Agent Forwarding
  config.ssh.forward_agent = true

  # Hostnames
  config.vm.hostname = "nextcloud"

  # Private Network
  config.vm.network :private_network, ip: "192.168.50.12"

  # Share Folders
  config.vm.synced_folder "../user_sql", "/var/www/nextcloud/apps/user_sql", owner: "www-data", group: "www-data"

  # Provisioning
  config.vm.provision "provision", type: "shell", :path => "provision.sh", args: [
    "nextcloud", # MySQL nextcloud password
    "root", # MySQL root password
    "user_sql", # Server name
    "admin", # Admin username
    "admin", # Admin password
    "master", # Nextcloud version
  ]

  config.vm.provision "no-tty-fix", type: "shell", inline: "sed -i '/tty/!s/mesg n/tty -s \\&\\& mesg n/' /root/.profile"
end
