require 'aws'
require File.join(File.dirname(__FILE__), "aws-deploy/version")
require File.join(File.dirname(__FILE__), "aws-deploy/credentials")
require File.join(File.dirname(__FILE__), "aws-deploy/load_balance")
require File.join(File.dirname(__FILE__), "aws-deploy/maintenance")
require File.join(File.dirname(__FILE__), "aws-deploy/instance")
require File.join(File.dirname(__FILE__), "aws-deploy/workers")
require File.join(File.dirname(__FILE__), "aws-deploy/cache")

load File.join(File.dirname(__FILE__), "tasks/aws_deploy.rake")

module AwsDeploy
  class << self
    attr_accessor :configuration
  end

  def self.configure
    self.configuration ||= Configuration.new
    yield(configuration)
  end

  class Configuration
    attr_accessor :environment, :autoscaling_name, :load_balancer_name, :path, :rds_instance_identifier
  end
end
