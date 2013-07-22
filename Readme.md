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

Exemplo de uso:
---------------

    Sandbox:
    rake aws_deploy:sandbox generate_launchconfig=on
    generate_launchconfig=on vai gerar um launch config novo para fazer o deploy (default=off).

    Production:
    rake aws_deploy:production [generate_launchconfig=on]
    generate_launchconfig=on vai gerar um launch config novo para fazer o deploy (default=off).

