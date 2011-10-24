# -*- encoding : utf-8 -*-
namespace :aws_deploy do
  
  desc "connect_to_s3"
  task :connect_to_s3 do
    s3_credentials = YAML::load(File.read(File.join(Rails.root, 'config/s3_backups.yml')))
    AWS::S3::Base.establish_connection!(
      :access_key_id     => s3_credentials['key'], 
      :secret_access_key => s3_credentials['secret']
    )
  end

  def aws_run(*cmd)
    system(*cmd)
    raise "Command #{cmd.inspect} failed!" unless $?.success?
  end

  def aws_confirm(message)
    aws_inform("#{message} [y/N] ")
    raise 'Abortado' unless STDIN.gets.chomp.downcase == 'y'
  end

  def aws_ask(question)
    print "\n ---> #{question}: "
    STDIN.gets.chomp
  end
  
  def aws_inform(message)
    print "\n ---> #{message}\n"
  end
  
  # -----------
  def aws_generate_launchconfig(branch)
    raise "CERTMAN_HOME not set" if ENV['CERTMAN_HOME'].blank?
    aws_inform "Gerando novo launchconfig usando o branch master..."
    aws_run "cd #{ENV['CERTMAN_HOME']} && . bin/activate && cd src && fab #{AwsDeploy.configuration.environment} deploy:#{File.dirname(Rails.root)},branch=#{branch}"
  end
  def aws_get_old_autoscaling_settings
    aws_inform "Buscando configurações atuais do auto-scaling-group..."
    output = `as-describe-auto-scaling-groups #{AwsDeploy.configuration.autoscaling_name} --show-xml`
    xml = Nokogiri::XML.parse(output)
    min_size = xml.at('AutoScalingGroups member > MinSize').text
    max_size = xml.at('AutoScalingGroups member > MaxSize').text
    desired_capacity = xml.at('AutoScalingGroups member > DesiredCapacity').text
    [min_size, max_size, desired_capacity]
  end
  def aws_deactivate_autoscaling(desired_capacity)
    aws_inform "'Desativando' auto-scaling..." # significa alterar desired-capacity para o número de instâncias atuais
    aws_run "as-update-auto-scaling-group #{AwsDeploy.configuration.autoscaling_name} --min-size #{desired_capacity} --max-size #{desired_capacity}"
  end
  def aws_query_all_instances_inservice_and_healthy_on_autoscaling
    aws_inform "Eis as instâncias registradas no auto-scaling-group neste momento:"
    aws_run "as-describe-auto-scaling-groups #{AwsDeploy.configuration.autoscaling_name}"
    aws_confirm "Todas as instâncias estão InService & Healthy?"
  end
  def aws_query_all_instances_inservice_on_load_balancer
    aws_inform "Eis as instâncias registradas no elastic-load-balancer neste momento:"
    aws_run "elb-describe-instance-health #{AwsDeploy.configuration.load_balancer_name}"
    aws_confirm "Todas as instâncias estão InService?"
  end
  def aws_set_maintenance_on_for_all_instances(credentials)
    aws_inform "Colocando todas as instâncias atuais em manutenção..."
    AwsDeploy::Maintenance.new(credentials, '/srv/fundos/src').on
  end
  def aws_shut_down_all_workers_on_all_instances(credentials)
    aws_inform "Desligando todos os workers de todas as instâncias..."
    AwsDeploy::Workers.new(credentials).stop
  end
  def aws_update_autoscalint_to_use_new_launchconfig(launchconfig)
    aws_inform "Atualizando auto-scaling-group para usar novo launchconfig..."
    aws_run "as-update-auto-scaling-group #{AwsDeploy.configuration.autoscaling_name} --launch-configuration #{launchconfig}"
  end
  def aws_clear_cache(credentials) # FIXME
    aws_inform "Limpando elastic-cache (memcached) ..."
    AwsDeploy::Cache.new(credentials, '/srv/fundos/src').clear
  end
  def aws_get_current_instances_ids
    output = `as-describe-auto-scaling-groups #{AwsDeploy.configuration.autoscaling_name} --show-xml`
    xml = Nokogiri::XML.parse(output)
    ids = xml.search("AutoScalingGroups Instances member InstanceId").map(&:text)
    raise "Nenhuma instância emcontrada no auto-scaling-group" if ids.empty?
    ids
  end
  def aws_kill_instance(id)
    aws_inform "Terminando instância de id #{id}..."
    aws_run "as-terminate-instance-in-auto-scaling-group #{id} --no-decrement-desired-capacity --force"
  end
  def aws_wait_new_instance_show_as_inservice_on_loadbalancer(launchconfig)
    new_instance_id = nil
    while new_instance_id.nil? do
      output = `as-describe-auto-scaling-groups #{AwsDeploy.configuration.autoscaling_name} --show-xml`
      xml = Nokogiri::XML.parse(output)
      if xml.search("AutoScalingGroups Instances member").select { |i| i.at("LaunchConfigurationName").text == launchconfig }.size > 0
        new_instance_id = xml.search("AutoScalingGroups Instances member").select { |i| i.at("LaunchConfigurationName").text == launchconfig }.first.at('InstanceId').text
      end
      aws_inform "Esperando 5 segundos para nova instância surgir..."
      sleep 5
    end
    aws_inform "Nova instância descoberta, id = #{new_instance_id}"
    new_instance_up = false
    until new_instance_up
      output = `elb-describe-instance-health #{AwsDeploy.configuration.load_balancer_name} --instances #{new_instance_id} --show-table`
      new_instance_up = true if output =~ /INSTANCE_ID  #{new_instance_id}  InService /
      aws_inform "Esperando 10 segundos para nova instância entrar InService no elastic-load-balancer..."
      sleep 10
    end
    aws_inform "Nova instância (#{new_instance_id}) está InService no elastic-load-balancer!"
  end
  def aws_reactivate_autoscaling(min_size, max_size, desired_capacity)
    aws_inform "'Re-ativando' auto-scaling..."
    aws_run "as-update-auto-scaling-group #{AwsDeploy.configuration.autoscaling_name} --min-size #{min_size} --max-size #{max_size} --desired-capacity #{desired_capacity}"
  end
  # -----------
  
  desc "Deploy to sandbox at Amazon"
  task :sandbox, :speed do |t, args|
    
    AWS_CONFIG ||= YAML::load(File.read('config/aws_deploy.yml'))["sandbox"]

    AwsDeploy.configure do |config|
      config.environment = AWS_CONFIG['environment']
      config.autoscaling_name = AWS_CONFIG['autoscaling_name']
      config.load_balancer_name = AWS_CONFIG['load_balancer_name']
    end

    args.with_defaults(:speed => 'normal')
    credentials = AwsDeploy::Credentials.new

    aws_generate_launchconfig('master')
    
    launchconfig = aws_ask('Digite o nome do launchconfig gerado (e dê enter)')
    
    old_autoscaling_min_size, old_autoscaling_max_size, old_autoscaling_desired_capacity = aws_get_old_autoscaling_settings

    begin
      aws_deactivate_autoscaling(old_autoscaling_desired_capacity)
        
      # verificar que não há nenhuma instância pending (subindo) no auto-scaling-group
      aws_query_all_instances_inservice_and_healthy_on_autoscaling
    
      # verificar que não há nenhuma instância fora de serviço no elastic-load-balancer
      aws_query_all_instances_inservice_on_load_balancer
      
      if args.speed != 'fast'
        aws_set_maintenance_on_for_all_instances(credentials)
      end

      aws_shut_down_all_workers_on_all_instances(credentials)
    
      # restaurar último backup de produção para sandbox
      # TODO
    
      # anonimizar banco do sandbox
      # TODO
    
      # configurar auto-scaling-group para usar novo launchconfig
      aws_update_autoscalint_to_use_new_launchconfig(launchconfig)
    
      aws_clear_cache(credentials) # FIXME
    
      # pegar ids de todas as instâncias atuais no auto-scaling-group
      instance_ids = aws_get_current_instances_ids
    
      # matar primaira máquina existente
      instance_id = instance_ids.pop
      aws_kill_instance(instance_id)
      
      # esperar uma nova máquina levantar e estar InService no elastic-load-balancer
      aws_wait_new_instance_show_as_inservice_on_loadbalancer(launchconfig)

      # matar todas as outras instâncias
      unless instance_ids.empty?
        aws_inform "Terminando todas as outras instâncias..."
        until instance_ids.empty?
          instance_id = instance_ids.pop
          aws_kill_instance(instance_id)
        end
      end
    ensure
      # reativar auto-scaling
      # significa voltar para desired-capacity default
      aws_reactivate_autoscaling(old_autoscaling_min_size, old_autoscaling_max_size, old_autoscaling_desired_capacity)
    end
    aws_inform "Deploy para sandbox finalizado!"
  end

  desc "Deploy to production at Amazon"
  task :production, :speed do |t, args|
    
    AWS_CONFIG ||= YAML::load(File.read('config/aws_deploy.yml'))["sandbox"]

    AwsDeploy.configure do |config|
      config.environment = AWS_CONFIG['environment']
      config.autoscaling_name = AWS_CONFIG['autoscaling_name']
      config.load_balancer_name = AWS_CONFIG['load_balancer_name']
    end
    
    args.with_defaults(:speed => 'normal')

    credentials = AwsDeploy::Credentials.new

    aws_generate_launchconfig('deploy')
    
    launchconfig = aws_ask('Digite o nome do launchconfig gerado (e dê enter)')
    
    old_autoscaling_min_size, old_autoscaling_max_size, old_autoscaling_desired_capacity = aws_get_old_autoscaling_settings

    begin
      aws_deactivate_autoscaling(old_autoscaling_desired_capacity)
        
      # verificar que não há nenhuma instância pending (subindo) no auto-scaling-group
      aws_query_all_instances_inservice_and_healthy_on_autoscaling
    
      # verificar que não há nenhuma instância fora de serviço no elastic-load-balancer
      aws_query_all_instances_inservice_on_load_balancer

      if args.speed != 'fast'
        aws_set_maintenance_on_for_all_instances(credentials)
      end

      aws_shut_down_all_workers_on_all_instances(credentials)
    
      # fazer backup do banco de dados e mandar para s3
      # TODO
    
      # configurar auto-scaling-group para usar novo launchconfig
      aws_update_autoscalint_to_use_new_launchconfig(launchconfig)
    
      aws_clear_cache(credentials) # FIXME
    
      # pegar ids de todas as instâncias atuais no auto-scaling-group
      instance_ids = aws_get_current_instances_ids
    
      # matar primaira máquina existente
      instance_id = instance_ids.pop
      aws_kill_instance(instance_id)
      
      # esperar uma nova máquina levantar e estar InService no elastic-load-balancer
      aws_wait_new_instance_show_as_inservice_on_loadbalancer(launchconfig)

      # matar todas as outras instâncias
      unless instance_ids.empty?
        aws_inform "Terminando todas as outras instâncias..."
        until instance_ids.empty?
          instance_id = instance_ids.pop
          aws_kill_instance(instance_id)
        end
      end
    ensure
      # reativar auto-scaling
      # significa voltar para desired-capacity default
      aws_reactivate_autoscaling(old_autoscaling_min_size, old_autoscaling_max_size, old_autoscaling_desired_capacity)
    end
    aws_inform "Deploy para production finalizado!"
  end
  
end
