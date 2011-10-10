module AwsDeploy
  class Cache
    
    def initialize(credentials, environment)
      @credentials = credentials
      @environment = environment
    end
    
    def clear
      instance = Instance.new(@credentials, @environment).find_all_in_service.first
      `ssh #{instance[:dns_name]} 'cd /srv/myfinance/src ; sudo RAILS_ENV=#{project_environment} /var/lib/gems/1.9.2/bin/bundle exec rake cache:clear'`
    end
    
    private
    
      def project_environment
        @environment.split("-").last.downcase
      end
    
  end
end
