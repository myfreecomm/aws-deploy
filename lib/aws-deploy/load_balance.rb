module AwsDeploy
  class LoadBalance
    def initialize(credentials, environment)
      @credentials = credentials
      @environment = environment
    end
    def instances
      raise "no environment given" if @environment.nil? || @environment == ""
      @ec2 = Aws::Ec2.new(@credentials.key, @credentials.token)
      instance_ids = Aws::Elb.new(@credentials.key, @credentials.token).describe_load_balancers({:names => [@environment]}).first[:instances].map{|i| i[:instance_id]}
      @ec2.describe_instances(instance_ids)
    end
  end
end