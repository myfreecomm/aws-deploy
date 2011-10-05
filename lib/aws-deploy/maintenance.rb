module AwsDeploy
  class Maintenance
    def initialize(credentials, environment)
      @credentials = credentials
      @environment = environment
    end
    def on
      Instance.new(@credentials, @environment).find_all_in_service.each do |instance|
        `ssh #{instance[:dns_name]} 'sudo touch /srv/myfinance/src/maintenance'`
      end
    end
    def off
      Instance.new(@credentials, @environment).find_all_in_service.each do |instance|
        `ssh #{instance[:dns_name]} 'sudo rm -f /srv/myfinance/src/maintenance'`
      end
    end
  end
end