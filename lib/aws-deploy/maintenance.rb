module AwsDeploy
  class Maintenance
    def initialize(credentials, path)
      @credentials = credentials
      @path = path
    end
    def on
      Instance.new(@credentials).find_all_in_service.each do |instance|
        `ssh #{instance[:dns_name]} 'sudo touch #{@path}/maintenance'`
      end
    end
    def off
      Instance.new(@credentials).find_all_in_service.each do |instance|
        `ssh #{instance[:dns_name]} 'sudo rm -f #{@path}/maintenance'`
      end
    end
  end
end