# Generate private key for SSH
resource "tls_private_key" "ssh_key" {
    algorithm = "RSA"
    rsa_bits = 4096
}

# Store private key in local file
resource "local_file" "private_key" {
    content  = tls_private_key.ssh_key.private_key_pem
    filename = "${path.module}/id_rsa"
}

# Store public key in local file
resource "local_file" "public_key" {
    content  = tls_private_key.ssh_key.public_key_openssh
    filename = "${path.module}/id_rsa.pub"
}

