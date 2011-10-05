module AwsDeploy
  class LoadBalance
    def find_by_name(credentials, name)
      Aws::Elb.new(credentials.key, credentials.token).describe_load_balancers.detect {|lb| lb[:load_balancer_name] == name}
    end
  end
end