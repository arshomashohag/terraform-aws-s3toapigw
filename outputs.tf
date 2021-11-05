# output "instance_id" {
#   description = "ID of the EC2 instance"
#   value       = aws_instance.app_server.id
# }

# output "instance_public_ip" {
#   description = "Public IP address of the EC2 instance"
#   value       = aws_instance.app_server.public_ip
# }

output "webhook_url" {
  description = " URL of API Gateway add data end point"

  value = "${aws_api_gateway_deployment.my_rest_api_deployment.invoke_url}${aws_api_gateway_stage.stage_dev.stage_name}${aws_api_gateway_resource.resource_add_data.path}"
}
 