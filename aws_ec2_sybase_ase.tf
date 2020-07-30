#################
# instance profile
#################
resource "aws_iam_instance_profile" "db_sybase_ase" {
  name = "db_sybase_ase"
  role = aws_iam_role.db_sybase_ase.name
}

resource "aws_iam_role" "db_sybase_ase" {
  name = "db_sybase_ase"
  path = "/"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}
resource "aws_iam_role_policy" "db_sybase_ase" {
  name = "db_sybase_ase"
  role = aws_iam_role.db_sybase_ase.id

  policy = <<-EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:Get*"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
  EOF
}

#################
# sybase setup
#################
resource "random_password" "db_sybase_ase" {
  length           = 26
  special          = true
  override_special = "_%@"
}
variable "db_sybase_ase_port" {
  type    = number
  default = 2638
}
variable "db_sybase_ase_username" {
  type    = string
  default = "tech_user"
}

module "sg_sybase_ase" {
  source = "terraform-aws-modules/security-group/aws"

  name        = "sg_sybase_ase"
  description = "Security group for Sybase ASE - publicly open"
  vpc_id      = module.vpc.vpc_id


  egress_rules        = ["all-all"]
  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["ssh-tcp"]
  ingress_with_cidr_blocks = [
    {
      from_port   = var.db_sybase_ase_port
      to_port     = var.db_sybase_ase_port
      protocol    = "tcp"
      description = "Sybase ASE"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
}


data "template_cloudinit_config" "db_sybase_ase" {
  gzip          = true
  base64_encode = true

  # Main cloud-config configuration file.
  part {
    filename     = "sybase_setup.cfg"
    content_type = "text/cloud-config"
    content      = local.cloud_config
  }

  part {
    content_type = "text/x-shellscript"
    content      = local.userdata
  }

}



resource "aws_instance" "db_sybase_ase" {
  ami           = data.aws_ami.ubuntu_xenial.image_id
  instance_type = "t3.medium"
  key_name      = "peter-pair"
  monitoring    = true

  # takes about 15 min to fully install Sybase ASE
  user_data_base64 = data.template_cloudinit_config.db_sybase_ase.rendered

  root_block_device {
    volume_size = 20
  }

  iam_instance_profile = aws_iam_instance_profile.db_sybase_ase.name

  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true
  vpc_security_group_ids      = [module.sg_sybase_ase.this_security_group_id]

  lifecycle {
    ignore_changes = [
      ami,
    ]
  }
  tags = merge({ "Name" = "Sybase ASE" }, var.default_tags)
}
output "sybase_ip" {
  value = aws_instance.db_sybase_ase.public_ip
}

resource "sdm_resource" "db_sybase_ase" {
  sybase {
    name     = "aws_db_sybase_ase"
    hostname = aws_instance.db_sybase_ase.private_dns
    username = var.db_sybase_ase_username
    password = random_password.db_sybase_ase.result
    port     = var.db_sybase_ase_port

    tags = var.default_tags
  }
}
resource "sdm_role_grant" "db_sybase_ase" {
  role_id     = sdm_role.databases.id
  resource_id = sdm_resource.db_sybase_ase.id
}

#################
# Vars
#################
locals {
  cloud_config    = <<CLOUD
#cloud-config
# Creates sdm user
groups:
  - sybdba
users:
  - default
  - name: strongdm
    gecos: strongDM
    ssh_authorized_keys:
    - ${local.sdm_ca_public_key}
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin
  - name: sybuser
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin, sybdba
# Install unzip
packages:
- unzip
- libaio1
write_files:
- content: |
${local.response_file}
  path: /opt/sybase/response_file.txt
CLOUD
  userdata        = <<NOTES
#!/bin/bash -xv

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

sudo mkdir /opt/sybase
sudo chmod u+x /opt/sybase
sudo chown -R sybuser:sybdba /opt/sybase

cd /opt/sybase
/usr/local/bin/aws s3 cp s3://bucket-name/ASE_Suite.linuxamd64.tgz .
tar zxvf ASE_Suite.linuxamd64.tgz

sudo echo "kernel.shmmax = 300000000" >> /etc/sysctl.conf
sudo /sbin/sysctl -p

# if no response file create manually
# sudo ./setup.bin -i console -r strongdm_response_file.txt 
sudo ./setup.bin -f response_file.txt -i silent 

sudo chown -R sybuser:sybdba /opt/sap
NOTES
  response_file   = <<NOTES
    # Tue Jul 28 17:08:32 UTC 2020
    # Replay feature output
    # ---------------------
    # This file was built by the Replay feature of InstallAnywhere.
    # It contains variables that were set by Panels, Consoles or Custom Code.



    #Validate Response File
    #----------------------
    RUN_SILENT=true

    #Choose Install Folder
    #---------------------
    USER_INSTALL_DIR=/opt/sap

    #Install older version
    #---------------------

    #Choose Install Set
    #------------------
    CHOSEN_FEATURE_LIST=fase_srv,fopen_client,fdblib,fjconnect160,fdbisql,fqptune,fsysam_util,fase_cagent,fodbcl,fconn_python,fconn_perl,fconn_php,fscc_server,fasecmap
    CHOSEN_INSTALL_FEATURE_LIST=fase_srv,fopen_client,fdblib,fjconnect160,fdbisql,fqptune,fsysam_util,fase_cagent,fodbcl,fconn_python,fconn_perl,fconn_php,fscc_server,fasecmap
    CHOSEN_INSTALL_SET=Typical

    #Choose Product License Type
    #---------------------------
    SYBASE_PRODUCT_LICENSE_TYPE=express

    #Install
    #-------
    -fileOverwrite_/opt/sap/sybuninstall/ASESuite/uninstall.lax=Yes

    #Configure New Servers
    #---------------------
    SY_CONFIG_ASE_SERVER=true
    SY_CONFIG_HADR_SERVER=false
    SY_CONFIG_BS_SERVER=true
    SY_CONFIG_XP_SERVER=true
    SY_CONFIG_JS_SERVER=true
    SY_CONFIG_BALDR_OPTION=true
    SY_CONFIG_SM_SERVER=true
    SY_CONFIG_WS_SERVER=false
    SY_CONFIG_SCC_SERVER=true
    SY_CONFIG_TXT_SERVER=false

    #Configure Servers with Different User Account
    #---------------------------------------------
    SY_CFG_USER_ACCOUNT_CHANGE=no

    #User Configuration Data Directory
    #---------------------------------
    SY_CFG_USER_DATA_DIRECTORY=/opt/sap

    #Configure New SAP ASE
    #---------------------
    SY_CFG_ASE_SERVER_NAME=SDM_DB_ASE
    # SY_CFG_ASE_HOST_NAME=leaving_blank
    SY_CFG_ASE_PORT_NUMBER=${var.db_sybase_ase_port}
    SY_CFG_ASE_APPL_TYPE=MIXED
    SY_CFG_ASE_PAGESIZE=4k
    SY_CFG_ASE_PASSWORD=${random_password.db_sybase_ase.result}
    SY_CFG_ASE_MASTER_DEV_NAME=/opt/sap/data/master.dat
    SY_CFG_ASE_MASTER_DEV_SIZE=65
    SY_CFG_ASE_MASTER_DB_SIZE=26
    SY_CFG_ASE_SYBPROC_DEV_NAME=/opt/sap/data/sysprocs.dat
    SY_CFG_ASE_SYBPROC_DEV_SIZE=196
    SY_CFG_ASE_SYBPROC_DB_SIZE=196
    SY_CFG_ASE_SYBTEMP_DEV_NAME=/opt/sap/data/sybsysdb.dat
    SY_CFG_ASE_SYBTEMP_DEV_SIZE=6
    SY_CFG_ASE_SYBTEMP_DB_SIZE=6
    SY_CFG_ASE_ERROR_LOG=/opt/sap/ASE-16_0/install/SDM_DB_ASE.log
    CFG_REMOTE_AND_CONTROL_AGENT=false
    ENABLE_COCKPIT_MONITORING=true
    COCKPIT_TECH_USER=${var.db_sybase_ase_username}
    COCKPIT_TECH_USER_PASSWORD=${random_password.db_sybase_ase.result}
    SY_CFG_ASE_PCI_ENABLE=false
    SY_CFG_ASE_PCI_DEV_NAME=$NULL$
    SY_CFG_ASE_PCI_DEV_SIZE=$NULL$
    SY_CFG_ASE_PCI_DB_SIZE=$NULL$
    SY_CFG_ASE_TEMP_DEV_NAME=/opt/sap/data/tempdbdev.dat
    SY_CFG_ASE_TEMP_DEV_SIZE=100
    SY_CFG_ASE_TEMP_DB_SIZE=100
    SY_CFG_ASE_OPT_ENABLE=false
    SY_CFG_ASE_CPU_NUMBER=$NULL$
    SY_CFG_ASE_MEMORY=$NULL$
    SY_CFG_ASE_LANG=us_english
    SY_CFG_ASE_CHARSET=utf8
    SY_CFG_ASE_SORTORDER=altdict
    SY_CFG_ASE_SAMPLE_DB=true

    #Configure New Backup Server
    #---------------------------
    SY_CFG_BS_SERVER_NAME=SDM_DB_ASE_BS
    SY_CFG_BS_PORT_NUMBER=5001
    SY_CFG_BS_ERROR_LOG=/opt/sap/ASE-16_0/install/SDM_DB_ASE_BS.log
    SY_CFG_BS_ALLOW_HOSTS=

    #Configure New XP Server
    #-----------------------
    SY_CFG_XP_SERVER_NAME=SDM_DB_ASE_XP
    SY_CFG_XP_PORT_NUMBER=5002
    SY_CFG_XP_ERROR_LOG=/opt/sap/ASE-16_0/install/SDM_DB_ASE_XP.log

    #Configure New Job Scheduler
    #---------------------------
    SY_CFG_JS_SERVER_NAME=SDM_DB_ASE_JSAGENT
    SY_CFG_JS_PORT_NUMBER=4900
    SY_CFG_JS_MANAG_DEV_NAME=/opt/sap/data/sybmgmtdb.dat
    SY_CFG_JS_MANAG_DEV_SIZE=76
    SY_CFG_JS_MANAG_DB_SIZE=76

    #Configure Self Management
    #-------------------------
    SY_CFG_SM_USER_NAME=sa
    SY_CFG_SM_PASSWORD=${random_password.db_sybase_ase.result}

    #Configure Historical Monitoring Data Repository
    #-----------------------------------------------
    SY_CFG_BALDR_DATA_DEV_NAME=/opt/sap/data/saptoolsdata.dat
    SY_CFG_BALDR_DATA_DEV_SIZE=2048
    SY_CFG_BALDR_LOG_DEV_NAME=/opt/sap/data/saptoolslog.dat
    SY_CFG_BALDR_LOG_DEV_SIZE=256

    #Cockpit Host and Ports
    #----------------------
    CONFIG_SCC_HTTP_PORT=4282
    CONFIG_SCC_HTTPS_PORT=4283
    SCC_TDS_PORT_NUMBER=4998
    SCC_RMI_PORT_NUMBER=4992

    #Cockpit Users and Passwords
    #---------------------------
    CONFIG_SCC_CSI_SCCADMIN_USER=sccadmin
    CONFIG_SCC_CSI_SCCADMIN_PWD=${random_password.db_sybase_ase.result}
    CONFIG_SCC_CSI_UAFADMIN_USER=uafadmin
    CONFIG_SCC_CSI_UAFADMIN_PWD=${random_password.db_sybase_ase.result}
    CONFIG_SCC_REPOSITORY_PWD=${random_password.db_sybase_ase.result}

    #Agree to license
    #----------------
    AGREE_TO_SYBASE_LICENSE=true
    AGREE_TO_SAP_LICENSE=true
NOTES
  troubleshooting = <<NOTES
Troubleshooting Notes
=====================
Setup guide
http://infocenter.sybase.com/help/index.jsp?topic=/com.sybase.infocenter.dc35890.1600/doc/html/san1253301371043.html

walkthrough
https://medium.com/@techrandomthoughts/installing-sybase-ase-16-on-ubuntu-16-04-f810ba8bc877

helpful commands
=====
export LANG=en_US.UTF-8
source /opt/sap/SYBASE.sh
source SYBASE.env
cat $SYBASE/log/ASE_Suite.log # view installation logs
cat $SYBASE/ASE-16_0/init/logs/configASELog.log
$SYBASE/ASE-16_0/install/showserver # view servers 
startserver -f RUN_strongdmASE
NOTES
}
