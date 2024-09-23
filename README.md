# Description
PoC to configure an ALB to have a NLB as a target. Two virtual machines are created as traffic end for HTTP. 

For interacting with the PoC, after deploying the AWS resources by typing `terraform apply --auto-approve`, simply retrieve the information from the terraform outputs. We list some examples in the following sections

## Perform a cURL to the public DNS of the ALB

```console
curl $(terraform output -raw alb_dns_name)
```

## Access the jumpbox

### Retrieve the VM keys

```console
terraform output -raw private_vm_key_pem > vm-keys.pem
chmod 400 vm-keys.pem
```

### Initiate a SSH session to jumpbox

```console
ssh -i vm-keys.pem ec2-user@$(terraform output -raw jumpbox_public_ip)
```

## Example 

```console
$ ssh -i vm-keys.pem ec2-user@$(terraform output -raw jumpbox_public_ip)
   ,     #_
   ~\_  ####_        Amazon Linux 2023
  ~~  \_#####\
  ~~     \###|
  ~~       \#/ ___   https://aws.amazon.com/linux/amazon-linux-2023
   ~~       V~' '->
    ~~~         /
      ~~._.   _/
         _/ _/
       _/m/'
Last login: Mon Sep 23 10:16:49 2024 from 212.12.112.142
[ec2-user@ip-10-0-0-68 ~]$ exit
logout
Connection to 35.158.123.215 closed.
$ curl $(terraform output -raw alb_dns_name)
<h1>Hello from NGINX on Terraform EC2 instance 1</h1>
$ curl $(terraform output -raw alb_dns_name)
<h1>Hello from NGINX on Terraform EC2 instance 2</h1>

```


