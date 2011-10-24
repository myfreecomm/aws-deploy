Exemplo de arquivo 'config/aws_deploy.yml'

production:
  environment: "production"
  autoscaling_name: "fundos-production"
  load_balancer_name: "Fundos-SSL"

sandbox:
  environment: "sandbox"
  autoscaling_name: "fundos-sandbox"
  load_balancer_name: "Fundos-Sandbox"