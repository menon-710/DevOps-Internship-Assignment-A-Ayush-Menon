###############################################################################
# Outputs – printed after terraform apply
# These feed directly into the Ansible inventory
###############################################################################

output "gateway_public_ip" {
  description = "Public IP of the nginx gateway – this is your API endpoint"
  value       = aws_eip.gateway.public_ip
}

output "gateway_private_ip" {
  description = "Private IP of the gateway"
  value       = aws_instance.gateway.private_ip
}

output "engine_private_ip" {
  description = "Private IP of the iii engine"
  value       = aws_instance.engine.private_ip
}

output "caller_worker_private_ip" {
  description = "Private IP of the caller (TypeScript) worker"
  value       = aws_instance.caller_worker.private_ip
}

output "inference_worker_private_ip" {
  description = "Private IP of the inference (Python) worker"
  value       = aws_instance.inference_worker.private_ip
}

output "api_endpoint" {
  description = "The public JSON API endpoint"
  value       = "http://${aws_eip.gateway.public_ip}/v1/chat/completions"
}

output "curl_example" {
  description = "Ready-to-use curl command for testing"
  value       = <<-EOT
    curl -X POST http://${aws_eip.gateway.public_ip}/v1/chat/completions \
      -H 'Content-Type: application/json' \
      -d '{"messages": [{"role": "user", "content": "Hello, what are you?"}]}'
  EOT
}

output "ssh_gateway" {
  description = "SSH into the gateway (bastion)"
  value       = "ssh -i ~/.ssh/devops-intern ubuntu@${aws_eip.gateway.public_ip}"
}

output "ssh_engine_via_gateway" {
  description = "SSH into the engine via gateway"
  value       = "ssh -i ~/.ssh/devops-intern -J ubuntu@${aws_eip.gateway.public_ip} ubuntu@${aws_instance.engine.private_ip}"
}
