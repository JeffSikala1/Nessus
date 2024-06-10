output "ssh_user" {
  value = "Nessus"
}

output "ssh_private_key" {
  value = local_file.private_key.filename
}

output "ssh_public_key" {
  value = local_file.public_key.content
}
