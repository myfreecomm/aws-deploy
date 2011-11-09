Exemplo de arquivo 'config/aws_deploy.yml'

    production:
      environment: "production"
      autoscaling_name: "fundos-production"
      load_balancer_name: "Fundos-SSL"
      path: "/srv/fundos/src"
      rds_instance_identifier: "fundos"

    sandbox:
      environment: "sandbox"
      autoscaling_name: "fundos-sandbox"
      load_balancer_name: "Fundos-Sandbox"
      path: "/srv/fundos/src"
      rds_instance_identifier: "fundos"
