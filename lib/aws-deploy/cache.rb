module AwsDeploy
  class Cache
    def initialize(credentials, path)
      @credentials = credentials
      @path = path
    end
    
    def clear
      instance = Instance.new(@credentials).find_all_in_service.first
      `ssh #{instance[:dns_name]} 'cd #{@path} ; sudo RAILS_ENV=#{AwsDeploy.configuration.environment} /var/lib/gems/1.9.2/bin/bundle exec rake cache:clear'`
    end
  end
end
