module AwsDeploy
  class LoadBalance
    def initialize(credentials)
      @credentials = credentials
    end
    def instances
      @ec2 = Aws::Ec2.new(@credentials.key, @credentials.token)
      instance_ids = Aws::Elb.new(@credentials.key, @credentials.token).describe_load_balancers({:names => [AwsDeploy.configuration.load_balancer_name]}).first[:instances].map{|i| i[:instance_id]}
      @ec2.describe_instances(instance_ids)
    end
  end
end