module AwsDeploy
  class Workers
    def initialize(credentials, environment)
      @credentials = credentials
      @environment = environment
    end
    def stop
      Instance.new(@credentials, @environment).find_all_in_service.each do |instance|
        `ssh #{instance[:dns_name]} 'for i in /etc/init/application-work-*; do NAME=$(basename $i); sudo initctl stop ${NAME%.conf}; done'`
      end
    end
  end
end