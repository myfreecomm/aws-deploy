# -*- encoding : utf-8 -*-
require 'nokogiri'

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
    puts *cmd
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
  def get_current_branch
    `git branch`.match(/\*\s([\w\/]+)/)[1]
  end
  def aws_check_current_branch(branch_to_deploy)
    if get_current_branch != branch_to_deploy
      raise %{O deploy deve ser feito a partir do branch "#{branch_to_deploy}".}
    end
  end

  def aws_check_new_migrations(credentials, app_path)
    aws_inform "Verificando se o deploy possui novas migrations..."

    instance = AwsDeploy::Instance.new(credentials).find_all_in_service.first
    unless instance.nil?
      remote_migrations_count = `ssh #{instance[:dns_name]} "ls -1 #{app_path}db/migrate/*.rb | wc -l"`.strip
      local_migrations_count = `ls -1 #{Rails.root}/db/migrate/*.rb | wc -l`.strip

      if remote_migrations_count != local_migrations_count
        raise "O deploy possui novas migrations, você não pode usar a opção 'fast'!"
      end
    end
  end

  def aws_generate_launchconfig(branch)
    raise "CERTMAN_HOME not set" if ENV['CERTMAN_HOME'].blank?
    aws_inform "Gerando novo launchconfig usando o branch #{branch}..."
    aws_run "cd #{ENV['CERTMAN_HOME']} && . bin/activate && cd src && fab #{AwsDeploy.configuration.environment} deploy:#{File.dirname(Rails.root)},branch=#{branch}"
  end
  def aws_freeze_instance(instance_id)
    raise "CERTMAN_HOME not set" if ENV['CERTMAN_HOME'].blank?
    aws_inform "Executando freeze da instancia #{instance_id}..."
    aws_run "cd #{ENV['CERTMAN_HOME']} && . bin/activate && cd src && fab asg:#{AwsDeploy.configuration.autoscaling_name} freeze:instance_id=#{instance_id} --keepalive=15"
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
    AwsDeploy::Maintenance.new(credentials, AwsDeploy.configuration.path).on
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
    AwsDeploy::Cache.new(credentials, AwsDeploy.configuration.path).clear
  end
  def aws_get_current_instances_ids
    output = `as-describe-auto-scaling-groups #{AwsDeploy.configuration.autoscaling_name} --show-xml`
    xml = Nokogiri::XML.parse(output)
    ids = xml.search("AutoScalingGroups Instances member InstanceId").map(&:text)
    aws_inform "Nenhuma instância encontrada no auto-scaling-group" if ids.empty?
    ids
  end
  def aws_kill_instance(id)
    aws_inform "Terminando instância de id #{id}..."
    aws_run "as-terminate-instance-in-auto-scaling-group #{id} --no-decrement-desired-capacity --force"
  end
  def aws_wait_new_instance_show_as_inservice_on_loadbalancer(launchconfig, old_instance_ids)
    new_instance_id = nil
    while new_instance_id.nil? do
      output = `as-describe-auto-scaling-groups #{AwsDeploy.configuration.autoscaling_name} --show-xml`
      xml = Nokogiri::XML.parse(output)
      if xml.search("AutoScalingGroups Instances member").select { |i| i.at("LaunchConfigurationName").text == launchconfig }.size > 0
        new_instance_node = xml.search("AutoScalingGroups Instances member").select { |i| i.at("LaunchConfigurationName").text == launchconfig && !old_instance_ids.include?(i.at('InstanceId').text) }.first
        new_instance_id = new_instance_node.at('InstanceId').text unless new_instance_node.nil?
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
    min_size = 1 if min_size.to_i <= 0
    max_size = min_size if max_size.to_i < min_size.to_i

    aws_inform "'Re-ativando' auto-scaling..."
    aws_run "as-update-auto-scaling-group #{AwsDeploy.configuration.autoscaling_name} --min-size #{min_size} --max-size #{max_size} --desired-capacity #{desired_capacity}"
  end
  def aws_rds_create_snapshot
    db_name = AwsDeploy.configuration.rds_instance_identifier
    raise "Invalid RDS DB instance name" if (db_name.nil? || db_name == '')
    snapshot_name = "#{db_name}-#{Time.now.utc.strftime('%Y%m%d%H%M%S%Z')}"
    aws_inform "Criando novo snapshot do banco '#{db_name}' com nome '#{snapshot_name}'..."
    aws_run "rds-create-db-snapshot #{db_name} --db-snapshot-identifier #{snapshot_name}"
    snapshot_name
  end
  def aws_rds_wait_snapshot_creation(snapshot_name)
    status = nil
    until status == 'available' do
      output = `rds-describe-db-snapshots --db-snapshot-identifier #{snapshot_name} --show-xml`
      status = 'available' if output =~ /<Status>available<\/Status>/
      aws_inform "Esperando 10 segundos para snapshot '#{snapshot_name}' ficar disponível..."
      sleep 10
    end
    aws_inform "Snapshot '#{snapshot_name}' criado com sucesso."
  end
  def aws_get_last_launchconfig
    output = `as-describe-launch-configs --show-xml`
    xml = Nokogiri::XML.parse(output)
    xml.search('LaunchConfigurationName').last.text
  end
  def aws_rds_remove_old_snapshots
    db_name = AwsDeploy.configuration.rds_instance_identifier
    raise "Invalid RDS DB instance name" if (db_name.nil? || db_name == '')
    aws_inform "Buscando lista de snapshots existentes do banco '#{db_name}'..."
    output = `rds-describe-db-snapshots --db-instance-identifier #{db_name} --show-xml`
    xml = Nokogiri::XML.parse(output)
    snapshots = xml.search('DBSnapshots DBSnapshot').map do |node|
      time = node.at('SnapshotCreateTime').try(:text)
      time = Time.parse(time) unless (time.nil? || time == '')
      {
        snapshot_create_time: time,
        status: node.at('Status').try(:text),
        db_instance_identifier: node.at('DBInstanceIdentifier').try(:text),
        db_snapshot_identifier: node.at('DBSnapshotIdentifier').try(:text)
      }
    end
    avaiable_snapshots = snapshots.select { |h| h[:status] == 'available' }
    if avaiable_snapshots.size > 3
      avaiable_snapshots.sort_by { |h| h[:snapshot_create_time] }[3..-1].each do |snap|
        snapshot_name = snap[:db_snapshot_identifier]
        aws_inform "Apagando snapshot antigo '#{snapshot_name}'..."
        begin
          aws_run "rds-delete-db-snapshot #{snapshot_name} --force"
        rescue => e
          aws_inform "Não foi possível apagar o snapshot '#{snapshot_name}': #{e}"
        end
      end
    else
      aws_inform "Não é necessário apagar snapshots, há apenas #{avaiable_snapshots.size} atualmente."
    end
  end
  # -----------

  desc "Deploy to sandbox at Amazon"
  task :sandbox, :speed do |t, args|

    AWS_CONFIG ||= YAML::load(File.read('config/aws_deploy.yml'))["sandbox"]

    AwsDeploy.configure do |config|
      config.environment = AWS_CONFIG['environment']
      config.autoscaling_name = AWS_CONFIG['autoscaling_name']
      config.load_balancer_name = AWS_CONFIG['load_balancer_name']
      config.rds_instance_identifier = AWS_CONFIG['rds_instance_identifier']
      config.path = AWS_CONFIG['path']
    end

    args.with_defaults(:speed => 'normal')
    credentials = AwsDeploy::Credentials.new

    aws_check_new_migrations(credentials, AWS_CONFIG['path']) if args.speed == 'fast'

    if ENV['generate_launchconfig'] == 'on'
      aws_generate_launchconfig(get_current_branch)
    end

    launchconfig = aws_get_last_launchconfig

    new_launchconfig = aws_ask("Digite o nome do launchconfig gerado (e dê enter) [#{launchconfig}]")
    launchconfig = new_launchconfig unless new_launchconfig.blank?

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

      # configurar auto-scaling-group para usar novo launchconfig
      aws_update_autoscalint_to_use_new_launchconfig(launchconfig)

      # aws_clear_cache(credentials) # FIXME

      # pegar ids de todas as instâncias atuais no auto-scaling-group
      instance_ids = aws_get_current_instances_ids

      # matar primeira máquina existente
      aws_kill_instance(instance_ids.first) unless instance_ids.empty?

      # esperar uma nova máquina levantar e estar InService no elastic-load-balancer
      aws_wait_new_instance_show_as_inservice_on_loadbalancer(launchconfig, instance_ids)

      # matar todas as outras instâncias
      instance_ids.shift
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

  desc "Do freeze in one instance"
  task :freeze, [:instance_id, :env] do |t, args|
    options = args.with_defaults :env => 'sandbox'
    AWS_CONFIG ||= YAML::load(File.read('config/aws_deploy.yml'))[options[:env]]

    AwsDeploy.configure do |config|
      config.environment = AWS_CONFIG['environment']
      config.autoscaling_name = AWS_CONFIG['autoscaling_name']
      config.load_balancer_name = AWS_CONFIG['load_balancer_name']
      config.rds_instance_identifier = AWS_CONFIG['rds_instance_identifier']
      config.path = AWS_CONFIG['path']
    end

    raise "instance_id é obrigatório" unless options.has_key? :instance_id
    aws_freeze_instance(options[:instance_id])
  end


  desc "Deploy to production at Amazon"
  task :production, :speed do |t, args|

    AWS_CONFIG ||= YAML::load(File.read('config/aws_deploy.yml'))["production"]

    AwsDeploy.configure do |config|
      config.environment = AWS_CONFIG['environment']
      config.autoscaling_name = AWS_CONFIG['autoscaling_name']
      config.load_balancer_name = AWS_CONFIG['load_balancer_name']
      config.rds_instance_identifier = AWS_CONFIG['rds_instance_identifier']
      config.path = AWS_CONFIG['path']
    end

    args.with_defaults(:speed => 'normal')
    credentials = AwsDeploy::Credentials.new

    aws_check_new_migrations(credentials, AWS_CONFIG['path']) if args.speed == 'fast'

    if ENV['generate_launchconfig'] == 'on'
      aws_generate_launchconfig("master")
    end

    launchconfig = aws_get_last_launchconfig

    new_launchconfig = aws_ask("Digite o nome do launchconfig gerado (e dê enter) [#{launchconfig}]")
    launchconfig = new_launchconfig unless new_launchconfig.blank?

    old_autoscaling_min_size, old_autoscaling_max_size, old_autoscaling_desired_capacity = aws_get_old_autoscaling_settings

    begin
      aws_deactivate_autoscaling(old_autoscaling_desired_capacity)

      # verificar que não há nenhuma instância pending (subindo) no auto-scaling-group
      aws_query_all_instances_inservice_and_healthy_on_autoscaling

      # verificar que não há nenhuma instância fora de serviço no elastic-load-balancer
      aws_query_all_instances_inservice_on_load_balancer

      # tira snapshot (backup) do banco
      new_snapshot_name = aws_rds_create_snapshot

      # remove snapshots antigos (mantém apenas os últimos 3)
      aws_rds_remove_old_snapshots


      if args.speed != 'fast'
        aws_set_maintenance_on_for_all_instances(credentials)
      end

      aws_shut_down_all_workers_on_all_instances(credentials)

      # configurar auto-scaling-group para usar novo launchconfig
      aws_update_autoscalint_to_use_new_launchconfig(launchconfig)

      # aws_clear_cache(credentials) # FIXME

      # pegar ids de todas as instâncias atuais no auto-scaling-group
      instance_ids = aws_get_current_instances_ids

      # matar primeira máquina existente
      aws_kill_instance(instance_ids.first) unless instance_ids.empty?

      # esperar uma nova máquina levantar e estar InService no elastic-load-balancer
      aws_wait_new_instance_show_as_inservice_on_loadbalancer(launchconfig, instance_ids)

      # matar todas as outras instâncias
      instance_ids.shift
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
